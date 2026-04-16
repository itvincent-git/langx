import Foundation

enum TranslationServiceError: LocalizedError {
    case executableNotFound(String)
    case processLaunchFailed(String)
    case commandFailed(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let path):
            "Executable not found: \(path)"
        case .processLaunchFailed(let reason):
            reason
        case .commandFailed(let reason):
            reason
        case .emptyResponse:
            "The selected CLI returned an empty translation."
        }
    }

    func localizedMessage(in language: InterfaceLanguage) -> String {
        switch (self, language) {
        case (.executableNotFound(let path), .simplifiedChinese):
            "未找到可执行文件：\(path)"
        case (.processLaunchFailed(let reason), .simplifiedChinese):
            "启动命令失败：\(reason)"
        case (.commandFailed(let reason), .simplifiedChinese):
            "翻译命令执行失败：\(reason)"
        case (.emptyResponse, .simplifiedChinese):
            "命令执行成功，但没有返回翻译内容。"
        default:
            errorDescription ?? "Translation failed."
        }
    }
}

final class CLITranslationService: @unchecked Sendable {
    private let fileManager = FileManager.default
    private let runner = ProcessRunner()
    private let codexClient = CodexAppServerClient()

    deinit {
        let codexClient = self.codexClient
        Task {
            await codexClient.shutdown()
        }
    }

    func findExecutable(for engine: TranslationEngine) -> String? {
        let pathComponents = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        let dynamicPaths = pathComponents.map { "\($0)/\(engine.executableName)" }
        let candidates = engine.candidatePaths + dynamicPaths

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }

