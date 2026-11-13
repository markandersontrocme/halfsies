import HalfsiesBattery
import SwiftUI

/// Links the app opens. The README sections are the user-facing guide.
enum HelpLinks {
    static let firmwareSetting = URL(string: "https://github.com/markandersontrocme/halfsies#firmware-setting")!
    static let troubleshooting = URL(string: "https://github.com/markandersontrocme/halfsies#troubleshooting")!
    /// System Settings > Privacy & Security > Bluetooth, where the user allows apps to use Bluetooth.
    static let bluetoothPrivacy = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!
}

/// One line at the top of Settings that says why the menu bar does or does not show a keyboard,
/// with the action that fixes it where there is one.
struct SetupStatusRow: View {
    let status: SetupStatus
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
            }
            .font(.headline)

            detail
        }
        .padding(.vertical, 2)
    }

    private var title: String {
        switch status {
        case .waitingForPermission: "Waiting for Bluetooth permission"
        case .permissionDenied: "Halfsies is not allowed to use Bluetooth"
        case .bluetoothOff: "Bluetooth is off"
        case .bluetoothUnsupported: "This Mac does not support Bluetooth Low Energy"
        case .noKeyboard: "No keyboard connected"
        case .notConnected(let name): "\(name) is not connected"
        case .singleBattery(let name): "\(name) reports only one battery"
        case .showing(let name): "Showing \(name)"
        }
    }

    private var symbol: String {
        switch status {
        case .showing: "checkmark.circle.fill"
        case .waitingForPermission: "hourglass"
        case .noKeyboard, .notConnected: "keyboard"
        case .permissionDenied, .bluetoothOff, .bluetoothUnsupported, .singleBattery: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .showing: .green
        case .waitingForPermission, .noKeyboard, .notConnected: .secondary
        case .permissionDenied, .bluetoothOff, .bluetoothUnsupported, .singleBattery: .orange
        }
    }

    @ViewBuilder private var detail: some View {
        switch status {
        case .waitingForPermission:
            note("Allow Halfsies when macOS asks, so it can read your keyboard's battery.")
        case .permissionDenied:
            note("Turn on Halfsies in Privacy & Security > Bluetooth.")
            Button("Open Bluetooth Settings") { openURL(HelpLinks.bluetoothPrivacy) }
        case .bluetoothOff:
            note("Turn on Bluetooth to see your keyboard's battery.")
        case .bluetoothUnsupported, .showing:
            EmptyView()
        case .noKeyboard:
            note("Connect your keyboard in System Settings > Bluetooth.")
        case .notConnected:
            note("Turn it on, or set Keyboard to Automatic below.")
        case .singleBattery:
            note("If it is a ZMK split, add these lines to the central half's firmware and flash it:")
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Self.firmwareSettings, id: \.self) { line in
                    Text(line)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .font(.caption.monospaced())
            .textSelection(.enabled)
            note("If the second half still does not show up, remove the keyboard in System Settings > Bluetooth and pair it again.")
            Link("Firmware setup in the README", destination: HelpLinks.firmwareSetting)
                .font(.caption)
        }
    }

    /// The ZMK settings that make the central half report the other half's battery, as in the README.
    static let firmwareSettings = [
        "CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING=y",
        "CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY=y",
    ]

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
