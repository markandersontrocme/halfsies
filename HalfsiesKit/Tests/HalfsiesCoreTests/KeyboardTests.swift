import Foundation
import Testing
@testable import HalfsiesCore

func keyboard(_ name: String, _ readings: [BatteryCharacteristicReading], id: String? = nil) -> Keyboard {
    Keyboard(id: KeyboardID(rawValue: id ?? name), name: name, readings: readings)
}

@Suite("Keyboard")
struct KeyboardTests {
    @Test func identifiesPartsRegardlessOfDiscoveryOrder() {
        let kb = keyboard("Forager", [Forager.peripheral, Forager.central])
        #expect(kb.parts == [
            Part(role: .central, level: .percent(86)),
            Part(role: .peripheral(0), level: .percent(39)),
        ])
    }

    @Test func dropsUnidentifiableAndDuplicateParts() {
        let backup = BatteryCharacteristicReading(
            level: 10, presentationFormat: Data([0x04, 0x00, 0xAD, 0x27, 0x01, 0x07, 0x01]), userDescription: nil)
        let secondCentral = BatteryCharacteristicReading(level: 20, presentationFormat: nil, userDescription: nil)
        let kb = keyboard("Forager", [Forager.central, backup, secondCentral])
        #expect(kb.parts == [Part(role: .central, level: .percent(86))])
    }

    @Test func isSplitNeedsTwoParts() {
        #expect(keyboard("Forager", [Forager.central, Forager.peripheral]).isSplit)
        #expect(!keyboard("Mono", [Forager.central]).isSplit)
    }
}

@Suite("Sides")
struct SidesTests {
    let forager = keyboard("Forager", [Forager.central, Forager.peripheral])

    @Test func centralIsLeftByDefault() {
        #expect(forager.sides(swapped: false) == SplitBattery(left: .percent(86), right: .percent(39)))
    }

    @Test func swapFlipsSides() {
        #expect(forager.sides(swapped: true) == SplitBattery(left: .percent(39), right: .percent(86)))
    }

    @Test func missingPeripheralLeavesRightEmpty() {
        let kb = keyboard("Forager", [Forager.central])
        #expect(kb.sides(swapped: false) == SplitBattery(left: .percent(86), right: nil))
    }

    @Test func sleepingPeripheralIsDisconnected() {
        let asleep = BatteryCharacteristicReading(
            level: 0, presentationFormat: Forager.auxiliaryFormat, userDescription: "Peripheral 0")
        let kb = keyboard("Forager", [Forager.central, asleep])
        #expect(kb.sides(swapped: false) == SplitBattery(left: .percent(86), right: .disconnected))
    }

    @Test func firmwareSidesWinOverTopology() {
        let left = BatteryCharacteristicReading(level: 70, presentationFormat: Forager.leftFormat, userDescription: nil)
        let right = BatteryCharacteristicReading(level: 60, presentationFormat: Forager.rightFormat, userDescription: nil)
        let kb = keyboard("Forager", [right, left])
        #expect(kb.sides(swapped: false) == SplitBattery(left: .percent(70), right: .percent(60)))
    }

    @Test func menuBarText() {
        #expect(SplitBattery(left: .percent(86), right: .percent(39)).menuBarText == "86% 39%")
        #expect(SplitBattery(left: .percent(86), right: .disconnected).menuBarText == "86% -")
        #expect(SplitBattery(left: .percent(86), right: nil).menuBarText == "86% -")
    }

    @Test func lowWhenEitherSideIsLow() {
        #expect(SplitBattery(left: .percent(86), right: .percent(12)).isLow)
        #expect(SplitBattery(left: .percent(12), right: nil).isLow)
        #expect(!SplitBattery(left: .percent(86), right: .disconnected).isLow)
        #expect(!SplitBattery(left: nil, right: nil).isLow)
    }

    @Test func accessibilityDescription() {
        #expect(SplitBattery(left: .percent(86), right: .percent(39)).accessibilityDescription == "Left 86%, right 39%")
        #expect(SplitBattery(left: .percent(86), right: .disconnected).accessibilityDescription == "Left 86%, right asleep")
        #expect(SplitBattery(left: nil, right: .percent(39)).accessibilityDescription == "Left not reported, right 39%")
    }
}

@Suite("Keyboard selection")
struct SelectionTests {
    let mono = keyboard("A Mono", [Forager.central])
    let forager = keyboard("Forager", [Forager.central, Forager.peripheral])
    let corne = keyboard("Corne", [Forager.central, Forager.peripheral])

    @Test func automaticPicksFirstSplitByName() {
        #expect(Keyboard.select(from: [forager, mono, corne], preferred: nil) == corne)
    }

    @Test func automaticIgnoresNonSplitKeyboards() {
        #expect(Keyboard.select(from: [mono], preferred: nil) == nil)
    }

    @Test func preferredWinsEvenIfNotSplit() {
        #expect(Keyboard.select(from: [forager, mono], preferred: mono.id) == mono)
    }

    @Test func preferredButAbsentSelectsNothing() {
        #expect(Keyboard.select(from: [corne], preferred: forager.id) == nil)
    }
}
