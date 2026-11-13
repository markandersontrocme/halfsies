import Foundation

/// How a transport recovers from failed battery reads.
///
/// A transport that cannot finish reading a keyboard drops it and lets its next discovery pass attach again.
/// This type holds the decisions as plain logic so they can be tested without Bluetooth.
public enum ReadRetry {
    /// Failed re-reads in a row that a battery with a known level survives, keeping its last value.
    public static let toleratedFailedRereads = 3

    /// Whether a failed read should drop the keyboard so it is attached again.
    /// - Parameters:
    ///   - hasLevel: Whether this battery was read successfully before.
    ///     A battery with no level yet keeps the keyboard hidden, so the keyboard is dropped right away.
    ///   - consecutiveFailures: Failed reads of this battery in a row, including this one.
    public static func shouldReattach(hasLevel: Bool, consecutiveFailures: Int) -> Bool {
        !hasLevel || consecutiveFailures >= toleratedFailedRereads
    }
}

/// Spaces out attempts to attach to a keyboard that keeps failing.
///
/// After the first failure a keyboard may be attached again after `initialDelay`.
/// Each further failure in a row doubles the delay, up to `maximumDelay`.
/// A successful read clears the history.
public struct AttachBackoff: Sendable {
    private struct Failures: Sendable {
        var count: Int
        var retryAt: ContinuousClock.Instant
    }

    public let initialDelay: Duration
    public let maximumDelay: Duration
    private var failures: [KeyboardID: Failures] = [:]

    public init(initialDelay: Duration = .seconds(10), maximumDelay: Duration = .seconds(300)) {
        self.initialDelay = initialDelay
        self.maximumDelay = maximumDelay
    }

    /// How long to wait before attaching again after `count` failures in a row.
    public func delay(afterFailures count: Int) -> Duration {
        guard count > 0 else { return .zero }
        // Cap the exponent so the multiplication cannot overflow; the maximum applies long before.
        let factor = 1 << min(count - 1, 20)
        return min(initialDelay * factor, maximumDelay)
    }

    /// Whether the keyboard may be attached at `now`.
    public func allowsAttach(_ id: KeyboardID, at now: ContinuousClock.Instant) -> Bool {
        guard let entry = failures[id] else { return true }
        return now >= entry.retryAt
    }

    /// Records a failed attach or read and schedules the next allowed attempt.
    public mutating func recordFailure(_ id: KeyboardID, at now: ContinuousClock.Instant) {
        let count = (failures[id]?.count ?? 0) + 1
        failures[id] = Failures(count: count, retryAt: now + delay(afterFailures: count))
    }

    /// Records that the keyboard was read in full, so its next failure starts from the initial delay.
    public mutating func recordSuccess(_ id: KeyboardID) {
        failures[id] = nil
    }
}
