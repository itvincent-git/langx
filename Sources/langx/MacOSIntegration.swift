import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class AppController: ObservableObject {
    private let hotKeyMonitor = GlobalHotKeyMonitor()
    private let quickTranslatePanelController = QuickTranslatePanelController()
    private var preferencesObserver: AnyCancellable?
    private weak var mainWindow: NSWindow?
    private weak var model: AppModel?

    init() {
        hotKeyMonitor.onActivate = { [weak self] in
            self?.handleQuickActionHotKey()
        }
    }

    func install(model: AppModel) {
        guard self.model !== model else {
            return
        }

        self.model = model
        quickTranslatePanelController.configure(model: model, controller: self)

        preferencesObserver = model.$preferences.sink { [weak self] preferences in
            self?.hotKeyMonitor.updateRegistration(for: preferences.quickActionShortcut)
        }

        hotKeyMonitor.updateRegistration(for: model.preferences.quickActionShortcut)
    }

    func showQuickTranslatePanel(prefillFromClipboard: Bool) {
        guard let model else {
            return
        }

        activateApp()
        quickTranslatePanelController.show()
        model.prepareQuickTranslatePresentation(prefillFromClipboard: prefillFromClipboard)
    }

    func translateClipboard() {
        guard let model else {
            return
        }

        activateApp()
        quickTranslatePanelController.show()
        model.translateClipboard()
    }

    func openMainWindow() {
        activateApp()

        guard let window = mainWindow ?? NSApp.windows.first(where: { !($0 is NSPanel) }) else {
            return
        }

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func closeQuickTranslatePanel() {
        quickTranslatePanelController.close()
    }

    func loadRecordInQuickTranslate(_ record: TranslationRecord) {
        guard let model else {
            return
        }

        model.useRecord(record)
        showQuickTranslatePanel(prefillFromClipboard: false)
    }

    private func handleQuickActionHotKey() {
        guard let model else {
            return
        }

        showQuickTranslatePanel(prefillFromClipboard: model.preferences.populateClipboardOnQuickOpen)
    }

    private func activateApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func registerMainWindow(_ window: NSWindow?) {
        guard let window else {
            return
        }
        mainWindow = window
    }
}

@MainActor
private final class QuickTranslatePanelController {
    private weak var model: AppModel?
    private weak var controller: AppController?
    private var panel: QuickTranslatePanel?

    func configure(model: AppModel, controller: AppController) {
        self.model = model
        self.controller = controller

        if let panel {
            attachRootView(to: panel)
        }
    }

    func show() {
        let panel = panel ?? makePanel()
        attachRootView(to: panel)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> QuickTranslatePanel {
        let panel = QuickTranslatePanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.setFrameAutosaveName("langx.quickTranslatePanel")
        self.panel = panel
        return panel
    }

    private func attachRootView(to panel: QuickTranslatePanel) {
        guard let model, let controller else {
            return
        }

        let rootView = AnyView(
            QuickTranslatePanelRootView()
                .environmentObject(model)
                .environmentObject(controller)
        )

        if let hostingController = panel.contentViewController as? NSHostingController<AnyView> {
            hostingController.rootView = rootView
        } else {
            panel.contentViewController = NSHostingController(rootView: rootView)
        }
    }
}

private final class QuickTranslatePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private final class GlobalHotKeyMonitor {
    var onActivate: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private let monitorID: UInt32

    private static let signature: OSType = 0x6C675858
    private nonisolated(unsafe) static var nextMonitorID: UInt32 = 1
    private nonisolated(unsafe) static var eventHandlerRef: EventHandlerRef?
    private nonisolated(unsafe) static var monitors: [UInt32: GlobalHotKeyMonitor] = [:]
    private static let eventHandler: EventHandlerUPP = { _, event, _ in
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

        guard status == noErr,
              hotKeyID.signature == GlobalHotKeyMonitor.signature,
              let monitor = GlobalHotKeyMonitor.monitors[hotKeyID.id] else {
            return noErr
        }

        Task { @MainActor in
            monitor.onActivate?()
        }

        return noErr
    }

    init() {
        monitorID = Self.nextMonitorID
        Self.nextMonitorID += 1
        Self.monitors[monitorID] = self
        Self.installEventHandlerIfNeeded()
    }

    deinit {
        unregister()
        Self.monitors.removeValue(forKey: monitorID)
    }

    func updateRegistration(for preset: QuickActionShortcutPreset) {
        unregister()

        guard let keyCode = preset.carbonKeyCode else {
            return
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: monitorID)
        RegisterEventHotKey(
            keyCode,
            preset.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
    }

    private func unregister() {
        guard let hotKeyRef else {
            return
        }

        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    private static func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetEventDispatcherTarget(),
            eventHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }
}

struct MainWindowObserver: NSViewRepresentable {
    let controller: AppController

    func makeNSView(context: Context) -> MainWindowTrackingView {
        let view = MainWindowTrackingView()
        view.onWindowChange = { window in
            controller.registerMainWindow(window)
        }
        return view
    }

    func updateNSView(_ nsView: MainWindowTrackingView, context: Context) {
        nsView.onWindowChange = { window in
            controller.registerMainWindow(window)
        }

        DispatchQueue.main.async {
            controller.registerMainWindow(nsView.window)
        }
    }
}

final class MainWindowTrackingView: NSView {
    var onWindowChange: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowChange?(window)
    }
}
