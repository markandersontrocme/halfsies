import CoreBluetooth
import HalfsiesCore
import Testing
@testable import HalfsiesBLE

/// Only the state and authorization enums are used here; no Bluetooth manager is created.
@Suite("BluetoothAvailability")
struct BluetoothAvailabilityTests {
    @Test func noStateYetMeansWaitingForPermission() {
        #expect(BluetoothAvailability(state: .unknown, authorization: .notDetermined) == .waitingForPermission)
        #expect(BluetoothAvailability(state: .unknown, authorization: .allowedAlways) == .waitingForPermission)
    }

    @Test func deniedOrRestrictedPermissionWinsOverState() {
        #expect(BluetoothAvailability(state: .unauthorized, authorization: .denied) == .denied)
        #expect(BluetoothAvailability(state: .poweredOn, authorization: .restricted) == .denied)
        #expect(BluetoothAvailability(state: .unauthorized, authorization: .allowedAlways) == .denied)
    }

    @Test func allowedPermissionFollowsTheState() {
        #expect(BluetoothAvailability(state: .poweredOn, authorization: .allowedAlways) == .ready)
        #expect(BluetoothAvailability(state: .poweredOff, authorization: .allowedAlways) == .poweredOff)
        #expect(BluetoothAvailability(state: .unsupported, authorization: .allowedAlways) == .unsupported)
    }
}
