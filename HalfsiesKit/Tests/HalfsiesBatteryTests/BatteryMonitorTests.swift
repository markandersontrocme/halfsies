import Foundation
import HalfsiesCore
import Testing
@testable import HalfsiesBattery

@MainActor
final class FakeTransport: KeyboardTransport {
    let updates: [TransportSnapshot]
    init(_ updates: [TransportSnapshot]) { self.updates = updates }
    /// Keyboard updates with Bluetooth ready.
    convenience init(_ updates: [[Keyboard]]) {
        self.init(updates.map { TransportSnapshot(bluetooth: .ready, keyboards: $0) })
    }

    func snapshots() -> AsyncStream<TransportSnapshot> {
        AsyncStream { continuation in
            for update in updates { continuation.yield(update) }
            continuation.finish()
        }
    }
}

let mainFormat = Data([0x04, 0x00, 0xAD, 0x27, 0x01, 0x06, 0x01])
let auxiliaryFormat = Data([0x04, 0x00, 0xAD, 0x27, 0x01, 0x08, 0x01])

func split(_ name: String, left: UInt8, right: UInt8) -> Keyboard {
    Keyboard(
        id: KeyboardID(rawValue: name), name: name,
        readings: [
            .init(level: left, presentationFormat: mainFormat, userDescription: nil),
            .init(level: right, presentationFormat: auxiliaryFormat, userDescription: "Peripheral 0"),
        ])
}

func single(_ name: String, level: UInt8) -> Keyboard {
    Keyboard(
        id: KeyboardID(rawValue: name), name: name,
        readings: [.init(level: level, presentationFormat: mainFormat, userDescription: nil)])
}

func freshDefaults() -> UserDefaults {
    let suite = "halfsies-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@MainActor
@Suite("BatteryMonitor")
struct BatteryMonitorTests {
    @Test func showsLatestKeyboardState() async {
        let transport = FakeTransport([[split("Forager", left: 90, right: 40)], [split("Forager", left: 86, right: 39)]])
        let monitor = BatteryMonitor(transport: transport, settings: BatterySettings(defaults: freshDefaults()))
        await monitor.run()
        #expect(monitor.split == SplitBattery(left: .percent(86), right: .percent(39)))
        #expect(monitor.menuBarText == "86% 39%")
        #expect(monitor.selectedKeyboard?.name == "Forager")
    }

    @Test func nothingToShowWithoutKeyboards() async {
        let monitor = BatteryMonitor(transport: FakeTransport([[]]), settings: BatterySettings(defaults: freshDefaults()))
        await monitor.run()
        #expect(monitor.selectedKeyboard == nil)
        #expect(monitor.menuBarText == nil)
    }

    @Test func swapSettingFlipsSides() async {
        let settings = BatterySettings(defaults: freshDefaults())
        let monitor = BatteryMonitor(transport: FakeTransport([[split("Forager", left: 86, right: 39)]]), settings: settings)
        await monitor.run()
        settings.swapSides = true
        #expect(monitor.menuBarText == "39% 86%")
    }

    @Test func preferredKeyboardOverridesAutomaticChoice() async {
        let settings = BatterySettings(defaults: freshDefaults())
        let monitor = BatteryMonitor(
            transport: FakeTransport([[split("Corne", left: 10, right: 20), split("Forager", left: 86, right: 39)]]),
            settings: settings)
        await monitor.run()
        #expect(monitor.selectedKeyboard?.name == "Corne")
        settings.preferredKeyboard = KeyboardReference(id: KeyboardID(rawValue: "Forager"), name: "Forager")
        #expect(monitor.selectedKeyboard?.name == "Forager")
    }

    @Test func choicesIncludeDisconnectedPreferredKeyboard() async {
        let settings = BatterySettings(defaults: freshDefaults())
        settings.preferredKeyboard = KeyboardReference(id: KeyboardID(rawValue: "Lily"), name: "Lily")
        let monitor = BatteryMonitor(transport: FakeTransport([[split("Forager", left: 86, right: 39)]]), settings: settings)
        await monitor.run()
        #expect(monitor.choices == [
            KeyboardChoice(reference: .init(id: KeyboardID(rawValue: "Forager"), name: "Forager"), isConnected: true),
            KeyboardChoice(reference: .init(id: KeyboardID(rawValue: "Lily"), name: "Lily"), isConnected: false),
        ])
        #expect(monitor.selectedKeyboard == nil)
    }
}

