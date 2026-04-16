import AppKit
import Foundation
import NaturalLanguage
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case translate
    case history
    case logs
    case settings

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .translate: "translate"
        case .history: "clock.arrow.circlepath"
        case .logs: "text.alignleft"
        case .settings: "slider.horizontal.3"
        }
    }
}

enum InterfaceLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }
    var localeIdentifier: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "中文"
        }
    }
}

enum TranslationEngine: String, CaseIterable, Codable, Identifiable, Sendable {
    case codex
    case gemini
    case claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: "Codex CLI"
        case .gemini: "Gemini CLI"
        case .claude: "Claude Code"
        }
    }

    var executableName: String {
        switch self {
        case .codex: "codex"
        case .gemini: "gemini"
        case .claude: "claude"
        }
    }

    var candidatePaths: [String] {
        switch self {
        case .codex, .gemini:
            [
                "/Users/\(NSUserName())/.nvm/versions/node/v24.11.0/bin/\(executableName)",
                "/opt/homebrew/bin/\(executableName)",
                "/usr/local/bin/\(executableName)",
                "/usr/bin/\(executableName)",
            ]
        case .claude:
            [
                "/usr/local/bin/claude",
                "/opt/homebrew/bin/claude",
                "/usr/bin/claude",
            ]
        }
    }
}

enum GlobalShortcutPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case off
    case optionSpace
    case commandShiftSpace
    case controlOptionSpace

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .off: "settings.shortcut.off"
        case .optionSpace: "settings.shortcut.option_space"
        case .commandShiftSpace: "settings.shortcut.command_shift_space"
        case .controlOptionSpace: "settings.shortcut.control_option_space"
        }
    }
}

struct TranslationLanguage: Codable, Hashable, Identifiable, Sendable {
    let code: String
    let englishName: String
    let chineseName: String
    let isAutomatic: Bool

    var id: String { code }

    static let automatic = TranslationLanguage(
        code: "auto",
        englishName: "Auto-detect",
        chineseName: "自动识别",
        isAutomatic: true
    )

    static let english = TranslationLanguage(
        code: "en",
        englishName: "English",
        chineseName: "英文",
        isAutomatic: false
    )

    static let simplifiedChinese = TranslationLanguage(
        code: "zh-Hans",
        englishName: "Simplified Chinese",
        chineseName: "简体中文",
        isAutomatic: false
    )

    static let supportedTargets: [TranslationLanguage] = [
        .english,
        .simplifiedChinese,
    ]

    static func fromDetected(code rawCode: String?) -> TranslationLanguage {
        guard let rawCode else {
            return TranslationLanguage(
                code: "und",
                englishName: "Unknown",
                chineseName: "未知",
                isAutomatic: false
            )
        }

        let normalized: String
        switch rawCode.lowercased() {
        case "zh", "zh-hans", "zh-cn", "cmn-hans":
            normalized = "zh-Hans"
        case "en", "en-us", "en-gb":
            normalized = "en"
        case "auto":
            return .automatic
        default:
            normalized = rawCode
        }

        switch normalized {
        case english.code:
            return .english
        case simplifiedChinese.code:
            return .simplifiedChinese
        default:
            let englishLocale = Locale(identifier: "en")
            let chineseLocale = Locale(identifier: "zh-Hans")
            return TranslationLanguage(
                code: normalized,
                englishName: englishLocale.localizedString(forIdentifier: normalized) ?? normalized.uppercased(),
                chineseName: chineseLocale.localizedString(forIdentifier: normalized) ?? normalized.uppercased(),
                isAutomatic: false
            )
        }
    }

    func localizedName(in interfaceLanguage: InterfaceLanguage) -> String {
        switch interfaceLanguage {
        case .english: englishName
        case .simplifiedChinese: chineseName
        }
    }
}

struct AppPreferences: Codable, Sendable {
    var selectedEngine: TranslationEngine = .codex
    var defaultTargetLanguage: TranslationLanguage = .english
    var interfaceLanguage: InterfaceLanguage = .english
    var preferStreaming: Bool = true
    var globalShortcutPreset: GlobalShortcutPreset = .off
    var customExecutablePaths: [String: String] = [:]

    mutating func setExecutablePath(_ path: String, for engine: TranslationEngine) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            customExecutablePaths.removeValue(forKey: engine.rawValue)
        } else {
            customExecutablePaths[engine.rawValue] = trimmed
        }
    }

    func executablePath(for engine: TranslationEngine) -> String {
        customExecutablePaths[engine.rawValue] ?? ""
    }
}

