import AppKit
@preconcurrency import ApplicationServices
import Carbon
import Foundation

enum SelectedTextCaptureError: LocalizedError, Equatable, Sendable {
    case permissionDenied
    case emptySelection
    case unsupportedSelection
    case noFrontmostApplication
    case clipboardCopyFailed
    case clipboardReadFailed
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Accessibility permission is required to read selected text. If it is already granted, remove and re-add /Applications/langx.app in System Settings, then relaunch the app."
        case .emptySelection:
            "No selected text was detected."
        case .unsupportedSelection:
            "The current app does not expose selected text."
        case .noFrontmostApplication:
            "Unable to determine the active application."
        case .clipboardCopyFailed:
            "Unable to trigger copy in the active application."
        case .clipboardReadFailed:
            "Unable to read copied text from the clipboard."
        case .unexpected(let message):
            message
        }
    }

    func localizedMessage(in language: InterfaceLanguage) -> String {
        switch (self, language) {
        case (.permissionDenied, .simplifiedChinese):
            "需要先在系统设置的“隐私与安全性 > 辅助功能”中允许 /Applications/langx.app，才能直接读取划词内容。若你已经授权，请删除旧的 langx 条目后重新添加，并重启 app。"
        case (.emptySelection, .simplifiedChinese):
            "没有检测到当前选中的文本。"
        case (.unsupportedSelection, .simplifiedChinese):
            "当前应用没有向 macOS 暴露可读取的选中文本。"
        case (.noFrontmostApplication, .simplifiedChinese):
            "无法确定当前前台应用。"
        case (.clipboardCopyFailed, .simplifiedChinese):
            "无法自动执行复制，请重新选中文本后再试。"
        case (.clipboardReadFailed, .simplifiedChinese):
            "复制成功后未能从剪贴板读取文本。"
        case (.unexpected(let message), .simplifiedChinese):
            "划词翻译失败：\(message)"
        default:
            errorDescription ?? "Unable to capture selected text."
        }
    }
}

protocol SelectedTextProvider: Sendable {
    func captureSelectedText() async throws -> String
}

struct SelectedTextCaptureService: Sendable {
    private let providers: [any SelectedTextProvider]

    init(providers: [any SelectedTextProvider] = [
        AccessibilitySelectedTextProvider(),
        ClipboardFallbackSelectedTextProvider(),
    ]) {
        self.providers = providers
    }

    func captureSelectedText() async throws -> String {
        var failures: [SelectedTextCaptureError] = []

        for provider in providers {
            do {
                let text = try await provider.captureSelectedText()
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    throw SelectedTextCaptureError.emptySelection
                }
                return text
            } catch let error as SelectedTextCaptureError {
                failures.append(error)
            } catch {
                failures.append(.unexpected(error.localizedDescription))
            }
        }

        throw prioritizedError(from: failures)
    }

    private func prioritizedError(from failures: [SelectedTextCaptureError]) -> SelectedTextCaptureError {
        if failures.contains(where: { if case .emptySelection = $0 { true } else { false } }) {
            return .emptySelection
        }
        if failures.contains(where: { if case .permissionDenied = $0 { true } else { false } }) {
            return .permissionDenied
        }
        if failures.contains(where: { if case .unsupportedSelection = $0 { true } else { false } }) {
            return .unsupportedSelection
        }
        if failures.contains(where: { if case .clipboardReadFailed = $0 { true } else { false } }) {
            return .clipboardReadFailed
        }
        if failures.contains(where: { if case .clipboardCopyFailed = $0 { true } else { false } }) {
            return .clipboardCopyFailed
        }
        if failures.contains(where: { if case .noFrontmostApplication = $0 { true } else { false } }) {
            return .noFrontmostApplication
        }
        return failures.first ?? .unexpected("Selected text capture failed.")
    }
}

struct AccessibilitySelectedTextProvider: SelectedTextProvider {
    func captureSelectedText() async throws -> String {
        guard isTrusted(promptIfNeeded: false) else {
            throw SelectedTextCaptureError.permissionDenied
        }

        guard let application = NSWorkspace.shared.frontmostApplication else {
            throw SelectedTextCaptureError.noFrontmostApplication
        }

        let element = AXUIElementCreateApplication(application.processIdentifier)

        guard let focusedElement = try copyElementAttribute(
            named: kAXFocusedUIElementAttribute as CFString,
            from: element
        ) else {
            throw SelectedTextCaptureError.unsupportedSelection
        }

        if let selectedText = try copyStringAttribute(
            named: kAXSelectedTextAttribute as CFString,
            from: focusedElement
        ) {
            let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                throw SelectedTextCaptureError.emptySelection
            }
            return selectedText
        }

        guard let selectedRange = try copyRangeAttribute(
            named: kAXSelectedTextRangeAttribute as CFString,
            from: focusedElement
        ) else {
            throw SelectedTextCaptureError.unsupportedSelection
        }

