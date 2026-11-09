import CoreBluetooth
import HalfsiesCore
import os

private let log = Logger(subsystem: "com.markandersontrocme.halfsies", category: "ble")

/// Reads battery levels from keyboards that macOS has already connected over Bluetooth LE.
///
/// It attaches to the system's existing connection (it never scans or pairs), reads every Battery Service
/// instance with the descriptors that name it, subscribes to notifications, and re-reads periodically
/// as a safety net. Keyboards are published only once every battery and its descriptors have been read,
/// so a part is never shown under the wrong role.
@MainActor
public final class BLEKeyboardTransport: NSObject, KeyboardTransport {
    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")
    private static let presentationFormat = CBUUID(string: CBUUIDCharacteristicFormatString)
    private static let userDescription = CBUUID(string: CBUUIDCharacteristicUserDescriptionString)

    private let discoveryInterval: Duration
    private let refreshInterval: Duration

    private var central: CBCentralManager?
    private var sessions: [UUID: Session] = [:]
    private var continuation: AsyncStream<[Keyboard]>.Continuation?
    private var lastPublished: [Keyboard]?
    private var timers: [Task<Void, Never>] = []

    /// - Parameters:
    ///   - discoveryInterval: How often to look for keyboards the system has newly connected.
    ///     CoreBluetooth has no callback for that on macOS, and the lookup is a cheap local call.
    ///   - refreshInterval: How often to re-read levels in case a notification was missed.
    public init(discoveryInterval: Duration = .seconds(10), refreshInterval: Duration = .seconds(60)) {
        self.discoveryInterval = discoveryInterval
        self.refreshInterval = refreshInterval
    }

    public func keyboards() -> AsyncStream<[Keyboard]> {
        let (stream, continuation) = AsyncStream.makeStream(of: [Keyboard].self, bufferingPolicy: .bufferingNewest(1))
        self.continuation = continuation
        central = CBCentralManager(delegate: self, queue: .main)
        timers = [
            repeating(every: discoveryInterval) { $0.discoverConnectedKeyboards() },
            repeating(every: refreshInterval) { $0.refreshLevels() },
        ]
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        return stream
    }

    private func stop() {
        timers.forEach { $0.cancel() }
        timers = []
        if let central {
            for session in sessions.values { central.cancelPeripheralConnection(session.peripheral) }
        }
        sessions = [:]
        central = nil
    }

    private func repeating(every interval: Duration, _ action: @escaping @MainActor (BLEKeyboardTransport) -> Void)
        -> Task<Void, Never>
    {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self else { return }
                action(self)
            }
        }
    }

    // MARK: - Discovery and refresh

    private func discoverConnectedKeyboards() {
        guard let central, central.state == .poweredOn else { return }
        for peripheral in central.retrieveConnectedPeripherals(withServices: [Self.batteryService])
        where sessions[peripheral.identifier] == nil {
            log.info("Attaching to \(peripheral.name ?? "?", privacy: .public) \(peripheral.identifier)")
            let session = Session(peripheral: peripheral)
            sessions[peripheral.identifier] = session
            peripheral.delegate = self
            central.connect(peripheral)
        }
    }

    private func refreshLevels() {
        for session in sessions.values where session.peripheral.state == .connected {
            for characteristic in session.characteristics {
                session.peripheral.readValue(for: characteristic)
            }
        }
    }

    // MARK: - Publishing

    private func publish() {
        let keyboards = sessions.values
            .compactMap(\.keyboard)
            .sorted { $0.id.rawValue < $1.id.rawValue }
        guard keyboards != lastPublished else { return }
        lastPublished = keyboards
        log.info("Publishing \(keyboards.count) keyboard(s): \(keyboards.map { "\($0.name) \($0.parts)" }, privacy: .public)")
        continuation?.yield(keyboards)
    }

    private func session(for peripheral: CBPeripheral) -> Session? {
        sessions[peripheral.identifier]
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEKeyboardTransport: @MainActor CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log.info("Bluetooth state \(central.state.rawValue), authorization \(CBManager.authorization.rawValue)")
        if central.state == .poweredOn {
            discoverConnectedKeyboards()
        } else {
            sessions = [:]
            publish()
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        session(for: peripheral)?.reset()
        peripheral.discoverServices([Self.batteryService])
    }

    public func centralManager(
        _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?
    ) {
        guard let session = session(for: peripheral) else { return }
        log.info("Disconnected from \(peripheral.name ?? "?", privacy: .public): \(String(describing: error))")
        session.reset()
        publish()
        // A pending local connection completes when the system reconnects the keyboard, for example after sleep.
        central.connect(peripheral)
    }

    public func centralManager(
        _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?
    ) {
        // Forget it; the next discovery pass picks it up again if the system still has it connected.
        sessions[peripheral.identifier] = nil
        publish()
    }
}

