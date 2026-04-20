import Foundation
import Testing
@testable import langx

private struct MockTranslationService: TranslationServing {
    let result: TranslationRunOutput
    let onTranslate: @Sendable () -> Void

    init(
        result: TranslationRunOutput = TranslationRunOutput(finalText: "translated", usedStreaming: false),
        onTranslate: @escaping @Sendable () -> Void = {}
    ) {
        self.result = result
        self.onTranslate = onTranslate
    }

    func findExecutable(for engine: TranslationEngine) -> String? {
        "/usr/bin/\(engine.executableName)"
    }

    func translate(
        sourceText: String,
        sourceLanguage: TranslationLanguage,
        targetLanguage: TranslationLanguage,
        engine: TranslationEngine,
        executablePath: String,
        preferStreaming: Bool,
        onLog: @escaping AppLogHandler,
        onChunk: @escaping @Sendable (String) async -> Void
    ) async throws -> TranslationRunOutput {
        onTranslate()
        await onChunk(result.finalText)
        return result
    }
}

private struct MockSelectedTextProvider: SelectedTextProvider {
    let result: Result<String, SelectedTextCaptureError>

    func captureSelectedText() async throws -> String {
        try result.get()
    }
}

@Test func supportedTargetsStayConstrained() async throws {
    #expect(TranslationLanguage.supportedTargets.map(\.code) == ["en", "zh-Hans"])
}

@Test func globalShortcutDefaultsToOff() async throws {
    #expect(AppPreferences().globalShortcutPreset == .off)
    #expect(AppPreferences().selectionTranslationShortcutPreset == .off)
}

@Test func globalShortcutPresetsStayStable() async throws {
    #expect(GlobalShortcutPreset.allCases.map(\.rawValue) == [
        "off",
        "optionSpace",
        "commandShiftSpace",
        "controlOptionSpace",
    ])
}

@Test func codexTranslationUsesCostEffectiveModel() async throws {
    #expect(CodexTranslationDefaults.model == "gpt-5.4-mini")
}

@Test func csvExportEscapesQuotes() async throws {
    let record = TranslationRecord(
        sourceText: "hello, \"world\"",
        translatedText: "你好\n世界",
        sourceLanguageCode: "en",
        targetLanguageCode: "zh-Hans",
        engine: .codex,
        createdAt: Date(timeIntervalSince1970: 0),
        wasStreamed: true
    )

    let csv = AppStorage.exportCSV(records: [record])
    #expect(csv.contains("\"hello, \"\"world\"\"\""))
    #expect(csv.contains("\"你好\n世界\""))
}

@Test func debugLogPreviewNormalizesAndTruncates() async throws {
    #expect(DebugLogFormatter.preview("line1\nline2", limit: 20) == "line1\\nline2")
    #expect(DebugLogFormatter.preview("abcdefghijklmnopqrstuvwxyz", limit: 8) == "abcdefgh...")
}

@Test func processExecutionEnvironmentPrependsExecutableAndDeduplicatesPaths() async throws {
    let components = ProcessExecutionEnvironment.mergedPathComponents(
        basePath: "/usr/bin:/bin:/usr/local/bin",
        executablePath: "/opt/homebrew/bin/codex",
        additionalDirectories: [
            "/Users/test/.nvm/versions/node/v24.11.0/bin",
            "/usr/local/bin",
            "/usr/bin",
        ]
    )

    #expect(components == [
        "/opt/homebrew/bin",
        "/Users/test/.nvm/versions/node/v24.11.0/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
    ])
}

@Test func processExecutionEnvironmentImportsWhitelistedShellVariables() async throws {
    let merged = ProcessExecutionEnvironment.mergedBaseEnvironment(
        ["USER": "vincent"],
        shellEnvironment: [
            "HTTP_PROXY": "http://127.0.0.1:7897",
            "HTTPS_PROXY": "http://127.0.0.1:7897",
            "ALL_PROXY": "socks5://127.0.0.1:7897",
            "OPENAI_API_KEY": "token",
            "PATH": "/custom/bin:/usr/bin",
            "FOO": "bar",
        ]
    )

    #expect(merged["USER"] == "vincent")
    #expect(merged["HTTP_PROXY"] == "http://127.0.0.1:7897")
    #expect(merged["HTTPS_PROXY"] == "http://127.0.0.1:7897")
    #expect(merged["ALL_PROXY"] == "socks5://127.0.0.1:7897")
    #expect(merged["OPENAI_API_KEY"] == "token")
    #expect(merged["PATH"] == "/custom/bin:/usr/bin")
    #expect(merged["FOO"] == nil)
}

