import Foundation
import Testing
@testable import HalfsiesCore

@Suite("LaunchHistory")
struct LaunchHistoryTests {
    func freshDefaults() -> UserDefaults {
        let suite = "halfsies-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func onlyTheFirstLaunchIsFirst() {
        let defaults = freshDefaults()
        #expect(LaunchHistory.recordLaunch(in: defaults, launchAtLoginEnabled: false))
        #expect(!LaunchHistory.recordLaunch(in: defaults, launchAtLoginEnabled: false))
        #expect(!LaunchHistory.recordLaunch(in: defaults, launchAtLoginEnabled: true))
    }

    @Test func launchAtLoginMeansTheAppRanBefore() {
        let defaults = freshDefaults()
        #expect(!LaunchHistory.recordLaunch(in: defaults, launchAtLoginEnabled: true))
        #expect(!LaunchHistory.recordLaunch(in: defaults, launchAtLoginEnabled: false))
    }
}
