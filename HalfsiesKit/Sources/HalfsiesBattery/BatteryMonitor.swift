import HalfsiesCore
import Observation

/// An entry in the keyboard picker.
public struct KeyboardChoice: Hashable, Sendable, Identifiable {
    public var reference: KeyboardReference
    public var isConnected: Bool

    public var id: KeyboardID { reference.id }

    public init(reference: KeyboardReference, isConnected: Bool) {
        self.reference = reference
        self.isConnected = isConnected
    }
}

/// Observable battery state for the UI, fed by a keyboard transport.
@MainActor
@Observable
public final class BatteryMonitor {
    public let settings: BatterySettings
    /// Every connected keyboard that reports a battery.
    public private(set) var keyboards: [Keyboard] = []
    /// Whether the transport can reach keyboards. Until it says otherwise, the app waits for permission.
    public private(set) var bluetooth: BluetoothAvailability = .waitingForPermission

    @ObservationIgnored private let transport: any KeyboardTransport

    public init(transport: any KeyboardTransport, settings: BatterySettings) {
        self.transport = transport
        self.settings = settings
    }

    /// Consumes transport updates until the stream ends. Call once.
    public func run() async {
        for await snapshot in transport.snapshots() {
            bluetooth = snapshot.bluetooth
            keyboards = snapshot.keyboards
        }
    }

    /// The keyboard shown in the menu bar, or nil when there is nothing to show.
    public var selectedKeyboard: Keyboard? {
        Keyboard.select(from: keyboards, preferred: settings.preferredKeyboard?.id)
    }

    /// Battery levels of the selected keyboard by physical side.
    public var split: SplitBattery? {
        selectedKeyboard?.sides(swapped: settings.swapSides)
    }

    /// Menu bar text such as "86% 39%", or nil when the menu bar item should be hidden.
    public var menuBarText: String? {
        split?.menuBarText
    }

    /// Why the menu bar does or does not show a keyboard, for Settings.
    public var status: SetupStatus {
        SetupStatus(
            bluetooth: bluetooth, keyboards: keyboards, selected: selectedKeyboard,
            preferred: settings.preferredKeyboard)
    }

    /// Keyboards for the picker: connected ones by name, plus the preferred one if it is disconnected.
    public var choices: [KeyboardChoice] {
        var choices = keyboards
            .sorted { $0.name < $1.name }
            .map { KeyboardChoice(reference: KeyboardReference(id: $0.id, name: $0.name), isConnected: true) }
        if let preferred = settings.preferredKeyboard, !choices.contains(where: { $0.id == preferred.id }) {
            choices.append(KeyboardChoice(reference: preferred, isConnected: false))
        }
        return choices
    }
}
