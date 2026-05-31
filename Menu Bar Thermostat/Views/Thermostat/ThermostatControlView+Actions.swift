import Foundation

extension ThermostatControlView {
    func fetchAvailableModes() {
        var modes: [String] = []
        modes.append(contentsOf: currentThermostat.capabilities.availableModes.map(\.commandValue))
        availableModes = modes
    }

    func sendSetpointUpdate() {
        guard isThermostatOn else {
            print("Cannot update setpoints: thermostat is in OFF or ECO mode")
            return
        }
        guard let selectedDevice = appState.selectedDevice else { return }

        let targetCoolCelsius = appState.temperatureUnit.celsius(from: targetCoolSetpoint)
        let targetHeatCelsius = appState.temperatureUnit.celsius(from: targetHeatSetpoint)

        switch thermostatMode {
        case "HEAT":
            sendSetpointCommand(deviceID: selectedDevice.id, coolCelsius: nil, heatCelsius: targetHeatCelsius, description: "heat setpoint")
        case "COOL":
            sendSetpointCommand(deviceID: selectedDevice.id, coolCelsius: targetCoolCelsius, heatCelsius: nil, description: "cool setpoint")
        case "HEATCOOL":
            guard targetCoolCelsius > targetHeatCelsius else {
                print("Cannot update setpoints: cool temperature must be greater than heat temperature")
                return
            }
            sendSetpointCommand(deviceID: selectedDevice.id, coolCelsius: targetCoolCelsius, heatCelsius: targetHeatCelsius, description: "range setpoints")
        default:
            break
        }
    }

    func sendSetpointCommand(deviceID: String, coolCelsius: Double?, heatCelsius: Double?, description: String) {
        appState.setThermostatTemperature(deviceID: deviceID, coolCelsius: coolCelsius, heatCelsius: heatCelsius) { success in
            if success {
                print("Successfully set \(description)")
            } else {
                print("Error setting \(description)")
            }
        }
    }

    func sendModeUpdate() {
        guard let selectedDevice = appState.selectedDevice else { return }

        isLoadingSetpoints = ["HEAT", "COOL", "HEATCOOL"].contains(thermostatMode)

        let completion: (Bool) -> Void = { success in
            guard success else {
                DispatchQueue.main.async {
                    self.isLoadingSetpoints = false
                }
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.appState.loadDeviceSnapshot(deviceID: selectedDevice.id) { updatedDevice in
                    DispatchQueue.main.async {
                        self.isLoadingSetpoints = false
                        if let updatedDevice {
                            let updatedThermostat = updatedDevice.thermostatSnapshot
                            self.appState.selectedDevice = updatedDevice
                            self.syncViewStateFromThermostat(updatedThermostat)
                            self.initializeSetpointsForMode(thermostat: updatedThermostat, mode: updatedThermostat.mode.commandValue)
                            self.updateEcoSetpointIndicators(with: updatedThermostat)
                        }
                    }
                }
            }
        }

        if thermostatMode == "ECO" {
            appState.setEcoMode(deviceID: selectedDevice.id, enabled: true, completion: completion)
        } else {
            if currentThermostat.eco.isActive {
                appState.setEcoMode(deviceID: selectedDevice.id, enabled: false) { ecoDisabled in
                    guard ecoDisabled else {
                        completion(false)
                        return
                    }
                    appState.setThermostatMode(deviceID: selectedDevice.id, mode: thermostatMode, completion: completion)
                }
                return
            }
            appState.setThermostatMode(deviceID: selectedDevice.id, mode: thermostatMode, completion: completion)
        }
    }

    func initializeSetpointsForMode(thermostat: Thermostat, mode: String) {
        let state = ThermostatSetpointDisplayState.initial(
            mode: mode,
            setpoints: thermostat.setpoints,
            unit: appState.temperatureUnit
        )

        targetCoolSetpoint = state.coolValue
        targetHeatSetpoint = state.heatValue
    }

    func syncViewStateFromThermostat(_ thermostat: Thermostat) {
        thermostatMode = thermostat.mode.commandValue
        isManualFanOn = thermostat.fan.isTimerOn
        updateTemperaturesFromThermostat(thermostat)
    }

    func updateTemperaturesFromThermostat(_ thermostat: Thermostat) {
        if isAwaitingCommandEcho { return }

        let state = ThermostatSetpointDisplayState.updating(
            mode: thermostatMode,
            setpoints: thermostat.setpoints,
            unit: appState.temperatureUnit,
            currentCoolValue: targetCoolSetpoint,
            currentHeatValue: targetHeatSetpoint
        )

        targetCoolSetpoint = state.coolValue
        targetHeatSetpoint = state.heatValue
    }

    func updateEcoSetpointIndicators(with thermostat: Thermostat) {
        if let ecoCoolCelsius = thermostat.eco.coolCelsius, isThermostatOn {
            let ecoTemp = appState.temperatureUnit.value(fromCelsius: ecoCoolCelsius)
            showCoolEcoLeafIcon = targetCoolSetpoint >= ecoTemp
        } else {
            showCoolEcoLeafIcon = false
        }

        if let ecoHeatCelsius = thermostat.eco.heatCelsius, isThermostatOn {
            let ecoTemp = appState.temperatureUnit.value(fromCelsius: ecoHeatCelsius)
            showHeatEcoLeafIcon = targetHeatSetpoint <= ecoTemp
        } else {
            showHeatEcoLeafIcon = false
        }
    }

    func toggleFan() {
        guard appState.isDeviceInteractive else {
            print("Fan button disabled - device is disconnected")
            return
        }
        if currentThermostat.hvacState.isRunning {
            print("Fan button disabled - HVAC is currently \(hvacStatus)")
            return
        }

        let fanTimerOn = currentThermostat.fan.isTimerOn
        if isManualFanOn || fanTimerOn {
            isManualFanOn = false
            appState.turnOffFan(deviceID: currentThermostat.id) { success in
                if !success {
                    isManualFanOn = fanTimerOn
                }
            }
        } else {
            isManualFanOn = true
            appState.setFanTimer(deviceID: currentThermostat.id, duration: 900) { success in
                if !success {
                    isManualFanOn = fanTimerOn
                }
            }
        }
    }
}
