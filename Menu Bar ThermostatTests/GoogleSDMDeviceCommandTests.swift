import XCTest

final class GoogleSDMDeviceCommandTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        UserDefaults.standard.removeObject(forKey: AppState.lastNetworkDeviceUpdateKey)
        super.tearDown()
    }

    func testSetTemperatureFailsOnUnauthorizedResponseWithoutMarkingDisconnected() {
        let appState = AppState(testMode: true)
        appState.httpSession = MockURLProtocol.makeSession()
        appState.sdmAccessToken = "test-token"
        appState.selectedDevice = TestFixtures.thermostatDevice()

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = "{\"error\":{\"code\":401,\"status\":\"UNAUTHENTICATED\"}}".data(using: .utf8)
            return (response, data)
        }

        let completion = expectation(description: "setpoint completion")

        appState.setThermostatTemperature(
            deviceID: appState.selectedDevice!.id,
            coolCelsius: nil,
            heatCelsius: 21.0
        ) { success in
            XCTAssertFalse(success)
            completion.fulfill()
        }

        wait(for: [completion], timeout: 2.0)
        XCTAssertEqual(appState.selectedDeviceConnectionHealth, .connected)
    }

    func testRejectedCommandDoesNotMarkDeviceDisconnected() {
        let appState = AppState(testMode: true)
        appState.httpSession = MockURLProtocol.makeSession()
        appState.sdmAccessToken = "test-token"
        appState.selectedDevice = TestFixtures.thermostatDevice()

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let data = "{\"error\":{\"code\":400,\"status\":\"FAILED_PRECONDITION\",\"message\":\"Thermostat fan unavailable\"}}".data(using: .utf8)
            return (response, data)
        }

        let completion = expectation(description: "fan command completion")

        appState.setFanTimer(deviceID: appState.selectedDevice!.id) { success in
            XCTAssertFalse(success)
            completion.fulfill()
        }

        wait(for: [completion], timeout: 2.0)
        XCTAssertEqual(appState.selectedDeviceConnectionHealth, .connected)
    }

    func testSetTemperatureUsesHeatCoolAndRangeCommandsForSetpointShape() {
        assertTemperatureCommand(
            coolCelsius: nil,
            heatCelsius: 21,
            expectedCommand: "sdm.devices.commands.ThermostatTemperatureSetpoint.SetHeat",
            expectedParams: ["heatCelsius": 21]
        )

        assertTemperatureCommand(
            coolCelsius: 24,
            heatCelsius: nil,
            expectedCommand: "sdm.devices.commands.ThermostatTemperatureSetpoint.SetCool",
            expectedParams: ["coolCelsius": 24]
        )

        assertTemperatureCommand(
            coolCelsius: 24,
            heatCelsius: 21,
            expectedCommand: "sdm.devices.commands.ThermostatTemperatureSetpoint.SetRange",
            expectedParams: ["coolCelsius": 24, "heatCelsius": 21]
        )
    }

    func testEcoCommandsUseExpectedPayloads() {
        assertDeviceCommand(
            expectedCommand: "sdm.devices.commands.ThermostatEco.SetMode",
            expectedParams: ["mode": "MANUAL_ECO"]
        ) { appState, completion in
            appState.setEcoMode(deviceID: TestFixtures.thermostatDevice().id, enabled: true, completion: completion)
        }

        assertDeviceCommand(
            expectedCommand: "sdm.devices.commands.ThermostatEco.SetMode",
            expectedParams: ["mode": "OFF"]
        ) { appState, completion in
            appState.setEcoMode(deviceID: TestFixtures.thermostatDevice().id, enabled: false, completion: completion)
        }

        assertDeviceCommand(
            expectedCommand: "sdm.devices.commands.ThermostatEco.SetTemperature",
            expectedParams: ["coolCelsius": 24.0, "heatCelsius": 18.0]
        ) { appState, completion in
            appState.setEcoTemperature(
                deviceID: TestFixtures.thermostatDevice().id,
                coolCelsius: 24,
                heatCelsius: 18,
                completion: completion
            )
        }
    }

    func testFanCommandsUseExpectedPayloads() {
        assertDeviceCommand(
            expectedCommand: "sdm.devices.commands.Fan.SetTimer",
            expectedParams: ["timerMode": "ON", "duration": "900s"]
        ) { appState, completion in
            appState.setFanTimer(deviceID: TestFixtures.thermostatDevice().id, duration: 900, completion: completion)
        }

        assertDeviceCommand(
            expectedCommand: "sdm.devices.commands.Fan.SetTimer",
            expectedParams: ["timerMode": "OFF"]
        ) { appState, completion in
            appState.turnOffFan(deviceID: TestFixtures.thermostatDevice().id, completion: completion)
        }
    }

    func testSetTemperatureRejectsEmptySetpointCommand() {
        let appState = AppState(testMode: true)
        appState.httpSession = MockURLProtocol.makeSession()
        appState.sdmAccessToken = "test-token"
        var didRequest = false

        MockURLProtocol.requestHandler = { request in
            didRequest = true
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data())
        }

        let completion = expectation(description: "temperature command rejected")
        appState.setThermostatTemperature(
            deviceID: TestFixtures.thermostatDevice().id,
            coolCelsius: nil,
            heatCelsius: nil
        ) { success in
            XCTAssertFalse(success)
            completion.fulfill()
        }

        wait(for: [completion], timeout: 2.0)
        XCTAssertFalse(didRequest)
    }

    private func assertTemperatureCommand(
        coolCelsius: Double?,
        heatCelsius: Double?,
        expectedCommand: String,
        expectedParams: [String: Double],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let appState = AppState(testMode: true)
        appState.httpSession = MockURLProtocol.makeSession()
        appState.sdmAccessToken = "test-token"

        var capturedPayload: [String: Any]?

        MockURLProtocol.requestHandler = { request in
            capturedPayload = try Self.requestJSONPayload(from: request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data())
        }

        let completion = expectation(description: "temperature command completion")

        appState.setThermostatTemperature(
            deviceID: TestFixtures.thermostatDevice().id,
            coolCelsius: coolCelsius,
            heatCelsius: heatCelsius
        ) { success in
            XCTAssertTrue(success, file: file, line: line)
            completion.fulfill()
        }

        wait(for: [completion], timeout: 2.0)

        XCTAssertEqual(capturedPayload?["command"] as? String, expectedCommand, file: file, line: line)
        let params = capturedPayload?["params"] as? [String: Any]
        XCTAssertEqual(params?.count, expectedParams.count, file: file, line: line)

        for (key, expectedValue) in expectedParams {
            XCTAssertEqual(params?[key] as? Double, expectedValue, file: file, line: line)
        }
    }

    private func assertDeviceCommand(
        expectedCommand: String,
        expectedParams: [String: Any],
        file: StaticString = #filePath,
        line: UInt = #line,
        perform: (AppState, @escaping (Bool) -> Void) -> Void
    ) {
        let appState = AppState(testMode: true)
        appState.httpSession = MockURLProtocol.makeSession()
        appState.sdmAccessToken = "test-token"

        var capturedPayload: [String: Any]?
        var capturedRequest: URLRequest?

        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            capturedPayload = try Self.requestJSONPayload(from: request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data())
        }

        let completion = expectation(description: "device command completion")
        perform(appState) { success in
            XCTAssertTrue(success, file: file, line: line)
            completion.fulfill()
        }

        wait(for: [completion], timeout: 2.0)

        XCTAssertEqual(capturedRequest?.httpMethod, "POST", file: file, line: line)
        XCTAssertTrue(capturedRequest?.url?.absoluteString.hasSuffix(":executeCommand") == true, file: file, line: line)
        XCTAssertEqual(capturedPayload?["command"] as? String, expectedCommand, file: file, line: line)

        let params = capturedPayload?["params"] as? [String: Any]
        XCTAssertEqual(params?.count, expectedParams.count, file: file, line: line)
        for (key, expectedValue) in expectedParams {
            switch expectedValue {
            case let expectedString as String:
                XCTAssertEqual(params?[key] as? String, expectedString, file: file, line: line)
            case let expectedDouble as Double:
                XCTAssertEqual(params?[key] as? Double, expectedDouble, file: file, line: line)
            default:
                XCTFail("Unsupported expected param type for \(key)", file: file, line: line)
            }
        }
    }

    private static func requestJSONPayload(from request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let httpBody = request.httpBody {
            data = httpBody
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            var bytes = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count > 0 {
                    bytes.append(buffer, count: count)
                } else {
                    break
                }
            }
            data = bytes
        } else {
            data = Data()
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let payload = object as? [String: Any] else {
            return [:]
        }
        return payload
    }
}
