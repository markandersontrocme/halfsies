import Foundation
import HalfsiesCore
import Observation

/// A keyboard the user picked, remembered with its name so it can be listed while disconnected.
public struct KeyboardReference: Hashable, Sendable, Codable {
    public var id: KeyboardID
    public var name: String

    public init(id: KeyboardID, name: String) {
        self.id = id
        self.name = name
    }
}

/// User preferences for the battery feature, persisted in UserDefaults.
@MainActor
@Observable
public final class BatterySettings {
    private enum Key {
        static let swapSides = "battery.swapSides"
        static let preferredKeyboard = "battery.preferredKeyboard"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Show the central half on the right instead of the left.
    public var swapSides: Bool {
        didSet { defaults.set(swapSides, forKey: Key.swapSides) }
    }

    /// The keyboard to show; nil picks one automatically.
    public var preferredKeyboard: KeyboardReference? {
        didSet {
            let data = preferredKeyboard.flatMap { try? JSONEncoder().encode($0) }
            defaults.set(data, forKey: Key.preferredKeyboard)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        swapSides = defaults.bool(forKey: Key.swapSides)
        preferredKeyboard = defaults.data(forKey: Key.preferredKeyboard)
            .flatMap { try? JSONDecoder().decode(KeyboardReference.self, from: $0) }
    }
}