        return nil
    }

    func translate(
        sourceText: String,
        sourceLanguage: TranslationLanguage,
        targetLanguage: TranslationLanguage,
        engine: TranslationEngine,
        executablePath: String,
        preferStreaming: Bool,
        onChunk: @escaping @Sendable (String) async -> Void
    ) async throws -> TranslationRunOutput {
        let executable = try resolveExecutable(engine: engine, customPath: executablePath)
        let prompt = makePrompt(
            sourceText: sourceText,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        )

        switch engine {
        case .codex:
            return try await runCodex(
                executable: executable,
                prompt: prompt,
                preferStreaming: preferStreaming,
                onChunk: onChunk
            )
        case .gemini:
            return try await runGemini(
                executable: executable,
                prompt: prompt,
                preferStreaming: preferStreaming,
                onChunk: onChunk
            )
        case .claude:
            return try await runClaude(
                executable: executable,
                prompt: prompt,
                preferStreaming: preferStreaming,
                onChunk: onChunk
            )
        }
    }

    private func resolveExecutable(engine: TranslationEngine, customPath: String) throws -> String {
        let trimmed = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            guard fileManager.isExecutableFile(atPath: trimmed) else {
                throw TranslationServiceError.executableNotFound(trimmed)
            }
            return trimmed
        }

        if let detected = findExecutable(for: engine) {
            return detected
        }

        throw TranslationServiceError.executableNotFound(engine.executableName)
    }

    private func runCodex(
        executable: String,
        prompt: String,
        preferStreaming: Bool,
        onChunk: @escaping @Sendable (String) async -> Void
    ) async throws -> TranslationRunOutput {
        try await codexClient.translate(
            executablePath: executable,
            workingDirectory: fileManager.homeDirectoryForCurrentUser.path,
            prompt: prompt,
            preferStreaming: preferStreaming,
            onChunk: onChunk
        )
    }

    private func runGemini(
        executable: String,
        prompt: String,
        preferStreaming: Bool,
        onChunk: @escaping @Sendable (String) async -> Void
    ) async throws -> TranslationRunOutput {
        let parser = StreamParserBox()
        let format = preferStreaming ? "stream-json" : "text"

        let result = try await runner.run(
            executablePath: executable,
            arguments: [
                "--prompt", prompt,
                "--approval-mode", "plan",
                "--output-format", format,
            ]
        ) { chunk in
            guard preferStreaming else {
                return
            }
            let deltas = await parser.ingest(chunk)
            for delta in deltas where !delta.isEmpty {
                await onChunk(delta)
            }
        }

        guard result.exitCode == 0 else {
            throw TranslationServiceError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }

        let finalText = preferStreaming
            ? await parser.finalize(stdout: result.stdout)
            : bestEffortFinalText(from: result.stdout)

        guard !finalText.isEmpty else {
            throw TranslationServiceError.emptyResponse
        }

        let usedStreaming = preferStreaming ? await parser.emitted : false
        return TranslationRunOutput(finalText: finalText, usedStreaming: usedStreaming)
    }

    private func runClaude(
        executable: String,
        prompt: String,
        preferStreaming: Bool,
        onChunk: @escaping @Sendable (String) async -> Void
    ) async throws -> TranslationRunOutput {
        let parser = StreamParserBox()
        let format = preferStreaming ? "stream-json" : "text"

        let result = try await runner.run(
            executablePath: executable,
            arguments: [
                "--print",
                "--output-format", format,
                prompt,
            ]
        ) { chunk in
            guard preferStreaming else {
                return
            }
            let deltas = await parser.ingest(chunk)
            for delta in deltas where !delta.isEmpty {
                await onChunk(delta)
            }
        }

        guard result.exitCode == 0 else {
            throw TranslationServiceError.commandFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }

        let finalText = preferStreaming
            ? await parser.finalize(stdout: result.stdout)
            : bestEffortFinalText(from: result.stdout)

        guard !finalText.isEmpty else {
            throw TranslationServiceError.emptyResponse
        }

        let usedStreaming = preferStreaming ? await parser.emitted : false
        return TranslationRunOutput(finalText: finalText, usedStreaming: usedStreaming)
    }

    private func makePrompt(
        sourceText: String,
        sourceLanguage: TranslationLanguage,
        targetLanguage: TranslationLanguage
    ) -> String {
        """
        You are a translation engine inside a macOS app named langx.

        Requirements:
        - Translate the user's text into \(targetLanguage.englishName).
        - Source language is \(sourceLanguage.isAutomatic ? "auto-detected" : sourceLanguage.englishName).
        - Return only the translated text.
        - Preserve paragraph breaks, markdown, code fences, inline code, bullets, numbers, and punctuation.
        - Do not add explanations, notes, quotes, prefixes, or labels.
        - Do not use tools, shell commands, or web browsing.

        SOURCE TEXT START
        \(sourceText)
        SOURCE TEXT END
        """
    }

    private func bestEffortFinalText(from rawOutput: String) -> String {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let longest = JSONLineStreamParser.longestTextCandidate(in: object) {
            return longest.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var parser = JSONLineStreamParser()
        _ = parser.ingest(trimmed + "\n")
        let parsed = parser.finalize(stdout: trimmed)
        return parsed.isEmpty ? trimmed : parsed
    }
}

private struct ProcessRunResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
}

private final class ProcessRunner: @unchecked Sendable {
    func run(
        executablePath: String,
        arguments: [String],
        stdin: String? = nil,
        onStdout: @escaping @Sendable (String) async -> Void
    ) async throws -> ProcessRunResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let stdinPipe = Pipe()
            let state = ProcessState()

            let finish: @Sendable (Result<ProcessRunResult, Error>) -> Void = { result in
                guard state.finish() else {
                    return
                }
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(with: result)
            }

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    return
                }

                state.appendStdout(data)
                let chunk = String(decoding: data, as: UTF8.self)
                Task {
                    await onStdout(chunk)
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    return
                }
                state.appendStderr(data)
            }

            process.terminationHandler = { process in
                let trailingOut = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let trailingErr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                if !trailingOut.isEmpty {
                    state.appendStdout(trailingOut)
                    let chunk = String(decoding: trailingOut, as: UTF8.self)
                    Task {
                        await onStdout(chunk)
                    }
                }

                if !trailingErr.isEmpty {
                    state.appendStderr(trailingErr)
                }

                finish(
                    .success(
                        ProcessRunResult(
                            stdout: state.stdoutString,
                            stderr: state.stderrString,
                            exitCode: process.terminationStatus
                        )
                    )
                )
            }

            do {
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments
                process.environment = ProcessInfo.processInfo.environment
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                if stdin != nil {
                    process.standardInput = stdinPipe
                }

                try process.run()

                if let stdin {
                    stdinPipe.fileHandleForWriting.write(Data(stdin.utf8))
                    try? stdinPipe.fileHandleForWriting.close()
                }
            } catch {
                finish(.failure(TranslationServiceError.processLaunchFailed(error.localizedDescription)))
            }
        }
    }
}

