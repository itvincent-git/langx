import Foundation

enum CodexTranslationDefaults {
    static let model = "gpt-5.4-mini"
}

actor CodexAppServerClient {
    private struct PendingRequest {
        let method: String
        let continuation: CheckedContinuation<Any, Error>
    }

    private struct ActiveTurn {
        let preferStreaming: Bool
        let onChunk: @Sendable (String) async -> Void
        let continuation: CheckedContinuation<TranslationRunOutput, Error>
        var turnID: String?
        var streamedText = ""
        var finalText = ""
        var hasExplicitFinalAnswer = false
        var usedStreaming = false
        var lastError: String?
    }

    private enum RequestID: Hashable {
        case int(Int)
        case string(String)

        init?(_ rawValue: Any) {
            switch rawValue {
            case let value as Int:
                self = .int(value)
            case let value as NSNumber:
                self = .int(value.intValue)
            case let value as String:
                self = .string(value)
            default:
                return nil
            }
        }

        var jsonValue: Any {
            switch self {
            case .int(let value):
                value
            case .string(let value):
                value
            }
        }
    }

    private let encoderQueue = DispatchQueue(label: "langx.codex-app-server.writer")
    private var currentExecutablePath: String?
    private var activeToken: UUID?
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutBuffer = ""
    private var stderrBuffer = Data()
    private var nextRequestID = 1
    private var pendingRequests: [RequestID: PendingRequest] = [:]
    private var activeTurns: [String: ActiveTurn] = [:]
    private var initialized = false
    private var logHandler: AppLogHandler = AppLogger.noop

    func translate(
        executablePath: String,
        workingDirectory: String,
        prompt: String,
        preferStreaming: Bool,
        onLog: @escaping AppLogHandler = AppLogger.noop,
        onChunk: @escaping @Sendable (String) async -> Void
    ) async throws -> TranslationRunOutput {
        logHandler = onLog
        await log(.info, "codex", "Preparing Codex app-server translation. cwd=\(workingDirectory) streaming=\(preferStreaming)")
        try await ensureServer(executablePath: executablePath)
        let threadID = try await createThread(workingDirectory: workingDirectory)
        await log(.debug, "codex", "Created thread \(threadID)")

        return try await withCheckedThrowingContinuation { continuation in
            activeTurns[threadID] = ActiveTurn(
                preferStreaming: preferStreaming,
                onChunk: onChunk,
                continuation: continuation
            )

            Task {
                do {
                    let turnID = try await self.startTurn(threadID: threadID, prompt: prompt)
                    self.attachTurnID(turnID, to: threadID)
                    await self.log(.debug, "codex", "Started turn \(turnID) for thread \(threadID)")
                } catch {
                    self.failTurn(threadID: threadID, error: error)
                }
            }
        }
    }

    func shutdown() {
        resetServerState(error: nil, terminateProcess: true)
    }

    private func ensureServer(executablePath: String) async throws {
        if initialized,
           currentExecutablePath == executablePath,
           process?.isRunning == true {
            await log(.debug, "codex", "Reusing running Codex app-server.")
            return
        }

        await log(.info, "codex", "Starting Codex app-server with executable \(executablePath)")
        resetServerState(
            error: TranslationServiceError.processLaunchFailed("Codex app-server restarted."),
            terminateProcess: true
        )

        let token = UUID()
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["app-server"]
        process.environment = ProcessInfo.processInfo.environment
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.terminationHandler = { [weak stdoutPipe, weak stderrPipe] process in
            let trailingStdout = stdoutPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
            let trailingStderr = stderrPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()

            Task {
                await self.handleTermination(
                    token: token,
                    status: process.terminationStatus,
                    trailingStdout: trailingStdout,
                    trailingStderr: trailingStderr
                )
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }

            Task {
                await self.handleStdout(data, token: token)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }

            Task {
                await self.handleStderr(data, token: token)
            }
        }

        do {
            try process.run()
        } catch {
            await log(.error, "codex", "Failed to start Codex app-server: \(error.localizedDescription)")
            throw TranslationServiceError.processLaunchFailed(error.localizedDescription)
        }

        currentExecutablePath = executablePath
        activeToken = token
        self.process = process
        stdinHandle = stdinPipe.fileHandleForWriting
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        stdoutBuffer.removeAll(keepingCapacity: false)
        stderrBuffer.removeAll(keepingCapacity: false)
        initialized = false

        do {
            _ = try await sendRequest(
                method: "initialize",
                params: [
                    "clientInfo": clientInfo(),
                    "capabilities": [
                        "experimentalApi": false,
                    ],
                ]
            )
            try await sendNotification(method: "initialized")
            initialized = true
            await log(.info, "codex", "Codex app-server initialized successfully.")
        } catch {
            resetServerState(error: error, terminateProcess: true)
            throw error
        }
    }

    private func createThread(workingDirectory: String) async throws -> String {
        let result = try await sendRequest(
            method: "thread/start",
            params: [
                "model": CodexTranslationDefaults.model,
                "cwd": workingDirectory,
                "approvalPolicy": "never",
                "sandbox": "read-only",
                "serviceName": "langx",
                "developerInstructions": Self.developerInstructions,
                "ephemeral": true,
                "experimentalRawEvents": false,
                "persistExtendedHistory": false,
            ]
        )

        guard let object = result as? [String: Any],
              let thread = object["thread"] as? [String: Any],
              let threadID = thread["id"] as? String,
              !threadID.isEmpty else {
            await log(.error, "codex.rpc", "Invalid response for thread/start.")
            throw TranslationServiceError.commandFailed("Codex app-server returned an invalid thread/start response.")
        }

        return threadID
    }

    private func startTurn(threadID: String, prompt: String) async throws -> String {
        let result = try await sendRequest(
            method: "turn/start",
            params: [
                "threadId": threadID,
                "input": [
                    [
                        "type": "text",
                        "text": prompt,
                        "text_elements": [],
                    ],
                ],
            ]
        )

        guard let object = result as? [String: Any],
              let turn = object["turn"] as? [String: Any],
              let turnID = turn["id"] as? String,
              !turnID.isEmpty else {
            await log(.error, "codex.rpc", "Invalid response for turn/start on thread \(threadID).")
            throw TranslationServiceError.commandFailed("Codex app-server returned an invalid turn/start response.")
        }

        return turnID
    }

    private func sendRequest(method: String, params: Any) async throws -> Any {
        let requestID = RequestID.int(nextRequestID)
        nextRequestID += 1
        await log(.debug, "codex.rpc", "-> \(method) id=\(requestID.jsonValue)")

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[requestID] = PendingRequest(method: method, continuation: continuation)

            do {
                try writeLine([
                    "id": requestID.jsonValue,
                    "method": method,
                    "params": params,
                ])
            } catch {
                pendingRequests.removeValue(forKey: requestID)
                continuation.resume(throwing: error)
            }
        }
    }

    private func sendNotification(method: String, params: Any? = nil) async throws {
        var object: [String: Any] = ["method": method]
        if let params {
            object["params"] = params
        }
        await log(.debug, "codex.rpc", "-> notification \(method)")
        try writeLine(object)
    }

    private func writeLine(_ object: [String: Any]) throws {
        guard let handle = stdinHandle else {
            throw TranslationServiceError.processLaunchFailed("Codex app-server stdin is unavailable.")
        }

        let data = try JSONSerialization.data(withJSONObject: object)

        encoderQueue.sync {
            handle.write(data)
            handle.write(Data([0x0A]))
        }
    }

    private func handleStdout(_ data: Data, token: UUID) async {
        guard token == activeToken else {
            return
        }

        await log(.debug, "codex.stdout", "\(data.count) bytes: \(DebugLogFormatter.preview(String(decoding: data, as: UTF8.self)))")
        stdoutBuffer += String(decoding: data, as: UTF8.self)

        while let newlineRange = stdoutBuffer.range(of: "\n") {
            let line = String(stdoutBuffer[..<newlineRange.lowerBound])
            stdoutBuffer.removeSubrange(..<newlineRange.upperBound)
            await handleMessageLine(line, token: token)
        }
    }

    private func handleStderr(_ data: Data, token: UUID) async {
        guard token == activeToken else {
            return
        }

        await log(.debug, "codex.stderr", "\(data.count) bytes: \(DebugLogFormatter.preview(String(decoding: data, as: UTF8.self)))")
        stderrBuffer.append(data)
    }

    private func handleTermination(
        token: UUID,
        status: Int32,
        trailingStdout: Data,
        trailingStderr: Data
    ) async {
        guard token == activeToken else {
            return
        }

        if !trailingStdout.isEmpty {
            await handleStdout(trailingStdout, token: token)
        }

        if !trailingStderr.isEmpty {
            await handleStderr(trailingStderr, token: token)
        }

        let stderrText = String(decoding: stderrBuffer, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = stderrText.isEmpty
            ? "Codex app-server exited with code \(status)."
            : stderrText
        await log(.error, "codex", "Codex app-server terminated. status=\(status) reason=\(DebugLogFormatter.preview(reason))")

        resetServerState(
            error: TranslationServiceError.commandFailed(reason),
            terminateProcess: false
        )
    }

    private func handleMessageLine(_ rawLine: String, token: UUID) async {
        guard token == activeToken else {
            return
        }

        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else {
            return
        }

        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            await log(.error, "codex.rpc", "Ignored non-JSON line from app-server: \(DebugLogFormatter.preview(line))")
            return
        }

        if let method = object["method"] as? String {
            if let rawID = object["id"], let requestID = RequestID(rawID) {
                await handleServerRequest(id: requestID, method: method)
                return
            }

            await handleNotification(method: method, params: object["params"])
            return
        }

        guard let rawID = object["id"], let requestID = RequestID(rawID) else {
            return
        }

        if let error = object["error"] as? [String: Any] {
            let message = (error["message"] as? String)
                ?? "Codex app-server request failed."
            if let request = pendingRequests.removeValue(forKey: requestID) {
                await log(.error, "codex.rpc", "<- \(request.method) id=\(requestID.jsonValue) error=\(message)")
                request.continuation.resume(
                    throwing: TranslationServiceError.commandFailed(message)
                )
            }
            return
        }

        if let result = object["result"] {
            if let request = pendingRequests.removeValue(forKey: requestID) {
                await log(.debug, "codex.rpc", "<- \(request.method) id=\(requestID.jsonValue) result received")
                request.continuation.resume(returning: result)
            }
        }
    }

    private func handleServerRequest(id: RequestID, method: String) async {
        let message = "Unsupported server request from Codex app-server: \(method)"
        await log(.error, "codex.rpc", message)
        try? writeLine([
            "id": id.jsonValue,
            "error": [
                "code": -32601,
                "message": message,
            ],
        ])
    }

    private func handleNotification(method: String, params: Any?) async {
        guard let params = params as? [String: Any],
              let threadID = params["threadId"] as? String else {
            return
        }

        switch method {
        case "item/agentMessage/delta":
            guard let delta = params["delta"] as? String,
                  var turn = activeTurns[threadID] else {
                return
            }

            await log(.debug, "codex.turn", "Delta for thread \(threadID): \(DebugLogFormatter.preview(delta))")

            if turn.turnID == nil {
                turn.turnID = params["turnId"] as? String
            }

            turn.streamedText += delta

            if turn.preferStreaming, !delta.isEmpty {
                turn.usedStreaming = true
                activeTurns[threadID] = turn
                await turn.onChunk(delta)
            } else {
                activeTurns[threadID] = turn
            }

        case "item/completed":
            guard let item = params["item"] as? [String: Any],
                  item["type"] as? String == "agentMessage",
                  let text = item["text"] as? String,
                  var turn = activeTurns[threadID] else {
                return
            }

            let phase = item["phase"] as? String
            if phase == "commentary" {
                return
            }

            await log(.debug, "codex.turn", "Completed item for thread \(threadID) phase=\(phase ?? "unknown")")

            if phase == "final_answer" {
                turn.hasExplicitFinalAnswer = true
                turn.finalText = text
            } else if !turn.hasExplicitFinalAnswer {
                turn.finalText = text
            }

            activeTurns[threadID] = turn

        case "error":
            guard let error = params["error"] as? [String: Any],
                  let message = error["message"] as? String,
                  var turn = activeTurns[threadID] else {
                return
            }

            turn.lastError = message
            activeTurns[threadID] = turn
            await log(.error, "codex.turn", "Thread \(threadID) reported error: \(message)")

        case "turn/completed":
            guard let turnPayload = params["turn"] as? [String: Any],
                  let status = turnPayload["status"] as? String else {
                return
            }

            await log(.info, "codex.turn", "Thread \(threadID) completed with status \(status)")

            await completeTurn(
                threadID: threadID,
                status: status,
                turnPayload: turnPayload
            )

        default:
            break
        }
    }

    private func completeTurn(
        threadID: String,
        status: String,
        turnPayload: [String: Any]
    ) async {
        guard let turn = activeTurns.removeValue(forKey: threadID) else {
            return
        }

        switch status {
        case "completed":
            let finalText = turn.finalText.isEmpty ? turn.streamedText : turn.finalText
            let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !trimmed.isEmpty else {
                await log(.error, "codex.turn", "Thread \(threadID) completed without translated text.")
                turn.continuation.resume(throwing: TranslationServiceError.emptyResponse)
                return
            }

            await log(.info, "codex.turn", "Thread \(threadID) succeeded. streamed=\(turn.preferStreaming && turn.usedStreaming) output=\(trimmed.count) chars")
            turn.continuation.resume(
                returning: TranslationRunOutput(
                    finalText: trimmed,
                    usedStreaming: turn.preferStreaming && turn.usedStreaming
                )
            )

        case "failed":
            let message: String

            if let error = turnPayload["error"] as? [String: Any],
               let errorMessage = error["message"] as? String,
               !errorMessage.isEmpty {
                message = errorMessage
            } else if let lastError = turn.lastError, !lastError.isEmpty {
                message = lastError
            } else {
                message = "Codex app-server turn failed."
            }

            await log(.error, "codex.turn", "Thread \(threadID) failed: \(message)")
            turn.continuation.resume(throwing: TranslationServiceError.commandFailed(message))

        case "interrupted":
            let message = turn.lastError ?? "Codex app-server turn was interrupted."
            await log(.error, "codex.turn", "Thread \(threadID) interrupted: \(message)")
            turn.continuation.resume(throwing: TranslationServiceError.commandFailed(message))

        default:
            await log(.error, "codex.turn", "Thread \(threadID) ended with unexpected status: \(status)")
            turn.continuation.resume(
                throwing: TranslationServiceError.commandFailed("Codex app-server ended with unexpected turn status: \(status)")
            )
        }
    }

    private func attachTurnID(_ turnID: String, to threadID: String) {
        guard var turn = activeTurns[threadID] else {
            return
        }

        turn.turnID = turnID
        activeTurns[threadID] = turn
    }

    private func failTurn(threadID: String, error: Error) {
        guard let turn = activeTurns.removeValue(forKey: threadID) else {
            return
        }

        Task {
            await self.log(.error, "codex.turn", "Failed to start turn for thread \(threadID): \(error.localizedDescription)")
        }
        turn.continuation.resume(throwing: error)
    }

    private func resetServerState(error: Error?, terminateProcess: Bool) {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        if terminateProcess, let process, process.isRunning {
            process.terminate()
        }

        for (_, request) in pendingRequests {
            request.continuation.resume(
                throwing: error ?? TranslationServiceError.processLaunchFailed("Codex app-server stopped.")
            )
        }
        pendingRequests.removeAll()

        for (_, turn) in activeTurns {
            turn.continuation.resume(
                throwing: error ?? TranslationServiceError.processLaunchFailed("Codex app-server stopped.")
            )
        }
        activeTurns.removeAll()

        try? stdinHandle?.close()
        stdinHandle = nil
        stdoutPipe = nil
        stderrPipe = nil
        process = nil
        currentExecutablePath = nil
        activeToken = nil
        initialized = false
        stdoutBuffer.removeAll(keepingCapacity: false)
        stderrBuffer.removeAll(keepingCapacity: false)
    }

    private func log(_ level: AppLogLevel, _ category: String, _ message: String) async {
        await logHandler(level, category, message)
    }

    private func clientInfo() -> [String: Any] {
        [
            "name": "langx",
            "title": "langx",
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev",
        ]
    }

    private static let developerInstructions = """
    You are the translation engine for a macOS app named langx.

    Requirements:
    - Return only the translated text.
    - Preserve paragraph breaks, markdown, code fences, inline code, bullets, numbers, and punctuation.
    - Do not add commentary, notes, quotes, prefixes, or labels.
    - Do not use tools, shell commands, web browsing, MCP servers, or external agents.
    """
}
