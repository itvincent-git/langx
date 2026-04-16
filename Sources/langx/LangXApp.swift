import AppKit
import Combine
import SwiftUI

@main
struct LangXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("langx") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1180, minHeight: 760)
                .onAppear {
                    appDelegate.configure(with: model)
                }
        }
        .defaultSize(width: 1280, height: 860)
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
                self?.floatingPanelController?.present()
            }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            guard let window = NSApp.windows.first else {
                return
            }

            window.makeKeyAndOrderFront(nil)
            window.makeMain()
        }
    }
}