        guard selectedRange.length > 0 else {
            throw SelectedTextCaptureError.emptySelection
        }

        if let selectedText = try copyStringForRange(selectedRange, from: focusedElement) {
            let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                throw SelectedTextCaptureError.emptySelection
            }
            return selectedText
        }

        throw SelectedTextCaptureError.unsupportedSelection
    }

    private func isTrusted(promptIfNeeded: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func copyElementAttribute(named name: CFString, from element: AXUIElement) throws -> AXUIElement? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name, &value)
        switch error {
        case .success:
            guard let value else {
                return nil
            }
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
                throw SelectedTextCaptureError.unexpected("Accessibility returned an unexpected focused element type.")
            }
            return (value as! AXUIElement)
        case .noValue, .attributeUnsupported:
            return nil
        case .apiDisabled:
            throw SelectedTextCaptureError.permissionDenied
        default:
            throw SelectedTextCaptureError.unexpected("Accessibility lookup failed with AXError \(error.rawValue).")
        }
    }

    private func copyStringAttribute(named name: CFString, from element: AXUIElement) throws -> String? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name, &value)
        switch error {
        case .success:
            return value as? String
        case .noValue, .attributeUnsupported:
            return nil
        case .apiDisabled:
            throw SelectedTextCaptureError.permissionDenied
        default:
            throw SelectedTextCaptureError.unexpected("Accessibility string lookup failed with AXError \(error.rawValue).")
        }
    }

    private func copyRangeAttribute(named name: CFString, from element: AXUIElement) throws -> CFRange? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name, &value)
        switch error {
        case .success:
            guard let value else {
                return nil
            }
            guard CFGetTypeID(value) == AXValueGetTypeID() else {
                throw SelectedTextCaptureError.unexpected("Accessibility returned an unexpected range value type.")
            }
            let axValue = value as! AXValue
            guard AXValueGetType(axValue) == .cfRange else {
                return nil
            }
            var range = CFRange()
            guard AXValueGetValue(axValue, .cfRange, &range) else {
                return nil
            }
            return range
        case .noValue, .attributeUnsupported:
            return nil
        case .apiDisabled:
            throw SelectedTextCaptureError.permissionDenied
        default:
            throw SelectedTextCaptureError.unexpected("Accessibility range lookup failed with AXError \(error.rawValue).")
        }
    }

    private func copyStringForRange(_ range: CFRange, from element: AXUIElement) throws -> String? {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else {
            throw SelectedTextCaptureError.unsupportedSelection
        }

        var value: CFTypeRef?
        let error = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        )

        switch error {
        case .success:
            return value as? String
        case .noValue, .attributeUnsupported, .parameterizedAttributeUnsupported:
            return nil
        case .apiDisabled:
            throw SelectedTextCaptureError.permissionDenied
        default:
            throw SelectedTextCaptureError.unexpected("Accessibility range extraction failed with AXError \(error.rawValue).")
        }
    }
}

struct ClipboardFallbackSelectedTextProvider: SelectedTextProvider {
    func captureSelectedText() async throws -> String {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            throw SelectedTextCaptureError.noFrontmostApplication
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        let initialChangeCount = pasteboard.changeCount
        defer {
            snapshot.restore(to: pasteboard)
        }

        try postCopyShortcut(to: application.processIdentifier)

        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(50))

            guard pasteboard.changeCount != initialChangeCount else {
                continue
            }

            guard let copiedText = pasteboard.string(forType: .string) else {
                throw SelectedTextCaptureError.clipboardReadFailed
            }

            let trimmed = copiedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw SelectedTextCaptureError.emptySelection
            }

            return copiedText
        }

        throw SelectedTextCaptureError.clipboardCopyFailed
    }

    private func postCopyShortcut(to processIdentifier: pid_t) throws {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false) else {
            throw SelectedTextCaptureError.clipboardCopyFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(processIdentifier)
        keyUp.postToPid(processIdentifier)
    }
}

private struct PasteboardSnapshot {
    private let items: [PasteboardItemSnapshot]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map(PasteboardItemSnapshot.init)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else {
            return
        }

        let restoredItems = items.map(\.item)
        pasteboard.writeObjects(restoredItems)
    }
}

private struct PasteboardItemSnapshot {
    let dataByType: [NSPasteboard.PasteboardType: Data]

    init(item: NSPasteboardItem) {
        var snapshot: [NSPasteboard.PasteboardType: Data] = [:]
        for type in item.types {
            if let data = item.data(forType: type) {
                snapshot[type] = data
            }
        }
        dataByType = snapshot
    }

    var item: NSPasteboardItem {
        let item = NSPasteboardItem()
        for (type, data) in dataByType {
            item.setData(data, forType: type)
        }
        return item
    }
}
