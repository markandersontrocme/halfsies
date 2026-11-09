import Foundation

/// The battery level of one part of a keyboard, as reported by the Battery Level characteristic (0x2A19).
public enum BatteryLevel: Hashable, Sendable {
    case percent(Int)
    /// ZMK reports 0% for a peripheral that is asleep or out of range, so 0 is never a real level.
    case disconnected

    public init(rawValue: UInt8) {
        self = rawValue == 0 ? .disconnected : .percent(min(Int(rawValue), 100))
    }

    /// Short text for the menu bar and panel: "86%" or "-".
    public var label: String {
        switch self {
        case .percent(let value): "\(value)%"
        case .disconnected: "-"
        }
    }
}

/// Everything the host reads for one Battery Level characteristic: its value and the descriptors that name it.
public struct BatteryCharacteristicReading: Hashable, Sendable {
    public var level: UInt8
    /// Raw Characteristic Presentation Format descriptor (0x2904).
    public var presentationFormat: Data?
    /// Characteristic User Description descriptor (0x2901).
    public var userDescription: String?

    public init(level: UInt8, presentationFormat: Data?, userDescription: String?) {
        self.level = level
        self.presentationFormat = presentationFormat
        self.userDescription = userDescription
    }
}

/// Which part of a split keyboard a battery belongs to.
public enum PartRole: Hashable, Sendable, Comparable {
    /// The half the host is connected to (ZMK's "central").
    case central
    /// A firmware that names the physical side directly.
    case left
    case right
    /// A half that reaches the host through the central, numbered by ZMK in bonding order.
    case peripheral(Int)
}

extension PartRole {
    /// Bluetooth SIG namespace descriptions used by ZMK in the Presentation Format descriptor.
    private enum Description: UInt16 {
        case main = 0x0106
        case auxiliary = 0x0108
        case left = 0x010D
        case right = 0x010E
    }

    /// Identifies a part from its descriptors, never from discovery order.
    /// Returns nil for a battery that is not a keyboard part (for example a "backup" battery).
    public init?(_ reading: BatteryCharacteristicReading) {
        let peripheralIndex = reading.userDescription.flatMap(Self.peripheralIndex(from:))

        if let raw = Self.namespaceDescription(reading.presentationFormat) {
            switch Description(rawValue: raw) {
            case .main: self = .central
            case .auxiliary: self = .peripheral(peripheralIndex ?? 0)
            case .left: self = .left
            case .right: self = .right
            case nil: return nil
            }
            return
        }

        // Without a usable Presentation Format, ZMK only names peripherals.
        if let index = peripheralIndex {
            self = .peripheral(index)
        } else if reading.userDescription == nil {
            self = .central
        } else {
            return nil
        }
    }

    /// The 16-bit description field (bytes 5 and 6, little endian) of a 7-byte Presentation Format value.
    private static func namespaceDescription(_ format: Data?) -> UInt16? {
        guard let format, format.count >= 7 else { return nil }
        let bytes = Array(format)
        return UInt16(bytes[5]) | UInt16(bytes[6]) << 8
    }

    /// Parses ZMK's "Peripheral N" user description.
    private static func peripheralIndex(from description: String) -> Int? {
        let prefix = "Peripheral "
        guard description.hasPrefix(prefix) else { return nil }
        return Int(description.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces))
    }
}

/// One part of a keyboard and its battery level.
public struct Part: Hashable, Sendable {
    public var role: PartRole
    public var level: BatteryLevel

    public init(role: PartRole, level: BatteryLevel) {
        self.role = role
        self.level = level
    }
}

/// Battery levels mapped to physical sides. Nil means the keyboard does not report that side at all.
public struct SplitBattery: Hashable, Sendable {
    public var left: BatteryLevel?
    public var right: BatteryLevel?

    public init(left: BatteryLevel?, right: BatteryLevel?) {
        self.left = left
        self.right = right
    }

    /// Menu bar text, left then right: "86% 39%", with "-" for a missing or disconnected side.
    public var menuBarText: String {
        "\(left?.label ?? "-") \(right?.label ?? "-")"
    }
}
