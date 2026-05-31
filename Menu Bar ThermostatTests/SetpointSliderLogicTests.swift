import XCTest

final class SetpointSliderLogicTests: XCTestCase {
    func testInitialSetpointDisplayStateUsesDefaultsWithoutCommandSideEffects() {
        let heatState = ThermostatSetpointDisplayState.initial(
            mode: "HEAT",
            setpoints: nil,
            unit: .fahrenheit
        )

        XCTAssertEqual(heatState.coolValue, 0)
        XCTAssertEqual(heatState.heatValue, 69.8, accuracy: 0.001)

        let mixedState = ThermostatSetpointDisplayState.initial(
            mode: "HEATCOOL",
            setpoints: .init(coolCelsius: nil, heatCelsius: 20),
            unit: .celsius
        )

        XCTAssertEqual(mixedState.coolValue, 24)
        XCTAssertEqual(mixedState.heatValue, 20)
    }

    func testUpdatingSetpointDisplayStatePreservesMissingValuesWithoutDefaultCommand() {
        let state = ThermostatSetpointDisplayState.updating(
            mode: "HEATCOOL",
            setpoints: .init(coolCelsius: nil, heatCelsius: 20),
            unit: .fahrenheit,
            currentCoolValue: 75,
            currentHeatValue: 66
        )

        XCTAssertEqual(state.coolValue, 75)
        XCTAssertEqual(state.heatValue, 68, accuracy: 0.001)

        let offState = ThermostatSetpointDisplayState.updating(
            mode: "OFF",
            setpoints: nil,
            unit: .fahrenheit,
            currentCoolValue: 74,
            currentHeatValue: 68
        )

        XCTAssertEqual(offState.coolValue, 74)
        XCTAssertEqual(offState.heatValue, 68)
    }

    func testHeatOnlyDragUpdatesHeatWithoutMutatingHiddenCoolValue() {
        let values = SetpointSliderLogic.adjustedValues(
            activeThumb: .heat,
            proposedValue: 72,
            coolValue: 0,
            heatValue: 68,
            mode: "HEAT",
            range: 50...90,
            minSetpointGap: 3
        )

        XCTAssertEqual(values.heatValue, 72)
        XCTAssertEqual(values.coolValue, 0)
    }

    func testCoolOnlyDragUpdatesCoolWithoutMutatingHiddenHeatValue() {
        let values = SetpointSliderLogic.adjustedValues(
            activeThumb: .cool,
            proposedValue: 74,
            coolValue: 78,
            heatValue: nil,
            mode: "COOL",
            range: 50...90,
            minSetpointGap: 3
        )

        XCTAssertEqual(values.coolValue, 74)
        XCTAssertEqual(values.heatValue, 74)
    }

    func testMixedHeatDragClampsAgainstCoolWithoutMovingCoolThumb() {
        let values = SetpointSliderLogic.adjustedValues(
            activeThumb: .heat,
            proposedValue: 78,
            coolValue: 76,
            heatValue: 70,
            mode: "HEATCOOL",
            range: 50...90,
            minSetpointGap: 3
        )

        XCTAssertEqual(values.heatValue, 73)
        XCTAssertEqual(values.coolValue, 76)
    }

    func testMixedCoolDragClampsAgainstHeatWithoutMovingHeatThumb() {
        let values = SetpointSliderLogic.adjustedValues(
            activeThumb: .cool,
            proposedValue: 68,
            coolValue: 76,
            heatValue: 70,
            mode: "HEATCOOL",
            range: 50...90,
            minSetpointGap: 3
        )

        XCTAssertEqual(values.coolValue, 73)
        XCTAssertEqual(values.heatValue, 70)
    }

    func testMixedDragWithinGapUpdatesOnlyDraggedSetpointThumb() {
        let heatValues = SetpointSliderLogic.adjustedValues(
            activeThumb: .heat,
            proposedValue: 69,
            coolValue: 76,
            heatValue: 70,
            mode: "HEATCOOL",
            range: 50...90,
            minSetpointGap: 3
        )

        XCTAssertEqual(heatValues.heatValue, 69)
        XCTAssertEqual(heatValues.coolValue, 76)

        let coolValues = SetpointSliderLogic.adjustedValues(
            activeThumb: .cool,
            proposedValue: 77,
            coolValue: 76,
            heatValue: 70,
            mode: "HEATCOOL",
            range: 50...90,
            minSetpointGap: 3
        )

        XCTAssertEqual(coolValues.coolValue, 77)
        XCTAssertEqual(coolValues.heatValue, 70)
    }
}
