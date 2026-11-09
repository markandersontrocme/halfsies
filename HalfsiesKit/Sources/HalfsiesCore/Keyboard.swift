import Foundation

/// Stable identity of a keyboard across launches (the system's Bluetooth identifier).
public struct KeyboardID: Hashable, Sendable, Codable, RawRepresentable {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// A snapshot of one connected keyboard. Features read from it; transports produce it.
public struct Keyboard: Hashable, Sendable, Identifiable {
    public var id: KeyboardID
    public var name: String
    /// Identified parts, ordered central, left, right, then peripherals by index.
    public var parts: [Part]

    public init(id: KeyboardID, name: String, parts: [Part]) {
        self.id = id
        self.name = name
        self.parts = parts.sorted { $0.role < $1.role }
    }

    /// Builds a keyboard from raw battery readings, dropping batteries that are not parts and duplicate roles.
    public init(id: KeyboardID, name: String, readings: [BatteryCharacteristicReading]) {
        var parts: [PartRole: Part] = [:]
        for reading in readings {
            guard let role = PartRole(reading), parts[role] == nil else { continue }
            parts[role] = Part(role: role, level: BatteryLevel(rawValue: reading.level))
        }
        self.init(id: id, name: name, parts: Array(parts.values))
    }

    /// A split reports a battery for at least two parts.
    public var isSplit: Bool { parts.count >= 2 }

    /// Maps parts to physical sides.
    /// Firmware that names sides is trusted; otherwise the central is left and the first peripheral is right.
    /// `swapped` flips the result for keyboards whose central is the right half.
    public func sides(swapped: Bool) -> SplitBattery {
        func level(_ role: PartRole) -> BatteryLevel? { parts.first { $0.role == role }?.level }

        let firmwareSides = parts.contains { $0.role == .left || $0.role == .right }
        let split: SplitBattery
        if firmwareSides {
            split = SplitBattery(left: level(.left), right: level(.right))
        } else {
            let first = parts.first?.level
            let second = parts.dropFirst().first?.level
            split = SplitBattery(left: first, right: second)
        }
        return swapped ? SplitBattery(left: split.right, right: split.left) : split
    }

    /// Picks the keyboard to show.
    /// A preferred keyboard is shown only when it is connected.
    /// Otherwise the first split keyboard by name is chosen.
    public static func select(from keyboards: [Keyboard], preferred: KeyboardID?) -> Keyboard? {
        if let preferred {
            return keyboards.first { $0.id == preferred }
        }
        return keyboards
            .filter(\.isSplit)
            .min { ($0.name, $0.id.rawValue) < ($1.name, $1.id.rawValue) }
    }
}

/// Produces snapshots of every connected keyboard whenever anything changes.
@MainActor
public protocol KeyboardTransport: AnyObject {
    /// Starts the transport and yields the full set of connected keyboards on each change.
    /// Call once; the stream has a single consumer.
    func keyboards() -> AsyncStream<[Keyboard]>
}
