import Foundation
import Alamofire

extension AppState {
    func loadStructures() {
        guard !sdmAccessToken.isEmpty else {
            print("loadStructures: Skipping – no access token.")
            return
        }

        let headers: HTTPHeaders = ["Authorization": "Bearer \(sdmAccessToken)"]
        let url = "https://smartdevicemanagement.googleapis.com/v1/enterprises/\(deviceAccessEnterpriseID)/structures"

        let tokenPreview = redactedToken(sdmAccessToken)
        print("Fetching structures from URL: \(url) with OAuth token \(tokenPreview)")

        httpSession.request(url, headers: headers)
            .validate()
            .responseDecodable(of: StructureListResponse.self) { response in
            switch response.result {
            case .success(let structureListResponse):
                DispatchQueue.main.async {
                    self.cancelStructuresRetry()
                    self.structuresRetryDelay = 5
                    self.availableStructures = structureListResponse.structures
                    // Device Access prompt handling removed (pending relocation)
                    let structureToSelect: Structure?
                    if !self.selectedStructureID.isEmpty,
                       let savedStructure = structureListResponse.structures.first(where: { $0.id == self.selectedStructureID }) {
                        structureToSelect = savedStructure
                        print("AppState: Restored previously selected structure: \(self.selectedStructureID)")
                    } else {
                        structureToSelect = structureListResponse.structures.first
                        print("AppState: No saved structure found, selecting first available structure")
                    }

                    if let structure = structureToSelect {
                        self.selectedStructure = structure
                        self.loadThermostats()
                    }
                }
            case .failure(let error):
                print("Error fetching structures: \(error.localizedDescription) — will retry in \(self.structuresRetryDelay)s")
                let failure = self.handleOAuthBackedFailure(
                    context: "loadStructures",
                    error: error,
                    statusCode: response.response?.statusCode,
                    responseData: response.data
                )
                if let data = response.data, let responseString = String(data: data, encoding: .utf8) {
                    print("Response Data: \(responseString)")
                    if let code = response.response?.statusCode,
                       (code == 403 || code == 404),
                       responseString.localizedCaseInsensitiveContains("PERMISSION_DENIED") ||
                       responseString.localizedCaseInsensitiveContains("permission denied") {
                        // Device Access prompt handling removed (pending relocation)
                    } else if let code = response.response?.statusCode, code == 200, responseString.trimmingCharacters(in: .whitespacesAndNewlines) == "{}" {
                        print("API returned empty object – assuming user has not enabled Device Access")
                        // Device Access prompt handling removed (pending relocation)
                    }
                }
                guard failure != .authentication else { return }
                let delay = self.structuresRetryDelay
                self.structuresRetryDelay = min(self.structuresRetryDelay * 2, 60)
                DispatchQueue.main.async {
                    self.scheduleStructuresRetry(after: delay)
                }
            }
        }
    }

    func loadThermostats(completion: (() -> Void)? = nil) {
        guard !sdmAccessToken.isEmpty else {
            print("loadThermostats: Skipping – no access token.")
            completion?()
            return
        }

        let headers: HTTPHeaders = ["Authorization": "Bearer \(sdmAccessToken)"]
        let url = "https://smartdevicemanagement.googleapis.com/v1/enterprises/\(deviceAccessEnterpriseID)/devices"

        let tokenPreview = redactedToken(sdmAccessToken)
        print("Fetching devices from URL: \(url) with OAuth token \(tokenPreview)")

        httpSession.request(url, headers: headers)
            .validate()
            .responseDecodable(of: GoogleSDMDeviceListResponse.self) { response in
            switch response.result {
            case .success(let deviceListResponse):
                DispatchQueue.main.async {
                    self.cancelDevicesRetry()
                    self.devicesRetryDelay = 5
                    let thermostatDevices = deviceListResponse.devices.filter { $0.type == "sdm.devices.types.THERMOSTAT" }
                    let activeStructureID = self.selectedStructure?.id
                    let filteredDevices: [GoogleSDMThermostatDevice]

                    if let structureID = activeStructureID, !structureID.isEmpty {
                        filteredDevices = thermostatDevices.filter { $0.belongsToStructure(structureID) }
                    } else {
                        filteredDevices = thermostatDevices
                    }

                    if filteredDevices.isEmpty {
                        if thermostatDevices.isEmpty {
                            print("No thermostat devices found in the response")
                            self.availableThermostats = []
                            self.selectedDevice = nil
                            self.selectedDeviceID = ""
                            self.stopDevicePolling()
                            self.markConnectionUnhealthy()
                            completion?()
                            return
                        }

                        if let structureID = activeStructureID {
                            print("No thermostat devices matched structure \(structureID); falling back to unfiltered list")
                        } else {
                            print("No thermostat devices available after filtering")
                        }

                        // Fall back to the full thermostat list so the UI can still function.
                        self.availableThermostats = thermostatDevices
                    } else {
                        self.availableThermostats = filteredDevices
                    }

                    self.recordFullDeviceSnapshots(self.availableThermostats)

                    let deviceToSelect: GoogleSDMThermostatDevice?
                    if !self.selectedDeviceID.isEmpty,
                       let savedDevice = self.availableThermostats.first(where: { $0.id == self.selectedDeviceID }) {
                        deviceToSelect = savedDevice
                        print("AppState: Restored previously selected device: \(self.selectedDeviceID)")
                    } else {
                        deviceToSelect = self.availableThermostats.first
                        print("AppState: No saved device found, selecting first available device")
                    }

                    if let device = deviceToSelect {
                        self.selectedDevice = device
                        if let ambientTemperatureCelsius = device.traits.temperature?.ambientTemperatureCelsius {
                            self.currentTemperatureCelsius = ambientTemperatureCelsius
                        }
                        self.updateTemperatureUnitFromDevice()
                        self.scheduleDevicePolling()
                    }
                    completion?()
                }
            case .failure(let error):
                print("Error fetching devices: \(error.localizedDescription) — will retry in \(self.devicesRetryDelay)s")
                let failure = self.handleOAuthBackedFailure(
                    context: "loadThermostats",
                    error: error,
                    statusCode: response.response?.statusCode,
                    responseData: response.data
                )
                if failure == .networkOrServerFailure || failure == .explicitOffline {
                    self.markConnectionUnhealthy()
                }
                guard failure != .authentication else {
                    DispatchQueue.main.async {
                        completion?()
                    }
                    return
                }
                let delay = self.devicesRetryDelay
                self.devicesRetryDelay = min(self.devicesRetryDelay * 2, 60)
                DispatchQueue.main.async {
                    self.scheduleDevicesRetry(after: delay)
                    completion?()
                }
            }
        }
    }

