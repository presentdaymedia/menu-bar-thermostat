import Foundation

extension ThermostatControlView {
    func handleAppear() {
        fetchAvailableModes()
        syncViewStateFromThermostat(currentThermostat)
        initializeSetpointsForMode(thermostat: currentThermostat, mode: currentThermostat.mode.commandValue)
        updateEcoSetpointIndicators(with: currentThermostat)
        isManualFanOn = currentThermostat.fan.isTimerOn
        if appState.isPopoverVisible {
            startRotationTimer()
        }
        lastDeviceID = currentThermostat.id
    }

    func handlePopoverVisibilityChange(_ isVisible: Bool) {
        if isVisible {
            startRotationTimer()
        } else {
            stopRotationTimer()
        }
    }

    func handleThermostatModeChange(oldValue: String, newValue: String) {
        updateEcoSetpointIndicators(with: currentThermostat)

        let reportedMode = currentThermostat.mode.commandValue
        let ecoReported = currentThermostat.eco.isActive

        if ecoReported && newValue == "ECO" {
            return
        }

        if reportedMode == newValue {
            return
        }

        if oldValue != newValue {
            sendModeUpdate()
        }
    }

    func handleTemperatureUnitChange() {
        updateTemperaturesFromThermostat(currentThermostat)
        updateEcoSetpointIndicators(with: currentThermostat)
    }

    func handleSelectedThermostatUpdate(_ updatedThermostat: Thermostat) {
        let deviceMode = updatedThermostat.mode.commandValue
        let previousMode = thermostatMode
        let isNewDevice = updatedThermostat.id != lastDeviceID

        lastDeviceID = updatedThermostat.id

        fetchAvailableModes()
        syncViewStateFromThermostat(updatedThermostat)

        if isNewDevice || previousMode != deviceMode {
            initializeSetpointsForMode(thermostat: updatedThermostat, mode: deviceMode)
        }

        updateEcoSetpointIndicators(with: updatedThermostat)
    }
}
