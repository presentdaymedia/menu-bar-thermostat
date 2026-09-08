import Foundation

extension AppState {
    var displayTemperature: Double? {
        guard let tempC = currentTemperatureCelsius else { return nil }
        return temperatureUnit.value(fromCelsius: tempC)
    }

    var selectedThermostat: Thermostat? {
        selectedDevice?.thermostatSnapshot
    }

    var isDeviceInteractive: Bool {
        guard !sdmAccessToken.isEmpty, !authenticationStatus.isRecovering,
              authenticationStatus != .reauthenticationRequired,
              authenticationStatus != .configurationError else { return false }
        guard let selectedDevice else { return false }
        guard selectedDevice.traits.connectivity?.status != "OFFLINE" else { return false }
        if selectedDevice.traits.connectivity?.status == "ONLINE" {
            return true
        }
        return selectedDeviceConnectionHealth != .disconnected
    }

    func updateDisplayedTemperature() {
        if currentTemperatureCelsius != nil {
            objectWillChange.send()
        }
    }

    func updateTemperatureUnitFromDevice() {
        guard let device = selectedDevice,
              let temperatureScale = device.traits.settings?.temperatureScale else { return }

        let deviceUnit: TemperatureUnit = temperatureScale == "CELSIUS" ? .celsius : .fahrenheit
        if temperatureUnit != deviceUnit {
            print("Updating temperature unit to match device setting: \(deviceUnit.rawValue)")
            temperatureUnit = deviceUnit
        }
    }
}
