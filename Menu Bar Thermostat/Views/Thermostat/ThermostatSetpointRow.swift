import SwiftUI

struct ThermostatSetpointRow: View {
    let thermostatMode: String
    let targetHeatSetpoint: Double
    let targetCoolSetpoint: Double
    let showHeatEcoLeafIcon: Bool
    let showCoolEcoLeafIcon: Bool
    let thermostat: Thermostat
    let temperatureUnit: TemperatureUnit
    let isLoadingSetpoints: Bool
    let textColor: Color

    var body: some View {
        HStack {
            Spacer()

            if thermostatMode == "ECO" {
                ecoSetpointDisplay
            } else if thermostatMode == "HEATCOOL" {
                setpointDisplay(value: targetHeatSetpoint, isEco: showHeatEcoLeafIcon)
                Spacer().frame(width: 20)
                setpointDisplay(value: targetCoolSetpoint, isEco: showCoolEcoLeafIcon)
            } else if thermostatMode == "HEAT" {
                setpointDisplay(value: targetHeatSetpoint, isEco: showHeatEcoLeafIcon)
            } else if thermostatMode == "COOL" {
                setpointDisplay(value: targetCoolSetpoint, isEco: showCoolEcoLeafIcon)
            } else {
                Text(ThermostatModeDisplay.name(for: thermostatMode).uppercased())
                    .font(.title)
                    .foregroundColor(textColor)
            }

            Spacer()
        }
        .frame(width: 250, height: 40)
    }

    private var ecoSetpointDisplay: some View {
        Group {
            if let ecoHeat = thermostat.eco.heatCelsius,
               let ecoCool = thermostat.eco.coolCelsius {
                let displayHeat = temperatureUnit.value(fromCelsius: ecoHeat)
                let displayCool = temperatureUnit.value(fromCelsius: ecoCool)
                setpointDisplay(value: displayHeat, isEco: true)
                Spacer().frame(width: 20)
                setpointDisplay(value: displayCool, isEco: true)
            } else {
                Text("ECO MODE")
                    .font(.title)
                    .foregroundColor(.green)
            }
        }
    }

    private func setpointDisplay(value: Double, isEco: Bool) -> some View {
        ZStack {
            if value == 0.0 || isLoadingSetpoints {
                Text("…")
                    .font(.title)
                    .foregroundColor(textColor)
            } else {
                Text(String(format: "%.1f°", value))
                    .font(.title)
                    .foregroundColor(textColor)
                if isEco {
                    HStack {
                        Spacer()
                        Image(systemName: "leaf.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 16))
                    }
                }
            }
        }
        .frame(width: 110)
    }
}
