import HalfsiesCore

/// What Settings tells the user about why the menu bar does or does not show a keyboard.
public enum SetupStatus: Hashable, Sendable {
    case waitingForPermission
    case permissionDenied
    case bluetoothOff
    case bluetoothUnsupported
    /// Bluetooth works, but no keyboard that reports a battery is connected.
    case noKeyboard
    /// The keyboard picked in Settings is not connected.
    case notConnected(name: String)
    /// The keyboard reports one battery, usually because the firmware does not proxy the other half's.
    case singleBattery(name: String)
    case showing(name: String)

    /// - Parameters:
    ///   - selected: The keyboard shown in the menu bar, if any.
    ///   - preferred: The keyboard picked in Settings, if any.
    public init(
        bluetooth: BluetoothAvailability, keyboards: [Keyboard], selected: Keyboard?, preferred: KeyboardReference?
    ) {
        switch bluetooth {
        case .waitingForPermission: self = .waitingForPermission
        case .denied: self = .permissionDenied
        case .poweredOff: self = .bluetoothOff
        case .unsupported: self = .bluetoothUnsupported
        case .ready:
            if let selected {
                self = selected.isSplit ? .showing(name: selected.name) : .singleBattery(name: selected.name)
            } else if let preferred {
                self = .notConnected(name: preferred.name)
            } else if let single = keyboards.min(by: { $0.name < $1.name }) {
                // Automatic selection skips keyboards with one battery, so any connected keyboard has one.
                self = .singleBattery(name: single.name)
            } else {
                self = .noKeyboard
            }
        }
    }
}
