import SwiftUI

struct CurrentTemperatureHeader: View {
    let thermostat: Thermostat
    let displayTemperature: Double?
    let temperatureUnit: TemperatureUnit

    var body: some View {
        VStack {
            Text("Currently")
            Text(formattedTemperature)
                .font(.title2)

            if let humidity = thermostat.ambientHumidityPercent {
                Text("\(humidity)% humidity")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var formattedTemperature: String {
        guard let displayTemperature else { return "…" }
        return temperatureUnit.formatted(displayTemperature)
    }
}
