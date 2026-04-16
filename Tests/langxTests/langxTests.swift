import Foundation
import Testing
@testable import langx

@Test func supportedTargetsStayConstrained() async throws {
    #expect(TranslationLanguage.supportedTargets.map(\.code) == ["en", "zh-Hans"])
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
        wasStreamed: true,
        inputOrigin: .clipboard
    )

    let csv = AppStorage.exportCSV(records: [record])
    #expect(csv.contains("input_origin"))
    #expect(csv.contains("\"clipboard\""))
    #expect(csv.contains("\"hello, \"\"world\"\"\""))
    #expect(csv.contains("\"你好\n世界\""))
}

@Test func translationRecordDecodesLegacyHistoryWithoutInputOrigin() async throws {
    let data = Data(
        """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "sourceText": "hello",
          "translatedText": "你好",
          "sourceLanguageCode": "en",
          "targetLanguageCode": "zh-Hans",
          "engine": "codex",
          "createdAt": "1970-01-01T00:00:00Z",
          "wasStreamed": true
        }
        """.utf8
    )

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let record = try decoder.decode(TranslationRecord.self, from: data)

    #expect(record.inputOrigin == .manual)
}

@Test func debugLogPreviewNormalizesAndTruncates() async throws {
    #expect(DebugLogFormatter.preview("line1\nline2", limit: 20) == "line1\\nline2")
    #expect(DebugLogFormatter.preview("abcdefghijklmnopqrstuvwxyz", limit: 8) == "abcdefgh...")
}
