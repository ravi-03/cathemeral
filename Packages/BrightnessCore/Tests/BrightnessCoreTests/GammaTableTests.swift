import BrightnessCore
import Testing

@Suite struct GammaTableTests {
    /// A calibrated-looking curve, not a straight line, so a linear ramp can't pass by accident.
    let original = GammaTable(
        red: [0.0, 0.11, 0.37, 0.72, 0.98],
        green: [0.0, 0.12, 0.36, 0.71, 0.97],
        blue: [0.01, 0.13, 0.35, 0.70, 0.99]
    )

    @Test func levelOneReturnsTheOriginalByteForByte() {
        let table = original.scaled(to: .full)
        #expect(table.red.map(\.bitPattern) == original.red.map(\.bitPattern))
        #expect(table.green.map(\.bitPattern) == original.green.map(\.bitPattern))
        #expect(table.blue.map(\.bitPattern) == original.blue.map(\.bitPattern))
    }

    @Test func levelPointFourScalesEveryEntryOfTheOriginal() {
        let table = original.scaled(to: Level(0.4))
        #expect(table.red == original.red.map { $0 * 0.4 })
        #expect(table.green == original.green.map { $0 * 0.4 })
        #expect(table.blue == original.blue.map { $0 * 0.4 })
    }

    @Test func aLevelBelowTheFloorScalesByTheFloor() {
        let table = original.scaled(to: Level(0.0))
        #expect(table.red == original.red.map { $0 * 0.1 })
        #expect(table.red.last! > 0)
    }
}