// MARK: - CBPeripheralDelegate

extension BLEKeyboardTransport: @MainActor CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard let session = session(for: peripheral) else { return }
        let services = (peripheral.services ?? []).filter { $0.uuid == Self.batteryService }
        session.pendingServices = services.count
        for service in services {
            peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
        }
        publish()
    }

    public func peripheral(
        _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?
    ) {
        guard let session = session(for: peripheral) else { return }
        for characteristic in service.characteristics ?? [] where characteristic.uuid == Self.batteryLevel {
            session.track(characteristic)
            peripheral.readValue(for: characteristic)
            peripheral.discoverDescriptors(for: characteristic)
            if characteristic.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        session.pendingServices = max(0, (session.pendingServices ?? 1) - 1)
        publish()
    }

    public func peripheral(
        _ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: (any Error)?
    ) {
        guard let session = session(for: peripheral) else { return }
        let naming = (characteristic.descriptors ?? []).filter {
            $0.uuid == Self.presentationFormat || $0.uuid == Self.userDescription
        }
        session.update(characteristic) { $0.pendingDescriptors = naming.count }
        naming.forEach { peripheral.readValue(for: $0) }
        publish()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: (any Error)?) {
        guard let session = session(for: peripheral), let characteristic = descriptor.characteristic else { return }
        session.update(characteristic) { state in
            if error == nil {
                switch descriptor.uuid {
                case Self.presentationFormat: state.presentationFormat = descriptor.value as? Data
                case Self.userDescription: state.userDescription = descriptor.value as? String
                default: break
                }
            }
            state.pendingDescriptors = max(0, (state.pendingDescriptors ?? 1) - 1)
        }
        publish()
    }

    public func peripheral(
        _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?
    ) {
        guard error == nil, let session = session(for: peripheral), let byte = characteristic.value?.first else {
            return
        }
        session.update(characteristic) { $0.level = byte }
        publish()
    }

    public func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        // The firmware's GATT table changed (Service Changed); start over for this keyboard.
        guard let session = session(for: peripheral) else { return }
        session.reset()
        publish()
        peripheral.discoverServices([Self.batteryService])
    }

    public func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        publish()
    }
}

// MARK: - Session

/// Read state for one keyboard while it is connected.
@MainActor
private final class Session {
    struct CharacteristicState {
        var level: UInt8?
        var presentationFormat: Data?
        var userDescription: String?
        /// Nil until descriptor discovery finishes, then the number of naming descriptors still being read.
        var pendingDescriptors: Int?

        var reading: BatteryCharacteristicReading? {
            guard let level, pendingDescriptors == 0 else { return nil }
            return BatteryCharacteristicReading(
                level: level, presentationFormat: presentationFormat, userDescription: userDescription)
        }
    }

    let peripheral: CBPeripheral
    private(set) var characteristics: [CBCharacteristic] = []
    private var states: [ObjectIdentifier: CharacteristicState] = [:]
    /// Nil until service discovery finishes, then the number of battery services whose characteristics are pending.
    var pendingServices: Int?

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
    }

    func reset() {
        characteristics = []
        states = [:]
        pendingServices = nil
    }

    func track(_ characteristic: CBCharacteristic) {
        let id = ObjectIdentifier(characteristic)
        guard states[id] == nil else { return }
        characteristics.append(characteristic)
        states[id] = CharacteristicState()
    }

    func update(_ characteristic: CBCharacteristic, _ change: (inout CharacteristicState) -> Void) {
        let id = ObjectIdentifier(characteristic)
        guard var state = states[id] else { return }
        change(&state)
        states[id] = state
    }

    /// The keyboard snapshot, or nil while anything is still being read.
    var keyboard: Keyboard? {
        guard peripheral.state == .connected, pendingServices == 0, !characteristics.isEmpty else { return nil }
        var readings: [BatteryCharacteristicReading] = []
        for characteristic in characteristics {
            guard let reading = states[ObjectIdentifier(characteristic)]?.reading else { return nil }
            readings.append(reading)
        }
        return Keyboard(
            id: KeyboardID(rawValue: peripheral.identifier.uuidString),
            name: peripheral.name ?? "Keyboard",
            readings: readings)
    }
}