struct TranslationRecord: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let sourceText: String
    let translatedText: String
    let sourceLanguageCode: String
    let targetLanguageCode: String
    let engine: TranslationEngine
    let createdAt: Date
    let wasStreamed: Bool

    init(
        id: UUID = UUID(),
        sourceText: String,
        translatedText: String,
        sourceLanguageCode: String,
        targetLanguageCode: String,
        engine: TranslationEngine,
        createdAt: Date,
        wasStreamed: Bool
    ) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.sourceLanguageCode = sourceLanguageCode
        self.targetLanguageCode = targetLanguageCode
        self.engine = engine
        self.createdAt = createdAt
        self.wasStreamed = wasStreamed
    }

    var sourceLanguage: TranslationLanguage {
        TranslationLanguage.fromDetected(code: sourceLanguageCode)
    }

    var targetLanguage: TranslationLanguage {
        TranslationLanguage.fromDetected(code: targetLanguageCode)
    }
}

struct HistorySection: Identifiable {
    let id: String
    let title: String
    let records: [TranslationRecord]
}

struct TranslationRunOutput: Sendable {
    let finalText: String
    let usedStreaming: Bool
}

struct LanguageDetector {
    func detect(_ text: String) -> TranslationLanguage {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .automatic
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        return TranslationLanguage.fromDetected(code: recognizer.dominantLanguage?.rawValue)
    }
}

enum Localizer {
    static func string(_ key: String, language: InterfaceLanguage, _ arguments: [CVarArg] = []) -> String {
        let bundle = bundle(for: language)
        let value = bundle.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else {
            return value
        }
        return String(format: value, locale: Locale(identifier: language.localeIdentifier), arguments: arguments)
    }

    private static func bundle(for language: InterfaceLanguage) -> Bundle {
        if let path = Bundle.module.path(forResource: language.rawValue, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .module
    }
}

actor AppStorage {
    static let shared = AppStorage()

    private let fileManager: FileManager
    private let historyURL: URL
    private let preferencesURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        let fileManager = FileManager.default
        self.fileManager = fileManager
        let supportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let baseURL: URL
        if let supportURL {
            baseURL = supportURL.appendingPathComponent("langx", isDirectory: true)
        } else {
            baseURL = fileManager.temporaryDirectory.appendingPathComponent("langx", isDirectory: true)
        }

        historyURL = baseURL.appendingPathComponent("history.json")
        preferencesURL = baseURL.appendingPathComponent("preferences.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadHistory() -> [TranslationRecord] {
        load([TranslationRecord].self, from: historyURL) ?? []
    }

    func saveHistory(_ records: [TranslationRecord]) {
        save(records, to: historyURL)
    }

    func loadPreferences() -> AppPreferences {
        load(AppPreferences.self, from: preferencesURL) ?? AppPreferences()
    }

    func savePreferences(_ preferences: AppPreferences) {
        save(preferences, to: preferencesURL)
    }

    private func ensureDirectory() {
        let directory = historyURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        ensureDirectory()
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decoder.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to url: URL) {
        ensureDirectory()
        guard let data = try? encoder.encode(value) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    static func exportCSV(records: [TranslationRecord]) -> String {
        let header = [
            "timestamp",
            "engine",
            "source_language",
            "target_language",
            "streamed",
            "source_text",
            "translated_text",
        ].joined(separator: ",")

        let formatter = ISO8601DateFormatter()
        let lines = records.map { record in
            [
                escapeCSV(formatter.string(from: record.createdAt)),
                escapeCSV(record.engine.displayName),
                escapeCSV(record.sourceLanguageCode),
                escapeCSV(record.targetLanguageCode),
                escapeCSV(record.wasStreamed ? "true" : "false"),
                escapeCSV(record.sourceText),
                escapeCSV(record.translatedText),
            ].joined(separator: ",")
        }

        return ([header] + lines).joined(separator: "\n")
    }

    private static func escapeCSV(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

extension Color {
    static let langxBackground = Color(hex: 0xF9F9FE)
    static let langxSidebar = Color(hex: 0xF3F3F8)
    static let langxCard = Color.white
    static let langxSurface = Color(hex: 0xEDEDF2)
    static let langxSurfaceHigh = Color(hex: 0xE8E8ED)
    static let langxOutline = Color(hex: 0xC1C6D7)
    static let langxPrimary = Color(hex: 0x0058BC)
    static let langxPrimaryAlt = Color(hex: 0x0070EB)
    static let langxText = Color(hex: 0x1A1C1F)
    static let langxSubtext = Color(hex: 0x414755)
    static let langxTertiary = Color(hex: 0x9E3D00)

    init(hex: UInt32, alpha: Double = 1) {
        let red = Double((hex & 0xFF0000) >> 16) / 255
        let green = Double((hex & 0x00FF00) >> 8) / 255
        let blue = Double(hex & 0x0000FF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

extension LinearGradient {
    static let langxPrimary = LinearGradient(
        colors: [.langxPrimary, .langxPrimaryAlt],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension View {
    func langxCardStyle(padding: CGFloat = 24) -> some View {
        self
            .padding(padding)
            .background(Color.langxCard)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 18, x: 0, y: 8)
    }
}
