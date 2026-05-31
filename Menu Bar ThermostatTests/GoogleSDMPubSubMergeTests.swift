import XCTest

@MainActor
final class GoogleSDMPubSubMergeTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        UserDefaults.standard.removeObject(forKey: AppState.lastNetworkDeviceUpdateKey)
        super.tearDown()
    }

    func testPubSubConnectivityEventUpdatesSelectedDeviceAndHealth() {
        let appState = AppState(testMode: true)
        appState.sdmAccessToken = "test-token"

        let initialDevice = TestFixtures.thermostatDevice(connectivity: "ONLINE")
        appState.selectedDevice = initialDevice
        XCTAssertEqual(appState.selectedDeviceConnectionHealth, .connected)

        let offlineUpdate = TestFixtures.connectivityUpdate(deviceID: initialDevice.id, status: "OFFLINE")
        appState.applyResourceUpdateForTesting(offlineUpdate)

        XCTAssertEqual(appState.selectedDevice?.traits.connectivity?.status, "OFFLINE")
        XCTAssertEqual(appState.selectedDeviceConnectionHealth, .disconnected)
        XCTAssertGreaterThan(UserDefaults.standard.double(forKey: AppState.lastNetworkDeviceUpdateKey), 0)
    }

    func testPubSubEventForNonSelectedDeviceUpdatesDeviceCacheWithoutDisconnectingSelectedDevice() {
        let appState = AppState(testMode: true)
        appState.sdmAccessToken = "test-token"

        let selected = TestFixtures.thermostatDevice(id: "enterprises/test-enterprise/devices/device-1", connectivity: "ONLINE")
        let other = TestFixtures.thermostatDevice(id: "enterprises/test-enterprise/devices/device-2", connectivity: "ONLINE")
        appState.availableThermostats = [selected, other]
        appState.selectedDevice = selected

        let offlineUpdate = TestFixtures.connectivityUpdate(deviceID: other.id, status: "OFFLINE")
        appState.applyResourceUpdateForTesting(offlineUpdate)

        XCTAssertEqual(appState.selectedDevice?.id, selected.id)
        XCTAssertEqual(appState.selectedDevice?.traits.connectivity?.status, "ONLINE")
        XCTAssertEqual(appState.availableThermostats.first(where: { $0.id == other.id })?.traits.connectivity?.status, "OFFLINE")
        XCTAssertEqual(appState.selectedDeviceConnectionHealth, .connected)
    }

    func testPartialHeatSetpointEventPreservesExistingCoolSetpointInMixedMode() {
        let appState = AppState(testMode: true)
        appState.sdmAccessToken = "test-token"

        let device = TestFixtures.thermostatDevice(mode: "HEATCOOL", heatCelsius: 20, coolCelsius: 25)
        appState.availableThermostats = [device]
        appState.selectedDevice = device

        let heatUpdate = TestFixtures.setpointUpdate(deviceID: device.id, heatCelsius: 21)
        appState.applyResourceUpdateForTesting(heatUpdate)

        XCTAssertEqual(appState.selectedDevice?.traits.thermostatTemperatureSetpoint?.heatCelsius, 21)
        XCTAssertEqual(appState.selectedDevice?.traits.thermostatTemperatureSetpoint?.coolCelsius, 25)
    }

    func testPartialCoolSetpointEventPreservesExistingHeatSetpointInMixedMode() {
        let appState = AppState(testMode: true)
        appState.sdmAccessToken = "test-token"

        let device = TestFixtures.thermostatDevice(mode: "HEATCOOL", heatCelsius: 20, coolCelsius: 25)
        appState.availableThermostats = [device]
        appState.selectedDevice = device

        let coolUpdate = TestFixtures.setpointUpdate(deviceID: device.id, coolCelsius: 24)
        appState.applyResourceUpdateForTesting(coolUpdate)

        XCTAssertEqual(appState.selectedDevice?.traits.thermostatTemperatureSetpoint?.heatCelsius, 20)
        XCTAssertEqual(appState.selectedDevice?.traits.thermostatTemperatureSetpoint?.coolCelsius, 24)
    }

    func testEqualTimestampPubSubEventsAllApply() {
        let appState = AppState(testMode: true)
        appState.sdmAccessToken = "test-token"

        let device = TestFixtures.thermostatDevice(connectivity: "OFFLINE", mode: "HEAT", hvacStatus: "HEATING")
        appState.availableThermostats = [device]
        appState.selectedDevice = device
        XCTAssertEqual(appState.selectedDeviceConnectionHealth, .disconnected)

        let timestamp = Date()
        let messages = [
            TestFixtures.pubSubMessage(
                eventID: "connectivity-online",
                deviceID: device.id,
                timestamp: timestamp,
                traits: [
                    "sdm.devices.traits.Connectivity": ["status": "ONLINE"]
                ]
            ),
            TestFixtures.pubSubMessage(
                eventID: "hvac-off",
                deviceID: device.id,
                timestamp: timestamp,
                traits: [
                    "sdm.devices.traits.ThermostatHvac": ["status": "OFF"]
                ]
            )
        ]

        appState.handlePubSubMessagesForTesting(messages)

        XCTAssertEqual(appState.selectedDevice?.traits.connectivity?.status, "ONLINE")
        XCTAssertEqual(appState.selectedDevice?.traits.thermostatHvac?.status, "OFF")
        XCTAssertEqual(appState.selectedDeviceConnectionHealth, .connected)
    }

    func testStalePubSubConnectivityEventDoesNotOverrideFreshSnapshot() {
        let appState = AppState(testMode: true)
        appState.sdmAccessToken = "test-token"

        let device = TestFixtures.thermostatDevice(connectivity: "ONLINE", hvacStatus: "OFF")
        appState.availableThermostats = [device]
        appState.selectedDevice = device

        let snapshotTime = Date()
        appState.recordFullDeviceSnapshot(device, timestamp: snapshotTime.timeIntervalSince1970)

        let staleOfflineUpdate = TestFixtures.connectivityUpdate(deviceID: device.id, status: "OFFLINE")
        appState.applyResourceUpdateForTesting(staleOfflineUpdate, timestamp: snapshotTime.addingTimeInterval(-60))

        XCTAssertEqual(appState.selectedDevice?.traits.connectivity?.status, "ONLINE")
        XCTAssertEqual(appState.selectedDeviceConnectionHealth, .connected)
    }

    func testOutOfOrderHvacEventDoesNotRestoreOldRunningState() {
        let appState = AppState(testMode: true)
        appState.sdmAccessToken = "test-token"

        let device = TestFixtures.thermostatDevice(connectivity: "ONLINE", mode: "HEAT", hvacStatus: "HEATING")
        appState.availableThermostats = [device]
        appState.selectedDevice = device

        let baseTime = Date()
        appState.applyResourceUpdateForTesting(
            TestFixtures.hvacUpdate(deviceID: device.id, status: "OFF"),
            timestamp: baseTime.addingTimeInterval(10)
        )
        appState.applyResourceUpdateForTesting(
            TestFixtures.hvacUpdate(deviceID: device.id, status: "HEATING"),
            timestamp: baseTime.addingTimeInterval(5)
        )

        XCTAssertEqual(appState.selectedDevice?.traits.thermostatHvac?.status, "OFF")
    }

    func testPubSubPollingDoesNotStartWithoutOAuthSession() {
        let appState = AppState(testMode: true)
        let provider = WorkloadIdentityTokenProvider()
        provider.setServiceAccountTokenForTesting("service-token")
        appState.workloadIdentityProvider = provider
        appState.pubSubSubscriptionResourceName = "projects/test/subscriptions/sub-1"

        appState.startPubSubPolling()

        XCTAssertFalse(appState.isPubSubActive)
    }

    func testEnsurePubSubSubscriptionUsesExistingSubscription() async {
        let appState = configuredPubSubAppState()
        var requestedMethods: [String] = []

        MockURLProtocol.requestHandler = { request in
            requestedMethods.append(request.httpMethod ?? "")
            XCTAssertTrue(request.url?.absoluteString.hasSuffix("/projects//subscriptions/test-sub") == true)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, "{}".data(using: .utf8))
        }

        let isReady = await appState.ensurePubSubSubscriptionExists(subscriptionId: "test-sub")

        XCTAssertTrue(isReady)
        XCTAssertEqual(requestedMethods, ["GET"])
        XCTAssertEqual(appState.pubSubSubscriptionResourceName, "projects//subscriptions/test-sub")
    }

    func testEnsurePubSubSubscriptionCreatesMissingSubscription() async throws {
        let appState = configuredPubSubAppState()
        var requestedMethods: [String] = []
        var createPayload: [String: Any]?

        MockURLProtocol.requestHandler = { request in
            requestedMethods.append(request.httpMethod ?? "")

            if request.httpMethod == "GET" {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 404,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, "{\"error\":{\"status\":\"NOT_FOUND\"}}".data(using: .utf8))
            }

            createPayload = try Self.requestJSONPayload(from: request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, "{}".data(using: .utf8))
        }

        let isReady = await appState.ensurePubSubSubscriptionExists(subscriptionId: "test-sub")

        XCTAssertTrue(isReady)
        XCTAssertEqual(requestedMethods, ["GET", "PUT"])
        XCTAssertEqual(createPayload?["topic"] as? String, "projects//topics/")
        XCTAssertEqual(createPayload?["ackDeadlineSeconds"] as? Int, 20)
        XCTAssertEqual(appState.pubSubSubscriptionResourceName, "projects//subscriptions/test-sub")
    }

    func testPullPubSubMessagesUsesInjectedHTTPSession() async {
        let appState = configuredPubSubAppState()
        appState.pubSubSubscriptionResourceName = "projects/test-project/subscriptions/test-sub"
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
            return (response, "{\"receivedMessages\":[]}".data(using: .utf8))
        }

        let success = await appState.pullPubSubMessages()

        XCTAssertTrue(success)
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://pubsub.googleapis.com/v1/projects/test-project/subscriptions/test-sub:pull")
        XCTAssertEqual(capturedPayload?["maxMessages"] as? Int, 50)
    }

    private func configuredPubSubAppState() -> AppState {
        let appState = AppState(testMode: true)
        appState.httpSession = MockURLProtocol.makeSession()
        appState.sdmAccessToken = "sdm-token"
        let provider = WorkloadIdentityTokenProvider()
        provider.setServiceAccountTokenForTesting("service-token")
        appState.workloadIdentityProvider = provider
        return appState
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
        return object as? [String: Any] ?? [:]
    }
}
