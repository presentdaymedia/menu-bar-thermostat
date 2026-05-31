import SwiftUI

extension ThermostatControlView {
    var isAwaitingCommandEcho: Bool {
        guard let lastInteraction = lastUserInteractionTime else { return false }
        return Date().timeIntervalSince(lastInteraction) < 3.0
    }

    var currentThermostat: Thermostat {
        appState.selectedThermostat ?? thermostat
    }

    var hvacStatus: String {
        currentThermostat.hvacState.commandValue
    }

    var isThermostatOn: Bool {
        thermostatMode != "OFF" && thermostatMode != "ECO"
    }

    var areThermostatControlsEnabled: Bool {
        isThermostatOn && appState.isDeviceInteractive
    }

    var sliderRange: ClosedRange<Double> {
        appState.temperatureUnit == .celsius ? 10...32 : 50...90
    }

    var availablePickerModes: [String] {
        var uniqueModes: [String] = []
        var seen = Set<String>()

        func append(_ mode: String) {
            guard !mode.isEmpty, !seen.contains(mode) else { return }
            seen.insert(mode)
            uniqueModes.append(mode)
        }

        availableModes.forEach { append($0) }
        append("OFF")

        if currentThermostat.capabilities.supportsEco || currentThermostat.eco.isActive {
            append("ECO")
        }

        return uniqueModes
    }

    var backgroundColor: Color {
        switch hvacStatus {
        case "COOLING":
            return .blue
        case "HEATING":
            return .red
        default:
            return colorScheme == .dark ? .gray : .white
        }
    }

    var backgroundOpacity: Double {
        switch hvacStatus {
        case "COOLING", "HEATING":
            return 0.66
        default:
            return 0.25
        }
    }

    var strokeColor: Color {
        switch hvacStatus {
        case "COOLING":
            return .blue
        case "HEATING":
            return .red
        default:
            return colorScheme == .dark ? .gray : .white
        }
    }

    var strokeOpacity: Double {
        switch hvacStatus {
        case "COOLING", "HEATING":
            return 1.0
        default:
            return 0.5
        }
    }

    var textColor: Color {
        switch hvacStatus {
        case "COOLING", "HEATING":
            return .white
        default:
            return .primary
        }
    }
}