@MainActor
@Suite("BatterySettings")
struct BatterySettingsTests {
    @Test func defaults() {
        let settings = BatterySettings(defaults: freshDefaults())
        #expect(settings.swapSides == false)
        #expect(settings.preferredKeyboard == nil)
        #expect(settings.compactMenuBar == false)
    }

    @Test func persistsAcrossInstances() {
        let defaults = freshDefaults()
        let first = BatterySettings(defaults: defaults)
        first.swapSides = true
        first.compactMenuBar = true
        first.preferredKeyboard = KeyboardReference(id: KeyboardID(rawValue: "abc"), name: "Forager")

        let second = BatterySettings(defaults: defaults)
        #expect(second.swapSides)
        #expect(second.compactMenuBar)
        #expect(second.preferredKeyboard == KeyboardReference(id: KeyboardID(rawValue: "abc"), name: "Forager"))

        second.preferredKeyboard = nil
        #expect(BatterySettings(defaults: defaults).preferredKeyboard == nil)
    }
}

@MainActor
@Suite("SetupStatus")
struct SetupStatusTests {
    func status(_ bluetooth: BluetoothAvailability, _ keyboards: [Keyboard], preferred: String? = nil) async
        -> SetupStatus
    {
        let settings = BatterySettings(defaults: freshDefaults())
        settings.preferredKeyboard = preferred.map { KeyboardReference(id: KeyboardID(rawValue: $0), name: $0) }
        let transport = FakeTransport([TransportSnapshot(bluetooth: bluetooth, keyboards: keyboards)])
        let monitor = BatteryMonitor(transport: transport, settings: settings)
        await monitor.run()
        return monitor.status
    }

    @Test func waitsForPermissionBeforeTheTransportReports() {
        let transport = FakeTransport([TransportSnapshot]())
        let monitor = BatteryMonitor(transport: transport, settings: BatterySettings(defaults: freshDefaults()))
        #expect(monitor.status == .waitingForPermission)
    }

    @Test func bluetoothProblemsComeFirst() async {
        #expect(await status(.waitingForPermission, []) == .waitingForPermission)
        #expect(await status(.denied, []) == .permissionDenied)
        #expect(await status(.poweredOff, []) == .bluetoothOff)
        #expect(await status(.unsupported, []) == .bluetoothUnsupported)
    }

    @Test func readyWithoutKeyboards() async {
        #expect(await status(.ready, []) == .noKeyboard)
    }

    @Test func showsTheSelectedSplit() async {
        #expect(await status(.ready, [split("Forager", left: 86, right: 39)]) == .showing(name: "Forager"))
    }

    @Test func explainsAKeyboardWithOneBattery() async {
        #expect(await status(.ready, [single("Forager", level: 86)]) == .singleBattery(name: "Forager"))
        #expect(
            await status(.ready, [single("Forager", level: 86)], preferred: "Forager") == .singleBattery(name: "Forager"))
    }

    @Test func aSplitWinsOverAOneBatteryDevice() async {
        let keyboards = [single("Mouse", level: 50), split("Forager", left: 86, right: 39)]
        #expect(await status(.ready, keyboards) == .showing(name: "Forager"))
    }

    @Test func namesAPickedKeyboardThatIsNotConnected() async {
        let corne = split("Corne", left: 10, right: 20)
        #expect(await status(.ready, [corne], preferred: "Forager") == .notConnected(name: "Forager"))
    }
}