@Test func processExecutionEnvironmentPreservesExistingVariablesOverShellValues() async throws {
    let merged = ProcessExecutionEnvironment.mergedBaseEnvironment(
        [
            "HTTP_PROXY": "http://existing:7890",
            "PATH": "/existing/bin:/usr/bin",
        ],
        shellEnvironment: [
            "HTTP_PROXY": "http://shell:7897",
            "PATH": "/shell/bin:/usr/bin",
        ]
    )

    #expect(merged["HTTP_PROXY"] == "http://existing:7890")
    #expect(merged["PATH"] == "/existing/bin:/usr/bin")
}

@Test func userShellEnvironmentParsesNullSeparatedOutput() async throws {
    let data = Data("HTTP_PROXY=http://127.0.0.1:7897\0PATH=/usr/bin:/bin\0INVALID\0".utf8)
    let parsed = UserShellEnvironment.parseEnvironmentOutput(data)

    #expect(parsed["HTTP_PROXY"] == "http://127.0.0.1:7897")
    #expect(parsed["PATH"] == "/usr/bin:/bin")
    #expect(parsed["INVALID"] == nil)
}

@Test func codexAppServerStreamDisconnectTriggersFallback() async throws {
    let service = CLITranslationService()

    #expect(service.shouldFallbackFromCodexAppServer(
        TranslationServiceError.commandFailed("Reconnecting... 2/5")
    ))
    #expect(service.shouldFallbackFromCodexAppServer(
        TranslationServiceError.commandFailed("timeout waiting for model response stream")
    ))
    #expect(!service.shouldFallbackFromCodexAppServer(
        TranslationServiceError.emptyResponse
    ))
}

@Test func appPreferencesDecodeLegacyPayloadWithSelectionShortcutDefault() async throws {
    let data = """
    {
      "customExecutablePaths": {},
      "defaultTargetLanguage": {
        "chineseName": "英文",
        "code": "en",
        "englishName": "English",
        "isAutomatic": false
      },
      "globalShortcutPreset": "optionSpace",
      "interfaceLanguage": "zh-Hans",
      "preferStreaming": false,
      "selectedEngine": "claude"
    }
    """.data(using: .utf8)!

    let decoded = try JSONDecoder().decode(AppPreferences.self, from: data)
    #expect(decoded.globalShortcutPreset == .optionSpace)
    #expect(decoded.selectionTranslationShortcutPreset == .off)
    #expect(decoded.selectedEngine == .claude)
}

@Test func selectedTextCaptureServiceFallsBackAfterAccessibilityFailure() async throws {
    let service = SelectedTextCaptureService(providers: [
        MockSelectedTextProvider(result: .failure(.permissionDenied)),
        MockSelectedTextProvider(result: .success("hello world")),
    ])

    let text = try await service.captureSelectedText()
    #expect(text == "hello world")
}

@Test func selectedTextCaptureServicePrefersEmptySelectionError() async throws {
    let service = SelectedTextCaptureService(providers: [
        MockSelectedTextProvider(result: .failure(.permissionDenied)),
        MockSelectedTextProvider(result: .failure(.emptySelection)),
    ])

    await #expect(throws: SelectedTextCaptureError.emptySelection) {
        try await service.captureSelectedText()
    }
}

@MainActor
@Test func prepareTranslationAutoTranslateFillsSourceAndRunsTranslation() async throws {
    let storageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let storage = AppStorage(baseURL: storageURL)
    let model = AppModel(
        storage: storage,
        translator: MockTranslationService(),
        bootstrapOnInit: false
    )

    model.prepareTranslation(sourceText: "hello", autoTranslate: true)

    for _ in 0..<20 where model.translatedText.isEmpty {
        try await Task.sleep(for: .milliseconds(25))
    }

    #expect(model.sourceText == "hello")
    #expect(model.translatedText == "translated")
    #expect(model.errorMessage == nil)
}

@MainActor
@Test func prepareTranslationWithoutAutoTranslateOnlyStagesSource() async throws {
    let storageURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let storage = AppStorage(baseURL: storageURL)
    let model = AppModel(
        storage: storage,
        translator: MockTranslationService(),
        bootstrapOnInit: false
    )

    model.translatedText = "stale"
    model.errorMessage = "old"
    model.prepareTranslation(sourceText: "draft", autoTranslate: false)

    #expect(model.sourceText == "draft")
    #expect(model.translatedText.isEmpty)
    #expect(model.errorMessage == nil)
    #expect(model.isTranslating == false)
}
