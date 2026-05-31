import XCTest

final class ThermostatSnapshotMappingTests: XCTestCase {
    func testThermostatSnapshotMapsGoogleSDMState() {
        let device = TestFixtures.thermostatDevice(
            customName: "Hallway",
            connectivity: "ONLINE",
            mode: "HEATCOOL",
            hvacStatus: "COOLING",
            heatCelsius: 20,
            coolCelsius: 25,
            ambientTemperatureCelsius: 22.5,
            ambientHumidityPercent: 41,
            ecoAvailableModes: ["MANUAL_ECO"],
            ecoHeatCelsius: 16,
            ecoCoolCelsius: 28,
            fanTimerMode: "ON",
            fanTimerTimeout: "2026-05-27T18:00:00Z"
        )

        let thermostat = device.thermostatSnapshot

        XCTAssertEqual(thermostat.id, device.id)
        XCTAssertEqual(thermostat.displayName, "Hallway")
        XCTAssertEqual(thermostat.connectionState, .online)
        XCTAssertEqual(thermostat.mode, .heatCool)
        XCTAssertEqual(thermostat.hvacState, .cooling)
        XCTAssertEqual(thermostat.ambientTemperatureCelsius, 22.5)
        XCTAssertEqual(thermostat.ambientHumidityPercent, 41)
        XCTAssertEqual(thermostat.setpoints.heatCelsius, 20)
        XCTAssertEqual(thermostat.setpoints.coolCelsius, 25)
        XCTAssertEqual(thermostat.eco.heatCelsius, 16)
        XCTAssertEqual(thermostat.eco.coolCelsius, 28)
        XCTAssertTrue(thermostat.capabilities.supportsEco)
        XCTAssertTrue(thermostat.capabilities.hasFan)
        XCTAssertTrue(thermostat.fan.isTimerOn)
        XCTAssertEqual(thermostat.fan.timerTimeout, "2026-05-27T18:00:00Z")
        XCTAssertEqual(thermostat.capabilities.availableModes, [.off, .heat, .cool, .heatCool])
    }

    func testThermostatSnapshotMapsManualEcoAsCurrentMode() {
        let device = TestFixtures.thermostatDevice(
            connectivity: "OFFLINE",
            mode: "HEAT",
            hvacStatus: "OFF",
            ecoMode: "MANUAL_ECO",
            ecoAvailableModes: ["MANUAL_ECO"]
        )

        let thermostat = device.thermostatSnapshot

        XCTAssertEqual(thermostat.connectionState, .offline)
        XCTAssertEqual(thermostat.mode, .eco)
        XCTAssertTrue(thermostat.eco.isActive)
        XCTAssertTrue(thermostat.capabilities.supportsEco)
        XCTAssertFalse(thermostat.fan.isAvailable)
    }
}
