/// Whether the transport can reach keyboards at all.
public enum BluetoothAvailability: Hashable, Sendable {
    /// The user has not answered the permission prompt yet.
    /// macOS sends no Bluetooth state until they do, so this is also the state before the first update.
    case waitingForPermission
    /// The user denied Bluetooth access, or a policy restricts it.
    case denied
    case poweredOff
    /// This Mac has no Bluetooth Low Energy.
    case unsupported
    case ready
}

/// Everything a transport knows at one moment.
public struct TransportSnapshot: Hashable, Sendable {
    public var bluetooth: BluetoothAvailability
    /// Every connected keyboard that has been read in full.
    public var keyboards: [Keyboard]

    public init(bluetooth: BluetoothAvailability, keyboards: [Keyboard]) {
        self.bluetooth = bluetooth
        self.keyboards = keyboards
    }
}

/// Produces snapshots of Bluetooth availability and every connected keyboard whenever anything changes.
@MainActor
public protocol KeyboardTransport: AnyObject {
    /// Starts the transport and yields a full snapshot on each change.
    /// Call once; the stream has a single consumer.
    func snapshots() -> AsyncStream<TransportSnapshot>
}