    func loadDeviceSnapshot(deviceID: String, completion: @escaping (GoogleSDMThermostatDevice?) -> Void) {
        let headers: HTTPHeaders = ["Authorization": "Bearer \(sdmAccessToken)"]
        let url = "https://smartdevicemanagement.googleapis.com/v1/\(deviceID)"

        httpSession.request(url, headers: headers)
            .validate()
            .responseDecodable(of: GoogleSDMThermostatDevice.self) { response in
            switch response.result {
            case .success(let device):
                DispatchQueue.main.async {
                    let previousHVAC = self.selectedDevice?.traits.thermostatHvac?.status ?? "<nil>"
                    let newHVAC = device.traits.thermostatHvac?.status ?? "<nil>"
                    print("GoogleSDMThermostatDevice state poll hvac: \(previousHVAC) → \(newHVAC)")

                    self.recordFullDeviceSnapshot(device)

                    if let currentThermostat = self.selectedDevice, !currentThermostat.hasSameState(as: device) {
                        let hvacStatus = device.traits.thermostatHvac?.status ?? "UNKNOWN"
                        print("GoogleSDMThermostatDevice state update: State differs (HVAC=\(hvacStatus)), applying update.")
                        self.selectedDevice = device
                        if let ambientTemperatureCelsius = device.traits.temperature?.ambientTemperatureCelsius {
                            self.currentTemperatureCelsius = ambientTemperatureCelsius
                            self.updateDisplayedTemperature()
                        }
                        self.updateTemperatureUnitFromDevice()
                    } else {
                        let hvacStatus = device.traits.thermostatHvac?.status ?? "UNKNOWN"
                        print("GoogleSDMThermostatDevice state update: State unchanged (HVAC=\(hvacStatus)), skipping assignment but calling completion.")
                    }
                    if device.traits.connectivity?.status == "OFFLINE" {
                        self.markConnectionUnhealthy()
                    } else {
                        self.markConnectionHealthy()
                    }
                    self.pollManager.recordSuccess()
                    completion(device)
                }
            case .failure(let error):
                print("Error fetching device state: \(error.localizedDescription)")
                let failure = self.handleOAuthBackedFailure(
                    context: "loadDeviceSnapshot",
                    error: error,
                    statusCode: response.response?.statusCode,
                    responseData: response.data
                )
                if failure == .networkOrServerFailure || failure == .explicitOffline {
                    self.markConnectionUnhealthy()
                }
                completion(nil)
            }
        }
    }

    func primeDeviceAccessEvents() {
        guard !sdmAccessToken.isEmpty else {
            print("primeDeviceAccessEvents: Skipping bootstrap – no OAuth token available")
            return
        }

        let headers: HTTPHeaders = ["Authorization": "Bearer \(sdmAccessToken)"]
        let url = "https://smartdevicemanagement.googleapis.com/v1/enterprises/\(deviceAccessEnterpriseID)/devices"
        print("Initiating events with devices.list API call")

        httpSession.request(url, headers: headers)
            .validate()
            .response { response in
                switch response.result {
                case .success:
                    print("Initiate events call succeeded – Pub/Sub should begin streaming updates")
                case .failure(let error):
                    print("Initiate events call failed: \(error.localizedDescription)")
                    if let data = response.data,
                       let responseString = String(data: data, encoding: .utf8) {
                        print("Initiate events response: \(responseString)")
                    }
                }
            }
    }
}
