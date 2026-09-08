import SwiftUI
import GoogleSignIn
import LaunchAtLogin

struct SettingsPopoverView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var workloadIdentityProvider: WorkloadIdentityTokenProvider

    var body: some View {
        VStack {
            Picker("Structure", selection: $appState.selectedStructureID) {
                ForEach(appState.availableStructures, id: \.id) { structure in
                    Text(structure.displayName).tag(structure.id)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .labelsHidden()
            .onChange(of: appState.selectedStructureID) { _, newID in
                if let newStruct = appState.availableStructures.first(where: { $0.id == newID }) {
                    appState.selectedStructure = newStruct
                    appState.selectedDevice = nil
                    appState.selectedDeviceID = ""
                    appState.loadThermostats()
                }
            }

            Picker("Thermostat", selection: $appState.selectedDeviceID) {
                if appState.availableThermostats.isEmpty {
                    Text("No Thermostats").tag("")
                } else {
                    ForEach(appState.availableThermostats, id: \.id) { device in
                        Text(device.displayName).tag(device.id)
                    }
                }
            }
            .pickerStyle(MenuPickerStyle())
            .labelsHidden()
            .padding(.bottom)
            .disabled(appState.availableThermostats.isEmpty)
            .onChange(of: appState.selectedDeviceID) { _, newID in
                if let newDev = appState.availableThermostats.first(where: { $0.id == newID }) {
                    appState.selectedDevice = newDev
                } else if newID.isEmpty {
                    appState.selectedDevice = nil
                }
            }

            if let userInfo = appState.userInfo {
                GoogleUserProfileView(userInfo: userInfo)
            }

            Button("Sign Out") {
                GIDSignIn.sharedInstance.signOut()
                appState.signOut()
            }
            .padding(.bottom)

            Picker("Units", selection: $appState.temperatureUnit) {
                Text("°C").tag(TemperatureUnit.celsius)
                Text("°F").tag(TemperatureUnit.fahrenheit)
            }
            .labelsHidden()
            .frame(width: 100)
            .pickerStyle(.segmented)
            .padding()

            LaunchAtLogin.Toggle("Start at Login")
                .toggleStyle(SwitchToggleStyle())
                .controlSize(.mini)
                .padding(.top)

            Button("Show Connection Log") {
                NSWorkspace.shared.selectFile(AuthenticationDiagnostics.logURL.path, inFileViewerRootedAtPath: "")
            }

            Button("Quit App") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.top)

            Text("© \(String(Calendar.current.component(.year, from: Date()))) Present Day Media, LLC.")
                .font(.caption)
                .foregroundColor(Color.secondary)
                .padding(.top, 8)

            Link("Visit website", destination: URL(string: "https://presentdaymedia.com")!)
                .font(.caption)
        }
        .frame(width: 200)
        .padding()
    }
}
