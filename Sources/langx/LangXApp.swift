import AppKit
import Combine
import Darwin
import SwiftUI

@main
struct LangXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("langx", id: AppSceneID.mainWindow) {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1180, minHeight: 760)
                .background(WindowActionRegistrar(appDelegate: appDelegate).environmentObject(model))
                .onAppear {
                    appDelegate.configure(with: model)
                }
        }
        .defaultSize(width: 1280, height: 860)
    }
}

private struct WindowActionRegistrar: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel

    let appDelegate: AppDelegate

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .onAppear {
                appDelegate.registerWindowActions(
                    openMainWindow: {
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: AppSceneID.mainWindow)
                    },
                    openSettings: {
                        model.activeSection = .settings
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: AppSceneID.mainWindow)
                    }
                )
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    private var preferencesCancellable: AnyCancellable?
    private var hotKeyEventCancellable: AnyCancellable?
    private var statusItemMenuCancellable: AnyCancellable?
    private let hotKeyManager = GlobalHotKeyManager()
    private let selectedTextCaptureService = SelectedTextCaptureService()
    private var floatingPanelController: FloatingTranslationPanelController?
    private var statusItem: NSStatusItem?
    private var statusItemMenu = NSMenu()
    private var openMainWindowAction: (() -> Void)?
    private var openSettingsAction: (() -> Void)?

    func configure(with model: AppModel) {
        guard self.model !== model else {
            return
        }

        self.model = model
        floatingPanelController = FloatingTranslationPanelController(model: model)
        preferencesCancellable = model.$preferences
            .map {
                HotKeyConfiguration(
                    openFloatingPanel: $0.globalShortcutPreset,
                    translateSelection: $0.selectionTranslationShortcutPreset
                )
            }
            .removeDuplicates()
            .sink { [weak self] configuration in
                self?.hotKeyManager.updateRegistration(for: .openFloatingPanel, preset: configuration.openFloatingPanel)
                self?.hotKeyManager.updateRegistration(for: .translateSelection, preset: configuration.translateSelection)
            }
        hotKeyEventCancellable = NotificationCenter.default.publisher(for: .langxGlobalHotKeyPressed)
            .compactMap { $0.object as? GlobalHotKeyAction }
            .sink { [weak self] action in
                switch action {
                case .openFloatingPanel:
                    self?.presentFloatingTranslationPanel()
                case .translateSelection:
                    self?.translateSelection()
                }
            }
        statusItemMenuCancellable = model.$preferences
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshStatusItemMenu()
            }
        refreshStatusItemMenu()
    }

    func registerWindowActions(
        openMainWindow: (() -> Void)?,
        openSettings: (() -> Void)?
    ) {
        openMainWindowAction = openMainWindow
        openSettingsAction = openSettings
    }

    func refreshStatusItemMenu() {
        guard let model else {
            return
        }

        let menu = NSMenu()
        menu.addItem(
            withTitle: model.t("menu.open_window"),
            action: #selector(openMainWindowFromStatusItem),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: model.t("menu.quick_translate"),
            action: #selector(openQuickTranslateFromStatusItem),
            keyEquivalent: ""
        )
        menu.addItem(
            withTitle: model.t("menu.open_settings"),
            action: #selector(openSettingsFromStatusItem),
            keyEquivalent: ""
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: model.t("menu.quit"),
            action: #selector(quitFromStatusItem),
            keyEquivalent: ""
        )
        menu.items.forEach { $0.target = self }

        statusItemMenu = menu
        statusItem?.button?.toolTip = model.t("menu.open_window")
        statusItem?.button?.setAccessibilityTitle(model.t("menu.open_window"))
    }

    func presentFloatingTranslationPanel() {
        floatingPanelController?.present()
    }

    private func translateSelection() {
        guard let model else {
            return
        }

        let captureService = selectedTextCaptureService
        Task {
            do {
                let selectedText = try await captureService.captureSelectedText()
                await MainActor.run {
                    self.presentFloatingTranslationPanel()
                    model.prepareTranslation(sourceText: selectedText, autoTranslate: true)
                }
            } catch let error as SelectedTextCaptureError {
                await MainActor.run {
                    self.presentFloatingTranslationPanel()
                    model.presentSelectionCaptureError(error)
                }
            } catch {
                await MainActor.run {
                    self.presentFloatingTranslationPanel()
                    model.presentSelectionCaptureError(.unexpected(error.localizedDescription))
                }
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Child CLI processes may close stdin immediately; ignore SIGPIPE so writes fail with EPIPE instead of killing the app.
        signal(SIGPIPE, SIG_IGN)

        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = AppIconRenderer.makeApplicationIcon()
        configureStatusItem()

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            guard let window = NSApp.windows.first(where: { !($0 is NSPanel) }) else {
                return
            }

            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func configureStatusItem() {
        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.isVisible = true
        if let button = item.button {
            let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            let image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "langx")
            image?.isTemplate = true
            button.image = image?.withSymbolConfiguration(configuration)
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        statusItem = item
    }

    private func openMainWindow() {
        if let openMainWindowAction {
            openMainWindowAction()
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows
            .first(where: { !($0 is NSPanel) })?
            .makeKeyAndOrderFront(nil)
    }

    private func openSettings() {
        model?.activeSection = .settings

        if let openSettingsAction {
            openSettingsAction()
            return
        }

        openMainWindow()
    }

    private func showStatusItemMenu() {
        guard let statusItem else {
            return
        }

        statusItem.menu = statusItemMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc
    private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            openMainWindow()
            return
        }

        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showStatusItemMenu()
            return
        }

        openMainWindow()
    }

    @objc
    private func openMainWindowFromStatusItem() {
        openMainWindow()
    }

    @objc
    private func openQuickTranslateFromStatusItem() {
        presentFloatingTranslationPanel()
    }

    @objc
    private func openSettingsFromStatusItem() {
        openSettings()
    }

    @objc
    private func quitFromStatusItem() {
        NSApp.terminate(nil)
    }
}

private struct HotKeyConfiguration: Equatable {
    let openFloatingPanel: GlobalShortcutPreset
    let translateSelection: GlobalShortcutPreset
}
