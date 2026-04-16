import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    private static let maxLogEntries = 500

    @Published var preferences = AppPreferences()
    @Published var activeSection: AppSection = .translate
    @Published var sourceText = ""
    @Published var translatedText = ""
    @Published var detectedSourceLanguage: TranslationLanguage = .automatic
    @Published var history: [TranslationRecord] = []
    @Published var selectedHistoryID: UUID?
    @Published var searchText = ""
    @Published var logs: [AppLogEntry] = []
    @Published var isTranslating = false
    @Published var errorMessage: String?
    @Published private(set) var quickTranslateActivationToken = UUID()

    private let storage: AppStorage
    private let detector: LanguageDetector
    private let translator: CLITranslationService
    private var detectionTask: Task<Void, Never>?
    private var currentInputOrigin: TranslationInputOrigin = .manual

    init(
        storage: AppStorage = .shared,
        detector: LanguageDetector = LanguageDetector(),
        translator: CLITranslationService = CLITranslationService()
    ) {
        self.storage = storage
        self.detector = detector
        self.translator = translator

        Task {
            await bootstrap()
        }
    }

    func bootstrap() async {
        preferences = await storage.loadPreferences()
        history = await storage.loadHistory()
        selectedHistoryID = history.first?.id
        detectedSourceLanguage = detector.detect(sourceText)
    }

    func t(_ key: String, _ arguments: CVarArg...) -> String {
        Localizer.string(key, language: preferences.interfaceLanguage, arguments)
    }

    var selectedRecord: TranslationRecord? {
        history.first(where: { $0.id == selectedHistoryID })
    }

    var recentHistory: [TranslationRecord] {
        Array(history.prefix(3))
    }

    var filteredHistory: [TranslationRecord] {
        let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            return history
        }

        return history.filter { record in
            record.sourceText.localizedCaseInsensitiveContains(term)
                || record.translatedText.localizedCaseInsensitiveContains(term)
                || record.engine.displayName.localizedCaseInsensitiveContains(term)
        }
    }

    var historySections: [HistorySection] {
        let grouped = Dictionary(grouping: filteredHistory) { record in
            Calendar.current.startOfDay(for: record.createdAt)
        }

        return grouped
            .keys
            .sorted(by: >)
            .map { day in
                HistorySection(
                    id: ISO8601DateFormatter().string(from: day),
                    title: sectionTitle(for: day),
                    records: grouped[day, default: []].sorted(by: { $0.createdAt > $1.createdAt })
                )
            }
    }

    func sectionLabel(for section: AppSection) -> String {
        switch section {
        case .translate:
            t("section.translate")
        case .history:
            t("section.history")
        case .logs:
            t("section.logs")
        case .settings:
            t("section.settings")
        }
    }

    func updateSourceText(_ text: String) {
        sourceText = text
        scheduleDetection()
    }

    func clearSourceText() {
        detectionTask?.cancel()
        sourceText = ""
        detectedSourceLanguage = .automatic
        errorMessage = nil
        currentInputOrigin = .manual
    }

    func scheduleDetection() {
        detectionTask?.cancel()
        let currentText = sourceText

        detectionTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else {
                return
            }

            let detected = detector.detect(currentText)
            await MainActor.run {
                guard currentText == self.sourceText else {
                    return
                }
                self.detectedSourceLanguage = detected
            }
        }
    }

    func selectEngine(_ engine: TranslationEngine) {
        preferences.selectedEngine = engine
        persistPreferences()
    }

    func selectTargetLanguage(_ language: TranslationLanguage) {
        preferences.defaultTargetLanguage = language
        persistPreferences()
    }

    func selectInterfaceLanguage(_ language: InterfaceLanguage) {
        preferences.interfaceLanguage = language
        persistPreferences()
    }

    func setStreamingEnabled(_ enabled: Bool) {
        preferences.preferStreaming = enabled
        persistPreferences()
    }

    func setQuickActionShortcut(_ preset: QuickActionShortcutPreset) {
        preferences.quickActionShortcut = preset
        persistPreferences()
    }

    func setPopulateClipboardOnQuickOpen(_ enabled: Bool) {
        preferences.populateClipboardOnQuickOpen = enabled
        persistPreferences()
    }

    func setAutoCopyTranslationResult(_ enabled: Bool) {
        preferences.autoCopyTranslationResult = enabled
        persistPreferences()
    }

    func setMenuBarExtraEnabled(_ enabled: Bool) {
        preferences.showMenuBarExtra = enabled
        persistPreferences()
    }

    func setExecutablePath(_ path: String, for engine: TranslationEngine) {
        preferences.setExecutablePath(path, for: engine)
        persistPreferences()
    }

    func resolvedExecutablePath(for engine: TranslationEngine) -> String {
        let custom = preferences.executablePath(for: engine)
        if !custom.isEmpty {
            return custom
        }
        return translator.findExecutable(for: engine) ?? ""
    }

    func translate() {
        Task {
            await runTranslation()
        }
    }

    func prepareQuickTranslatePresentation(prefillFromClipboard: Bool) {
        activeSection = .translate
        errorMessage = nil

        if prefillFromClipboard,
           let clipboardText = readClipboardText(),
           clipboardText != sourceText {
            importText(clipboardText, origin: .clipboard, clearTranslation: true)
        }

        quickTranslateActivationToken = UUID()
    }

    func translateClipboard() {
        guard let clipboardText = readClipboardText() else {
            activeSection = .translate
            errorMessage = t("error.empty_clipboard")
            quickTranslateActivationToken = UUID()
            return
        }

        importText(clipboardText, origin: .clipboard, clearTranslation: true)
        quickTranslateActivationToken = UUID()
        translate()
    }

    func clearHistory() {
        history.removeAll()
        selectedHistoryID = nil
        Task {
            await storage.saveHistory([])
        }
    }

    func exportHistory() {
        let csv = AppStorage.exportCSV(records: filteredHistory)
        guard !csv.isEmpty else {
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "langx-history.csv"

        if panel.runModal() == .OK, let url = panel.url {
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func browseExecutable(for engine: TranslationEngine) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            setExecutablePath(url.path, for: engine)
        }
    }

    func resetPreferences() {
        preferences = AppPreferences()
        persistPreferences()
    }

    func clearLogs() {
        logs.removeAll()
    }

    func copyLogs() {
        let content = logs
            .map(formattedLogLine)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !content.isEmpty else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }

    func copyTranslatedText() {
        guard !translatedText.isEmpty else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translatedText, forType: .string)
    }

    func copyLatestTranslation() {
        guard let record = history.first else {
            return
        }
        copyRecord(record)
    }

    func copyRecord(_ record: TranslationRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.translatedText, forType: .string)
    }

    func useRecord(_ record: TranslationRecord) {
        activeSection = .translate
        sourceText = record.sourceText
        translatedText = record.translatedText
        detectedSourceLanguage = record.sourceLanguage
        currentInputOrigin = record.inputOrigin

        if let target = TranslationLanguage.supportedTargets.first(where: { $0.code == record.targetLanguageCode }) {
            preferences.defaultTargetLanguage = target
        }

        persistPreferences()
    }

    func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: preferences.interfaceLanguage.localeIdentifier)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func formattedLogTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: preferences.interfaceLanguage.localeIdentifier)
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    func formattedLogLine(_ entry: AppLogEntry) -> String {
        "[\(formattedLogTimestamp(entry.timestamp))] [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)"
    }

    private func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return t("history.today")
        }
        if calendar.isDateInYesterday(date) {
            return t("history.yesterday")
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: preferences.interfaceLanguage.localeIdentifier)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func runTranslation() async {
        guard !isTranslating else {
            appendLog(level: .debug, category: "app", message: "Ignored translate request because another run is still active.")
            return
        }

        let input = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            errorMessage = t("error.empty_input")
            appendLog(level: .error, category: "app", message: "Translation aborted because the source text is empty.")
            return
        }

        errorMessage = nil
        isTranslating = true
        translatedText = ""
        let sourceLanguage = detector.detect(input)
        detectedSourceLanguage = sourceLanguage
        appendLog(
            level: .info,
            category: "app",
            message: "Starting translation with \(preferences.selectedEngine.displayName). source=\(sourceLanguage.code) target=\(preferences.defaultTargetLanguage.code) streaming=\(preferences.preferStreaming)"
        )

        do {
            let output = try await translator.translate(
                sourceText: sourceText,
                sourceLanguage: sourceLanguage,
                targetLanguage: preferences.defaultTargetLanguage,
                engine: preferences.selectedEngine,
                executablePath: preferences.executablePath(for: preferences.selectedEngine),
                preferStreaming: preferences.preferStreaming,
                onLog: { [weak self] level, category, message in
                    await MainActor.run {
                        self?.appendLog(level: level, category: category, message: message)
                    }
                }
            ) { [weak self] delta in
                await MainActor.run {
                    self?.translatedText += delta
                }
            }

            translatedText = output.finalText
            appendLog(
                level: .info,
                category: "app",
                message: "Translation completed successfully. streamed=\(output.usedStreaming) output=\(output.finalText.count) chars"
            )

            let record = TranslationRecord(
                sourceText: sourceText,
                translatedText: output.finalText,
                sourceLanguageCode: sourceLanguage.code,
                targetLanguageCode: preferences.defaultTargetLanguage.code,
                engine: preferences.selectedEngine,
                createdAt: Date(),
                wasStreamed: output.usedStreaming,
                inputOrigin: currentInputOrigin
            )

            history.insert(record, at: 0)
            selectedHistoryID = record.id
            await storage.saveHistory(history)

            if preferences.autoCopyTranslationResult {
                copyTranslatedText()
            }
        } catch let error as TranslationServiceError {
            errorMessage = error.localizedMessage(in: preferences.interfaceLanguage)
            appendLog(
                level: .error,
                category: "app",
                message: "Translation failed: \(error.localizedMessage(in: preferences.interfaceLanguage))"
            )
        } catch {
            errorMessage = error.localizedDescription
            appendLog(level: .error, category: "app", message: "Unexpected error: \(error.localizedDescription)")
        }

        isTranslating = false
    }

    private func appendLog(level: AppLogLevel, category: String, message: String) {
        let entry = AppLogEntry(level: level, category: category, message: message)
        logs.append(entry)

        if logs.count > Self.maxLogEntries {
            logs.removeFirst(logs.count - Self.maxLogEntries)
        }

        print("[langx][\(entry.level.rawValue)][\(entry.category)] \(entry.message)")
    }

    private func persistPreferences() {
        let snapshot = preferences
        Task {
            await storage.savePreferences(snapshot)
        }
    }

    private func importText(_ text: String, origin: TranslationInputOrigin, clearTranslation: Bool) {
        activeSection = .translate
        sourceText = text
        if clearTranslation {
            translatedText = ""
        }
        errorMessage = nil
        currentInputOrigin = origin
        scheduleDetection()
    }

    private func readClipboardText() -> String? {
        guard let value = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty else {
            return nil
        }
        return value
    }
}
