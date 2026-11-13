import Foundation

/// Remembers whether the app has run before, so Settings opens on the first launch only.
public enum LaunchHistory {
    static let key = "app.hasLaunched"

    /// Records this launch and returns whether it is the first one.
    ///
    /// Launch at login can only be on after an earlier launch turned it on, so such a launch is never first,
    /// even for a version that did not record launches yet.
    public static func recordLaunch(in defaults: UserDefaults, launchAtLoginEnabled: Bool) -> Bool {
        let isFirst = !defaults.bool(forKey: key) && !launchAtLoginEnabled
        defaults.set(true, forKey: key)
        return isFirst
    }
}
