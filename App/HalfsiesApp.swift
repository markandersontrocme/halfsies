import HalfsiesUI
import SwiftUI

@main
struct HalfsiesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Reading menuBarText here makes SwiftUI re-evaluate the scene when a keyboard comes or goes.
        let hasKeyboard = appDelegate.monitor.menuBarText != nil

        MenuBarExtra(isInserted: .constant(hasKeyboard)) {
            BatteryPanel(
                monitor: appDelegate.monitor,
                openSettings: appDelegate.showSettings,
                quit: { NSApp.terminate(nil) })
        } label: {
            MenuBarLabel(monitor: appDelegate.monitor)
        }
        .menuBarExtraStyle(.window)
    }
}