private actor StreamParserBox {
    private var parser = JSONLineStreamParser()

    func ingest(_ chunk: String) -> [String] {
        parser.ingest(chunk)
    }

    func finalize(stdout: String) -> String {
        parser.finalize(stdout: stdout)
    }

    var emitted: Bool {
        parser.emitted
    }
}

private final class ProcessState: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var didFinish = false

    var stdoutString: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: stdout, as: UTF8.self)
    }

    var stderrString: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: stderr, as: UTF8.self)
    }

    func appendStdout(_ data: Data) {
        lock.lock()
        stdout.append(data)
        lock.unlock()
    }

    func appendStderr(_ data: Data) {
        lock.lock()
        stderr.append(data)
        lock.unlock()
    }

    func finish() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didFinish else {
            return false
        }
        didFinish = true
        return true
    }
}

private struct JSONLineStreamParser {
    private static let interestingKeys: Set<String> = [
        "text",
        "delta",
        "content",
        "output_text",
        "completion",
        "result",
    ]

    private var buffer = ""
    private var rendered = ""
    var emitted = false

    mutating func ingest(_ chunk: String) -> [String] {
        buffer += chunk
        var deltas: [String] = []

        while let newlineRange = buffer.range(of: "\n") {
            let line = String(buffer[..<newlineRange.lowerBound])
            buffer.removeSubrange(..<newlineRange.upperBound)
            deltas.append(contentsOf: processLine(line))
        }

        return deltas
    }

    mutating func finalize(stdout: String) -> String {
        if !buffer.isEmpty {
            _ = processLine(buffer)
            buffer.removeAll(keepingCapacity: false)
        }

        let trimmedRendered = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRendered.isEmpty {
            return trimmedRendered
        }

        let trimmedStdout = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmedStdout.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let longest = Self.longestTextCandidate(in: object) {
            return longest.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmedStdout
    }

    mutating private func processLine(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return absorb(candidate: trimmed).map { [$0] } ?? []
        }

        let candidates = Self.textCandidates(in: object)
        var deltas: [String] = []

        for candidate in candidates {
            if let delta = absorb(candidate: candidate) {
                deltas.append(delta)
            }
        }

        return deltas
    }

    mutating private func absorb(candidate: String) -> String? {
        let normalized = candidate.replacingOccurrences(of: "\r\n", with: "\n")
        guard !normalized.isEmpty else {
            return nil
        }

        if normalized == rendered || rendered.hasSuffix(normalized) {
            return nil
        }

        if normalized.hasPrefix(rendered) {
            let delta = String(normalized.dropFirst(rendered.count))
            rendered = normalized
            if !delta.isEmpty {
                emitted = true
                return delta
            }
            return nil
        }

        if rendered.hasPrefix(normalized) {
            return nil
        }

        rendered += normalized
        emitted = true
        return normalized
    }

    static func longestTextCandidate(in object: Any) -> String? {
        textCandidates(in: object)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .max(by: { $0.count < $1.count })
    }

    private static func textCandidates(in value: Any, parentKey: String? = nil) -> [String] {
        switch value {
        case let string as String:
            guard let parentKey, interestingKeys.contains(parentKey) else {
                return []
            }
            return [string]
        case let dictionary as [String: Any]:
            return dictionary.flatMap { key, child in
                textCandidates(in: child, parentKey: key)
            }
        case let array as [Any]:
            return array.flatMap { item in
                textCandidates(in: item, parentKey: parentKey)
            }
        default:
            return []
        }
    }
}
