import XCTest

final class GoogleSDMDeviceLoadingTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        UserDefaults.standard.removeObject(forKey: AppState.lastNetworkDeviceUpdateKey)
        super.tearDown()
    }

    func testSuccessfulUnchangedDeviceFetchClearsDisconnectedState() {
        let appState = AppState(testMode: true)
        appState.httpSession = MockURLProtocol.makeSession()
        appState.sdmAccessToken = "test-token"
        appState.isPubSubActive = true
        appState.pubSubSubscriptionResourceName = "projects/test/subscriptions/sub-1"
        let device = TestFixtures.thermostatDevice(connectivity: "ONLINE")
        appState.selectedDevice = device
        appState.markConnectionUnhealthy()

        MockURLProtocol.requestHandler = { request in
            let response = Self.response(for: request, statusCode: 200)
            let data = TestFixtures.deviceListResponse(devices: [device])
            let object = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
            let devices = object["devices"] as! [[String: Any]]
            return (response, try! JSONSerialization.data(withJSONObject: devices[0]))
        }

        let completion = expectation(description: "device state fetch")
        appState.loadDeviceSnapshot(deviceID: device.id) { updatedDevice in
            XCTAssertNotNil(updatedDevice)
            completion.fulfill()
        }

        wait(for: [completion], timeout: 2.0)
        XCTAssertEqual(appState.selectedDeviceConnectionHealth, .connected)
        XCTAssertGreaterThan(UserDefaults.standard.double(forKey: AppState.lastNetworkDeviceUpdateKey), 0)
    }

    func testFetchDevicesDoesNotAdvancePubSubEventCurrency() {
        let appState = AppState(testMode: true)
        appState.httpSession = MockURLProtocol.makeSession()
        appState.sdmAccessToken = "test-token"
        appState.isPubSubActive = true
        appState.pubSubSubscriptionResourceName = "projects/test/subscriptions/sub-1"
        let device = TestFixtures.thermostatDevice(connectivity: "ONLINE")

        MockURLProtocol.requestHandler = { request in
            (Self.response(for: request, statusCode: 200), TestFixtures.deviceListResponse(devices: [device]))
        }

        let completion = expectation(description: "devices fetched")
        appState.loadThermostats {
            completion.fulfill()
        }

        wait(for: [completion], timeout: 2.0)
        XCTAssertEqual(appState.lastProcessedPubSubEventTime, Date.distantPast)
    }

    func testFetchDevicesAuthFailureDoesNotMarkDisconnected() {
        let appState = AppState(testMode: true)
        appState.httpSession = MockURLProtocol.makeSession()
        appState.sdmAccessToken = "test-token"
        appState.selectedDevice = TestFixtures.thermostatDevice()

        MockURLProtocol.requestHandler = { request in
            let data = "{\"error\":{\"code\":401,\"status\":\"UNAUTHENTICATED\"}}".data(using: .utf8)
            return (Self.response(for: request, statusCode: 401), data)
        }

        let completion = expectation(description: "fetch failure handled")
        appState.loadThermostats {
            completion.fulfill()
        }

        wait(for: [completion], timeout: 2.0)
        XCTAssertEqual(appState.selectedDeviceConnectionHealth, .connected)
    }

    private static func response(for request: URLRequest, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }
}
