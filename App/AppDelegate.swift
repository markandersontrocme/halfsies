import AppKit
import HalfsiesBLE
import HalfsiesBattery
import HalfsiesUI
import SwiftUI

/// Composition root: builds the feature objects and owns app-level windows.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = BatteryMonitor(transport: BLEKeyboardTransport(), settings: BatterySettings())
    private let loginItem = LoginItem()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await monitor.run() }
    }

    /// The menu bar item is hidden while no keyboard is connected, so opening the app again shows Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func showSettings() {
        loginItem.refresh()
        if settingsWindow == nil {
            let view = SettingsHost(monitor: monitor, loginItem: loginItem)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Halfsies Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

/// Connects the settings view to the app-level login item.
private struct SettingsHost: View {
    let monitor: BatteryMonitor
    let loginItem: LoginItem

    var body: some View {
        SettingsView(
            monitor: monitor,
            launchAtLogin: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }),
            launchAtLoginNote: loginItem.note)
    }
}
