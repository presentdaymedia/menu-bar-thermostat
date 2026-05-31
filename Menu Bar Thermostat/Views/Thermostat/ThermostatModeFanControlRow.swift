import SwiftUI

struct ThermostatModeFanControlRow: View {
    @Binding var thermostatMode: String

    let availableModes: [String]
    let thermostat: Thermostat
    let fanRotationAngle: Double
    let textColor: Color
    let isManualFanOn: Bool
    let isDeviceInteractive: Bool
    let onFanToggle: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Picker("", selection: $thermostatMode) {
                ForEach(availableModes, id: \.self) { mode in
                    Text(ThermostatModeDisplay.name(for: mode)).tag(mode)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .labelsHidden()
            .foregroundColor(textColor)
            .disabled(!isDeviceInteractive)

            if thermostat.fan.isAvailable {
                Button(action: onFanToggle) {
                    fanIcon
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!isDeviceInteractive)
            } else {
                fanIcon
            }
        }
    }

    private var fanIcon: some View {
        Image(systemName: isFanVisuallyActive ? "fan.fill" : "fan")
            .font(.system(size: 16))
            .foregroundColor(textColor)
            .rotationEffect(.degrees(fanRotationAngle))
            .padding(.leading)
    }

    private var isFanVisuallyActive: Bool {
        thermostat.hvacState.isRunning || thermostat.fan.isTimerOn || isManualFanOn
    }
}
