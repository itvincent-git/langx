import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class FloatingTranslationPanelController {
    private weak var model: AppModel?
    private var panel: NSPanel?

    init(model: AppModel) {
        self.model = model
    }

    func present() {
        guard let model else {
            return
        }

        let panel = makePanelIfNeeded(with: model)
        panel.title = model.t("floating.title")

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        model.requestFloatingPanelFocus()
    }

    private func makePanelIfNeeded(with model: AppModel) -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentViewController = NSHostingController(
            rootView: FloatingTranslateView().environmentObject(model)
        )
        panel.center()

        self.panel = panel
        return panel
    }
}

final class GlobalHotKeyManager {
    private static let signature = OSType(0x4C4E4758) // LNGX
    private static let eventHandler: EventHandlerUPP = { _, event, userData in
        guard let userData else {
            return OSStatus(eventNotHandledErr)
        }

        let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
        return manager.handleHotKeyEvent(event)
    }

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init() {
        installEventHandler()
    }

    deinit {
        unregister()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func updateRegistration(for preset: GlobalShortcutPreset) {
        unregister()
        guard let registration = HotKeyRegistration(preset: preset) else {
            return
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            registration.keyCode,
            registration.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            NSLog("langx failed to register global hotkey, status=%d", status)
            hotKeyRef = nil
        }
    }

    private func installEventHandler() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        if status != noErr {
            NSLog("langx failed to install global hotkey handler, status=%d", status)
        }
    }

    private func handleHotKeyEvent(_ event: EventRef?) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr, hotKeyID.signature == Self.signature else {
            return OSStatus(eventNotHandledErr)
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .langxGlobalHotKeyPressed, object: nil)
        }
        return noErr
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
}

extension Notification.Name {
    static let langxGlobalHotKeyPressed = Notification.Name("langx.globalHotKeyPressed")
}

private struct HotKeyRegistration {
    let keyCode: UInt32
    let modifiers: UInt32

    init?(preset: GlobalShortcutPreset) {
        switch preset {
        case .off:
            return nil
        case .optionSpace:
            keyCode = UInt32(kVK_Space)
            modifiers = UInt32(optionKey)
        case .commandShiftSpace:
            keyCode = UInt32(kVK_Space)
            modifiers = UInt32(cmdKey | shiftKey)
        case .controlOptionSpace:
            keyCode = UInt32(kVK_Space)
            modifiers = UInt32(controlKey | optionKey)
        }
    }
}

struct FloatingTranslateView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var isSourceFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.t("floating.title"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.langxText)
                Text(model.t("floating.subtitle"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.langxSubtext)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(model.t("translate.source"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.langxSubtext)
                    Spacer()
                    Text("\(model.sourceText.count) / 5000")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.langxSubtext.opacity(0.75))
                }

                TextEditor(
                    text: Binding(
                        get: { model.sourceText },
                        set: { model.updateSourceText($0) }
                    )
                )
                .focused($isSourceFocused)
                .font(.system(size: 16))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 150)
                .padding(6)
                .background(Color.clear)
            }
            .langxCardStyle()

            VStack(alignment: .leading, spacing: 12) {
                Text(model.t("translate.target"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.langxSubtext)

                HStack(spacing: 10) {
                    ForEach(TranslationLanguage.supportedTargets) { language in
                        FloatingSelectionChip(
                            title: language.localizedName(in: model.preferences.interfaceLanguage),
                            isSelected: model.preferences.defaultTargetLanguage.code == language.code
                        ) {
                            model.selectTargetLanguage(language)
                        }
                    }

                    Spacer()

                    Button {
                        model.translate()
                    } label: {
                        HStack(spacing: 8) {
                            if model.isTranslating {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            }
                            Text(model.isTranslating ? model.t("translate.translating") : model.t("translate.cta"))
                                .font(.system(size: 14, weight: .bold))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .foregroundStyle(.white)
                        .background(LinearGradient.langxPrimary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isTranslating)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(model.t("translate.target"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.langxSubtext)
                    Spacer()
                    Button(model.t("translate.copy")) {
                        model.copyTranslatedText()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.langxPrimary)
                }

                ScrollView {
                    Text(model.translatedText.isEmpty ? model.t("translate.placeholder") : model.translatedText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.system(size: 16))
                        .foregroundStyle(model.translatedText.isEmpty ? Color.langxSubtext.opacity(0.6) : Color.langxText)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 160)

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                }
            }
            .langxCardStyle()
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 520, alignment: .topLeading)
        .background(Color.langxBackground)
        .onAppear {
            focusSourceEditor()
        }
        .onChange(of: model.floatingPanelFocusToken) { _, _ in
            focusSourceEditor()
        }
    }

    private func focusSourceEditor() {
        DispatchQueue.main.async {
            isSourceFocused = true
        }
    }
}

private struct FloatingSelectionChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.langxPrimary.opacity(0.12) : Color.langxSurfaceHigh.opacity(0.6))
                )
                .foregroundStyle(isSelected ? Color.langxPrimary : Color.langxSubtext)
        }
        .buttonStyle(.plain)
    }
}
