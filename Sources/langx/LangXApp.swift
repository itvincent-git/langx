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
    private let selectedTextCaptureService = SelectedTextCaptureService()
    private var floatingPanelController: FloatingTranslationPanelController?

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
}

private struct HotKeyConfiguration: Equatable {
    let openFloatingPanel: GlobalShortcutPreset
    let translateSelection: GlobalShortcutPreset
}
