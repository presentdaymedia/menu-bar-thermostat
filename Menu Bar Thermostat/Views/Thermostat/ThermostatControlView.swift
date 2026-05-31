import SwiftUI
import Combine

struct ThermostatControlView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme
    let thermostat: Thermostat

    @State var thermostatMode: String = "OFF"
    @State var targetCoolSetpoint: Double = 0.0
    @State var targetHeatSetpoint: Double = 0.0
    @State var availableModes: [String] = []
    @State var isLoadingSetpoints: Bool = false
    @State var showCoolEcoLeafIcon: Bool = false
    @State var showHeatEcoLeafIcon: Bool = false
    @State var fanRotationAngle: Double = 0
    @State var rotationTimer: AnyCancellable?
    @State var fanAnimationTickCount: Int = 0
    @State var isRotating: Bool = false {
        didSet {
            if !isRotating {
                fanRotationAngle = 0
            }
        }
    }
    @State var isManualFanOn: Bool = false
    @State var lastDeviceID: String?
    @State var lastUserInteractionTime: Date?

    var body: some View {
        VStack {
            if currentThermostat.ambientTemperatureCelsius != nil {
                CurrentTemperatureHeader(
                    thermostat: currentThermostat,
                    displayTemperature: appState.displayTemperature,
                    temperatureUnit: appState.temperatureUnit
                )
                .padding()
            }

            ZStack {
                VStack {
                    Text("Set to")
                        .foregroundColor(textColor)
                        .padding(5)

                    ThermostatSetpointRow(
                        thermostatMode: thermostatMode,
                        targetHeatSetpoint: targetHeatSetpoint,
                        targetCoolSetpoint: targetCoolSetpoint,
                        showHeatEcoLeafIcon: showHeatEcoLeafIcon,
                        showCoolEcoLeafIcon: showCoolEcoLeafIcon,
                        thermostat: currentThermostat,
                        temperatureUnit: appState.temperatureUnit,
                        isLoadingSetpoints: isLoadingSetpoints,
                        textColor: textColor
                    )

                    SetpointSlider(
                        coolValue: $targetCoolSetpoint,
                        heatValue: thermostatMode == "HEAT" || thermostatMode == "HEATCOOL" ? $targetHeatSetpoint : nil,
                        range: sliderRange,
                        thumbSize: 24,
                        isEnabled: areThermostatControlsEnabled,
                        mode: thermostatMode,
                        hvacStatus: hvacStatus,
                        onDragEnded: { _ in
                            if areThermostatControlsEnabled {
                                lastUserInteractionTime = Date()
                                sendSetpointUpdate()
                                updateEcoSetpointIndicators(with: currentThermostat)
                            }
                        }
                    )
                    .padding()

                    ThermostatModeFanControlRow(
                        thermostatMode: $thermostatMode,
                        availableModes: availablePickerModes,
                        thermostat: currentThermostat,
                        fanRotationAngle: fanRotationAngle,
                        textColor: textColor,
                        isManualFanOn: isManualFanOn,
                        isDeviceInteractive: appState.isDeviceInteractive,
                        onFanToggle: toggleFan
                    )
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                .padding()
                .background(backgroundColor.opacity(backgroundOpacity))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(strokeColor.opacity(strokeOpacity), lineWidth: 2)
                )
            }
        }
        .padding([.bottom, .leading, .trailing])
        .onAppear(perform: handleAppear)
        .onDisappear(perform: stopRotationTimer)
        .onChange(of: appState.isPopoverVisible) { _, isVisible in
            handlePopoverVisibilityChange(isVisible)
        }
        .onChange(of: thermostatMode) { oldValue, newValue in
            handleThermostatModeChange(oldValue: oldValue, newValue: newValue)
        }
        .onChange(of: appState.temperatureUnit) { _, _ in
            handleTemperatureUnitChange()
        }
        .onReceive(appState.$selectedDevice.compactMap { $0?.thermostatSnapshot }) { updatedThermostat in
            handleSelectedThermostatUpdate(updatedThermostat)
        }
    }
}
