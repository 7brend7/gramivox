import SwiftUI

@main
struct GramiVoxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppCoordinator.shared.start()
        statusBarController = StatusBarController(coordinator: AppCoordinator.shared, settings: AppSettings.shared)
        statusBarController?.install()
        showSettingsOnFirstLaunchIfNeeded()
    }

    private func showSettingsOnFirstLaunchIfNeeded() {
        let key = "hasShownSettingsWindowOnce"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        UserDefaults.standard.set(true, forKey: key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            AppCoordinator.shared.openSettings()
        }
    }
}
