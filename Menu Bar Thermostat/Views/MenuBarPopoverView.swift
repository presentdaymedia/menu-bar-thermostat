import SwiftUI
import GoogleSignIn
import LaunchAtLogin

struct MenuBarPopoverView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var workloadIdentityProvider: WorkloadIdentityTokenProvider
    @State private var showConfigurePopup = false

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
    }

    private var header: some View {
        HStack {
            if appState.sdmAccessToken.isEmpty {
                signedOutView
            } else {
                authenticatedHeader
            }
        }
        .padding([.top, .leading, .trailing])
    }

    @ViewBuilder
    private var content: some View {
        if appState.sdmAccessToken.isEmpty {
            EmptyView()
        } else if let thermostat = appState.selectedThermostat {
            ThermostatControlView(thermostat: thermostat)
                .onAppear {
                    if let ambientTemperatureCelsius = thermostat.ambientTemperatureCelsius {
                        appState.currentTemperatureCelsius = ambientTemperatureCelsius
                        appState.updateDisplayedTemperature()
                    }
                }
        } else {
            fetchingDevicesView
                .onAppear {
                    appState.loadThermostats()
                }
        }
    }

    private var signedOutView: some View {
        VStack {
            AppTitleView()
                .padding(.bottom)
                .padding(.top, 8)
            GoogleSignInView()
            Button("Quit App") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.bottom)
        }
    }

    private var authenticatedHeader: some View {
        HStack {
            Circle()
                .fill(connectivityColor)
                .frame(width: 6, height: 6)
            Text(thermostatTitle)
            Spacer()
            if appState.selectedDevice != nil {
                configureButton
            }
        }
    }

    private var configureButton: some View {
        Button {
            showConfigurePopup.toggle()
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 16))
                .foregroundColor(Color.primary)
        }
        .buttonStyle(PlainButtonStyle())
        .popover(isPresented: $showConfigurePopup) {
            SettingsPopoverView()
                .environmentObject(appState)
                .environmentObject(workloadIdentityProvider)
        }
    }

    private var fetchingDevicesView: some View {
        VStack {
            Text("Fetching devices...")
                .padding()
            Button("Stop Fetching") {
                GIDSignIn.sharedInstance.signOut()
                appState.signOut()
            }
            Button("Quit App") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.bottom)
        }
    }
}

private extension MenuBarPopoverView {
    var thermostatTitle: String {
        if let device = appState.selectedDevice {
            return device.displayName
        }

        if !appState.availableThermostats.isEmpty {
            return "Select Thermostat"
        }

        return appState.sdmAccessToken.isEmpty ? "" : "Loading…"
    }

    var connectivityColor: Color {
        if appState.selectedDeviceConnectionHealth == .disconnected {
            return Color.red
        }
        guard let connectionState = appState.selectedThermostat?.connectionState else {
            return appState.sdmAccessToken.isEmpty ? Color.clear : Color.gray.opacity(0.6)
        }
        return connectionState == .online ? Color.green : Color.red
    }
}
