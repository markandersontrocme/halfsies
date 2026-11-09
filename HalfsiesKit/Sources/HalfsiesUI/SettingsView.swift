import HalfsiesBattery
import HalfsiesCore
import SwiftUI

/// The Settings window content.
public struct SettingsView: View {
    @Bindable var monitor: BatteryMonitor
    @Binding var launchAtLogin: Bool
    /// Shown under the launch-at-login toggle, for example when macOS needs the user's approval.
    let launchAtLoginNote: String?

    public init(monitor: BatteryMonitor, launchAtLogin: Binding<Bool>, launchAtLoginNote: String?) {
        self.monitor = monitor
        _launchAtLogin = launchAtLogin
        self.launchAtLoginNote = launchAtLoginNote
    }

    public var body: some View {
        @Bindable var settings = monitor.settings
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                if let launchAtLoginNote {
                    Text(launchAtLoginNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Keyboard", selection: $settings.preferredKeyboard) {
                    Text("Automatic").tag(KeyboardReference?.none)
                    ForEach(monitor.choices) { choice in
                        Text(choice.isConnected ? choice.reference.name : "\(choice.reference.name) (not connected)")
                            .tag(Optional(choice.reference))
                    }
                }
                Toggle("Swap left and right", isOn: $settings.swapSides)
            } footer: {
                Text("Halfsies shows the half your Mac connects to on the left. Swap if yours is on the right.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}
