import AppKit
import Combine
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
                .onAppear {
                    appDelegate.configure(with: model)
                }
        }
        .defaultSize(width: 1280, height: 860)

        MenuBarExtra {
            MenuBarExtraContent(appDelegate: appDelegate)
                .environmentObject(model)
        } label: {
            Label("langx", systemImage: "character.bubble")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarExtraContent: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel

    let appDelegate: AppDelegate

    var body: some View {
        Button(model.t("menu.open_window")) {
            openMainWindow()
        }

        Button(model.t("menu.quick_translate")) {
            appDelegate.presentFloatingTranslationPanel()
        }

        Button(model.t("menu.open_settings")) {
            model.activeSection = .settings
            openMainWindow()
        }

        Divider()

        Button(model.t("menu.quit")) {
            NSApp.terminate(nil)
        }
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: AppSceneID.mainWindow)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    private var preferencesCancellable: AnyCancellable?
    private var hotKeyEventCancellable: AnyCancellable?
    private let hotKeyManager = GlobalHotKeyManager()
    private var floatingPanelController: FloatingTranslationPanelController?

    func configure(with model: AppModel) {
        guard self.model !== model else {
            return
        }

        self.model = model
        floatingPanelController = FloatingTranslationPanelController(model: model)
        preferencesCancellable = model.$preferences
            .map(\.globalShortcutPreset)
            .removeDuplicates()
            .sink { [weak self] preset in
                self?.hotKeyManager.updateRegistration(for: preset)
            }
        hotKeyEventCancellable = NotificationCenter.default.publisher(for: .langxGlobalHotKeyPressed)
            .sink { [weak self] _ in
                self?.presentFloatingTranslationPanel()
            }
    }

    func presentFloatingTranslationPanel() {
        floatingPanelController?.present()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = AppIconRenderer.makeApplicationIcon()

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            guard let window = NSApp.windows.first else {
                return
            }

            window.makeKeyAndOrderFront(nil)
            window.makeMain()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
