import Foundation
import Alamofire

extension AppState {
    func setThermostatMode(deviceID: String, mode: String, completion: @escaping (Bool) -> Void) {
        executeDeviceCommand(
            deviceID: deviceID,
            command: "sdm.devices.commands.ThermostatMode.SetMode",
            params: ["mode": mode],
            context: "setThermostatMode",
            successMessage: "Thermostat mode set to \(mode)",
            failureMessage: "Error setting thermostat mode",
            completion: completion
        )
    }

    func setThermostatTemperature(deviceID: String, coolCelsius: Double?, heatCelsius: Double?, completion: @escaping (Bool) -> Void) {
        var params: [String: Any] = [:]
        if let coolCelsius = coolCelsius {
            params["coolCelsius"] = coolCelsius
        }
        if let heatCelsius = heatCelsius {
            params["heatCelsius"] = heatCelsius
        }

        let command: String
        switch (coolCelsius, heatCelsius) {
        case (.some, .some):
            command = "sdm.devices.commands.ThermostatTemperatureSetpoint.SetRange"
        case (.some, .none):
            command = "sdm.devices.commands.ThermostatTemperatureSetpoint.SetCool"
        case (.none, .some):
            command = "sdm.devices.commands.ThermostatTemperatureSetpoint.SetHeat"
        case (.none, .none):
            print("Cannot set thermostat temperature without a heat or cool setpoint")
            completion(false)
            return
        }

        executeDeviceCommand(
            deviceID: deviceID,
            command: command,
            params: params,
            context: "setThermostatTemperature",
            successMessage: "Thermostat temperature set successfully",
            failureMessage: "Error updating thermostat settings",
            completion: completion
        )
    }

    func setEcoMode(deviceID: String, enabled: Bool, completion: @escaping (Bool) -> Void) {
        executeDeviceCommand(
            deviceID: deviceID,
            command: "sdm.devices.commands.ThermostatEco.SetMode",
            params: ["mode": enabled ? "MANUAL_ECO" : "OFF"],
            context: "setEcoMode",
            successMessage: "Eco mode set to \(enabled)",
            failureMessage: "Error setting eco mode",
            completion: completion
        )
    }

    func setEcoTemperature(deviceID: String, coolCelsius: Double?, heatCelsius: Double?, completion: @escaping (Bool) -> Void) {
        var params: [String: Any] = [:]
        if let coolCelsius = coolCelsius {
            params["coolCelsius"] = coolCelsius
        }
        if let heatCelsius = heatCelsius {
            params["heatCelsius"] = heatCelsius
        }
        executeDeviceCommand(
            deviceID: deviceID,
            command: "sdm.devices.commands.ThermostatEco.SetTemperature",
            params: params,
            context: "setEcoTemperature",
            successMessage: "Eco temperature set successfully",
            failureMessage: "Error setting eco temperature",
            completion: completion
        )
    }

    func setFanTimer(deviceID: String, duration: Int = 900, completion: @escaping (Bool) -> Void) {
        print("Setting fan timer for \(duration) seconds")

        executeDeviceCommand(
            deviceID: deviceID,
            command: "sdm.devices.commands.Fan.SetTimer",
            params: [
                "timerMode": "ON",
                "duration": "\(duration)s"
            ],
            context: "setFanTimer",
            successMessage: "Fan timer set successfully",
            failureMessage: "Error setting fan timer",
            completion: completion,
            onFailureResponse: logFanTimerFailure
        )
    }

    func turnOffFan(deviceID: String, completion: @escaping (Bool) -> Void) {
        print("Turning off fan")

        executeDeviceCommand(
            deviceID: deviceID,
            command: "sdm.devices.commands.Fan.SetTimer",
            params: ["timerMode": "OFF"],
            context: "turnOffFan",
            successMessage: "Fan turned off successfully",
            failureMessage: "Error turning off fan",
            completion: completion,
            onFailureResponse: logFanOffFailure
        )
    }

    private func executeDeviceCommand(
        deviceID: String,
        command: String,
        params: [String: Any],
        context: String,
        successMessage: String,
        failureMessage: String,
        completion: @escaping (Bool) -> Void,
        onFailureResponse: ((Int?, Data?) -> Void)? = nil
    ) {
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(sdmAccessToken)",
            "Content-Type": "application/json"
        ]
        let url = "https://smartdevicemanagement.googleapis.com/v1/\(deviceID):executeCommand"
        let parameters: [String: Any] = [
            "command": command,
            "params": params
        ]

        httpSession.request(url, method: .post, parameters: parameters, encoding: JSONEncoding.default, headers: headers)
            .validate()
            .response { response in
            switch response.result {
            case .success:
                print(successMessage)
                self.markConnectionHealthy()
                // Note: immediate fetch removed to prevent race condition with PubSub updates
                completion(true)
            case .failure(let error):
                print("\(failureMessage): \(error.localizedDescription)")
                self.handleCommandFailure(context: context, error: error, statusCode: response.response?.statusCode, responseData: response.data)
                onFailureResponse?(response.response?.statusCode, response.data)
                completion(false)
            }
        }
    }

    private func logFanTimerFailure(statusCode: Int?, responseData: Data?) {
        guard let responseData, let responseString = String(data: responseData, encoding: .utf8) else { return }
        print("Response Data: \(responseString)")
        if responseString.contains("Thermostat fan unavailable") {
            print("API Error: This thermostat does not have fan capability (FAILED_PRECONDITION)")
        } else if responseString.contains("already engaged") || responseString.contains("cannot be overridden") {
            print("API Warning: Fan behavior cannot be overridden - may be controlled by HVAC or schedule")
        } else if responseString.contains("FAILED_PRECONDITION") {
            print("API Error: Fan command failed precondition check")
        } else if statusCode == 200, responseString.trimmingCharacters(in: .whitespacesAndNewlines) == "{}" {
            print("API returned empty object for devices – assuming user has not enabled Device Access")
        }
    }

    private func logFanOffFailure(statusCode: Int?, responseData: Data?) {
        guard let responseData, let responseString = String(data: responseData, encoding: .utf8) else { return }
        print("Response Data: \(responseString)")
        if responseString.contains("Thermostat fan unavailable") {
            print("API Error: This thermostat does not have fan capability (FAILED_PRECONDITION)")
        } else if responseString.contains("cannot be overridden") {
            print("API Warning: Fan behavior cannot be overridden - controlled by HVAC or schedule")
        }
    }
}
