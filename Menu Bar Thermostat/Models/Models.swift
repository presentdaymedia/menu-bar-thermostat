import Foundation

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case fahrenheit = "F"
    case celsius = "C"

    var id: String { rawValue }

    func value(fromCelsius celsius: Double) -> Double {
        switch self {
        case .celsius:
            return celsius
        case .fahrenheit:
            return (celsius * 9 / 5) + 32
        }
    }

    func celsius(from value: Double) -> Double {
        switch self {
        case .celsius:
            return value
        case .fahrenheit:
            return (value - 32) * 5 / 9
        }
    }

    func formatted(_ value: Double) -> String {
        String(format: "%.1f°%@", value, rawValue)
    }
}

enum ConnectionHealth: String {
    case unknown
    case connected
    case disconnected
}

enum SetpointThumb {
    case cool
    case heat
}

struct SetpointSliderLogic {
    static func adjustedValues(
        activeThumb: SetpointThumb,
        proposedValue: Double,
        coolValue: Double,
        heatValue: Double?,
        mode: String,
        range: ClosedRange<Double>,
        minSetpointGap: Double
    ) -> (coolValue: Double, heatValue: Double) {
        let proposedValue = clamp(proposedValue, to: range)
        var adjustedCool = coolValue
        var adjustedHeat = heatValue ?? proposedValue

        switch activeThumb {
        case .heat:
            if mode == "HEATCOOL" {
                adjustedHeat = min(proposedValue, coolValue - minSetpointGap)
                adjustedHeat = clamp(adjustedHeat, to: range)
            } else {
                adjustedHeat = proposedValue
            }
        case .cool:
            if mode == "HEATCOOL", let heatValue {
                adjustedCool = max(proposedValue, heatValue + minSetpointGap)
                adjustedCool = clamp(adjustedCool, to: range)
            } else {
                adjustedCool = proposedValue
            }
        }

        return (coolValue: adjustedCool, heatValue: adjustedHeat)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

struct ThermostatSetpointDisplayState: Equatable {
    var coolValue: Double
    var heatValue: Double

    static func initial(
        mode: String,
        setpoints: ThermostatSetpoints?,
        unit: TemperatureUnit,
        defaultHeatCelsius: Double = 21.0,
        defaultCoolCelsius: Double = 24.0
    ) -> ThermostatSetpointDisplayState {
        switch mode {
        case "HEAT":
            if let heatCelsius = setpoints?.heatCelsius {
                return ThermostatSetpointDisplayState(
                    coolValue: 0.0,
                    heatValue: unit.value(fromCelsius: heatCelsius)
                )
            }
            return ThermostatSetpointDisplayState(
                coolValue: 0.0,
                heatValue: unit.value(fromCelsius: defaultHeatCelsius)
            )

        case "COOL":
            if let coolCelsius = setpoints?.coolCelsius {
                return ThermostatSetpointDisplayState(
                    coolValue: unit.value(fromCelsius: coolCelsius),
                    heatValue: 0.0
                )
            }
            return ThermostatSetpointDisplayState(
                coolValue: unit.value(fromCelsius: defaultCoolCelsius),
                heatValue: 0.0
            )

        case "HEATCOOL":
            let heatValue = unit.value(fromCelsius: setpoints?.heatCelsius ?? defaultHeatCelsius)
            let coolValue = unit.value(fromCelsius: setpoints?.coolCelsius ?? defaultCoolCelsius)

            return ThermostatSetpointDisplayState(
                coolValue: coolValue,
                heatValue: heatValue
            )

        default:
            return ThermostatSetpointDisplayState(coolValue: 0.0, heatValue: 0.0)
        }
    }

    static func updating(
        mode: String,
        setpoints: ThermostatSetpoints?,
        unit: TemperatureUnit,
        currentCoolValue: Double,
        currentHeatValue: Double
    ) -> ThermostatSetpointDisplayState {
        switch mode {
        case "HEAT":
            return ThermostatSetpointDisplayState(
                coolValue: 0.0,
                heatValue: setpoints?.heatCelsius.map { unit.value(fromCelsius: $0) } ?? currentHeatValue
            )
        case "COOL":
            return ThermostatSetpointDisplayState(
                coolValue: setpoints?.coolCelsius.map { unit.value(fromCelsius: $0) } ?? currentCoolValue,
                heatValue: 0.0
            )
        case "HEATCOOL":
            return ThermostatSetpointDisplayState(
                coolValue: setpoints?.coolCelsius.map { unit.value(fromCelsius: $0) } ?? currentCoolValue,
                heatValue: setpoints?.heatCelsius.map { unit.value(fromCelsius: $0) } ?? currentHeatValue
            )
        default:
            return ThermostatSetpointDisplayState(
                coolValue: currentCoolValue,
                heatValue: currentHeatValue
            )
        }
    }
}
