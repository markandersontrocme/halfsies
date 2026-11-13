import Testing
@testable import HalfsiesCore

@Suite("ReadRetry")
struct ReadRetryTests {
    @Test func failureBeforeFirstReadReattachesRightAway() {
        #expect(ReadRetry.shouldReattach(hasLevel: false, consecutiveFailures: 1))
    }

    @Test func failedRereadsKeepTheLastValueUntilTheThird() {
        #expect(!ReadRetry.shouldReattach(hasLevel: true, consecutiveFailures: 1))
        #expect(!ReadRetry.shouldReattach(hasLevel: true, consecutiveFailures: 2))
        #expect(ReadRetry.shouldReattach(hasLevel: true, consecutiveFailures: 3))
    }
}

@Suite("AttachBackoff")
struct AttachBackoffTests {
    let forager = KeyboardID(rawValue: "Forager")
    let start = ContinuousClock.now

    @Test func attachesKeyboardsWithoutFailures() {
        #expect(AttachBackoff().allowsAttach(forager, at: start))
    }

    @Test func waitsTheInitialDelayAfterOneFailure() {
        var backoff = AttachBackoff(initialDelay: .seconds(10), maximumDelay: .seconds(300))
        backoff.recordFailure(forager, at: start)
        #expect(!backoff.allowsAttach(forager, at: start + .seconds(9)))
        #expect(backoff.allowsAttach(forager, at: start + .seconds(10)))
    }

    @Test func doublesTheDelayUpToTheMaximum() {
        let backoff = AttachBackoff(initialDelay: .seconds(10), maximumDelay: .seconds(300))
        let delays = (1...8).map { backoff.delay(afterFailures: $0) }
        #expect(delays == [10, 20, 40, 80, 160, 300, 300, 300].map { Duration.seconds($0) })
        #expect(backoff.delay(afterFailures: 1000) == .seconds(300))
    }

    @Test func repeatedFailuresWaitLonger() {
        var backoff = AttachBackoff(initialDelay: .seconds(10), maximumDelay: .seconds(300))
        backoff.recordFailure(forager, at: start)
        let second = start + .seconds(10)
        backoff.recordFailure(forager, at: second)
        #expect(!backoff.allowsAttach(forager, at: second + .seconds(19)))
        #expect(backoff.allowsAttach(forager, at: second + .seconds(20)))
    }

    @Test func successClearsTheHistory() {
        var backoff = AttachBackoff(initialDelay: .seconds(10), maximumDelay: .seconds(300))
        backoff.recordFailure(forager, at: start)
        backoff.recordFailure(forager, at: start)
        backoff.recordSuccess(forager)
        #expect(backoff.allowsAttach(forager, at: start))
        backoff.recordFailure(forager, at: start)
        #expect(backoff.allowsAttach(forager, at: start + .seconds(10)))
    }

    @Test func tracksKeyboardsSeparately() {
        var backoff = AttachBackoff()
        backoff.recordFailure(forager, at: start)
        #expect(backoff.allowsAttach(KeyboardID(rawValue: "Corne"), at: start))
    }
}
