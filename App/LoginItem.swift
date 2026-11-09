import Observation
import ServiceManagement

/// Launch at login through SMAppService. The system owns the state, so it is read back rather than stored.
@MainActor
@Observable
final class LoginItem {
    private(set) var isEnabled = false
    private(set) var note: String?

    init() {
        refresh()
    }

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        note = status == .requiresApproval ? "Allow Halfsies in System Settings > General > Login Items." : nil
    }

    func setEnabled(_ enabled: Bool) {
        var failure: (any Error)?
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            failure = error
        }
        refresh()
        if let failure {
            note = "Could not change the login item: \(failure.localizedDescription)"
        } else if SMAppService.mainApp.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }
}
