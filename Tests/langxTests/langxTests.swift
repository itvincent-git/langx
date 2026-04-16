import Foundation
import Testing
@testable import langx

@Test func supportedTargetsStayConstrained() async throws {
    #expect(TranslationLanguage.supportedTargets.map(\.code) == ["en", "zh-Hans"])
}

@Test func globalShortcutDefaultsToOff() async throws {
    #expect(AppPreferences().globalShortcutPreset == .off)
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
