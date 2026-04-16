import AppKit
import SwiftUI

@main
struct LangXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var controller = AppController()

    var body: some Scene {
        WindowGroup("langx") {
            RootView()
                .environmentObject(model)
                .environmentObject(controller)
                .background(MainWindowObserver(controller: controller))
                .frame(minWidth: 1180, minHeight: 760)
                .task {
                    controller.install(model: model)
                }
        }
        .defaultSize(width: 1280, height: 860)

        MenuBarExtra(
            "langx",
            systemImage: "translate",
            isInserted: Binding(
                get: { model.preferences.showMenuBarExtra },
                set: { model.setMenuBarExtraEnabled($0) }
            )
        ) {
            MenuBarExtraContent()
                .environmentObject(model)
                .environmentObject(controller)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
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
