import Foundation
import Testing
@testable import HalfsiesCore

/// Descriptor bytes captured from a real ZMK split ("Forager") on 2026-11-09.
/// Layout: format=uint8, exponent=0, unit=0x27AD (percentage), namespace=SIG, description (little endian).
enum Forager {
    static let mainFormat = Data([0x04, 0x00, 0xAD, 0x27, 0x01, 0x06, 0x01])
    static let auxiliaryFormat = Data([0x04, 0x00, 0xAD, 0x27, 0x01, 0x08, 0x01])
    static let leftFormat = Data([0x04, 0x00, 0xAD, 0x27, 0x01, 0x0D, 0x01])
    static let rightFormat = Data([0x04, 0x00, 0xAD, 0x27, 0x01, 0x0E, 0x01])

    static let central = BatteryCharacteristicReading(level: 86, presentationFormat: mainFormat, userDescription: nil)
    static let peripheral = BatteryCharacteristicReading(
        level: 39, presentationFormat: auxiliaryFormat, userDescription: "Peripheral 0")
}

@Suite("BatteryLevel")
struct BatteryLevelTests {
    @Test func zeroMeansDisconnected() {
        #expect(BatteryLevel(rawValue: 0) == .disconnected)
    }

    @Test(arguments: [1, 39, 86, 100])
    func validPercentages(_ raw: Int) {
        #expect(BatteryLevel(rawValue: UInt8(raw)) == .percent(raw))
    }

    @Test func valuesAbove100AreClamped() {
        #expect(BatteryLevel(rawValue: 255) == .percent(100))
    }

    @Test func labels() {
        #expect(BatteryLevel.percent(86).label == "86%")
        #expect(BatteryLevel.disconnected.label == "-")
    }

    @Test func lowAtOrBelowTwentyPercent() {
        #expect(BatteryLevel.percent(1).isLow)
        #expect(BatteryLevel.percent(20).isLow)
        #expect(!BatteryLevel.percent(21).isLow)
        #expect(!BatteryLevel.disconnected.isLow)
    }
}

@Suite("PartRole identification")
struct PartRoleTests {
    @Test func foragerCentral() {
        #expect(PartRole(Forager.central) == .central)
    }

    @Test func foragerPeripheral() {
        #expect(PartRole(Forager.peripheral) == .peripheral(0))
    }

    @Test func peripheralIndexComesFromUserDescription() {
        let reading = BatteryCharacteristicReading(
            level: 50, presentationFormat: Forager.auxiliaryFormat, userDescription: "Peripheral 1")
        #expect(PartRole(reading) == .peripheral(1))
    }

    @Test func auxiliaryWithoutUserDescriptionIsPeripheralZero() {
        let reading = BatteryCharacteristicReading(
            level: 50, presentationFormat: Forager.auxiliaryFormat, userDescription: nil)
        #expect(PartRole(reading) == .peripheral(0))
    }

    @Test func explicitSidesFromFirmware() {
        #expect(PartRole(.init(level: 1, presentationFormat: Forager.leftFormat, userDescription: nil)) == .left)
        #expect(PartRole(.init(level: 1, presentationFormat: Forager.rightFormat, userDescription: nil)) == .right)
    }

    @Test func withoutFormatAUserDescriptionMeansPeripheral() {
        let reading = BatteryCharacteristicReading(level: 50, presentationFormat: nil, userDescription: "Peripheral 2")
        #expect(PartRole(reading) == .peripheral(2))
    }

    @Test func withoutAnyDescriptorItIsTheCentral() {
        let reading = BatteryCharacteristicReading(level: 50, presentationFormat: nil, userDescription: nil)
        #expect(PartRole(reading) == .central)
    }

    @Test func malformedFormatFallsBackToUserDescription() {
        let reading = BatteryCharacteristicReading(
            level: 50, presentationFormat: Data([0x04]), userDescription: "Peripheral 0")
        #expect(PartRole(reading) == .peripheral(0))
    }

    @Test func unknownDescriptionIsNotAPart() {
        let other = Data([0x04, 0x00, 0xAD, 0x27, 0x01, 0x07, 0x01])  // "backup"
        #expect(PartRole(.init(level: 50, presentationFormat: other, userDescription: nil)) == nil)
    }
}
