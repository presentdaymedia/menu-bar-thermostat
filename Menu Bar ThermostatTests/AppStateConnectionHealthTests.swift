import XCTest

final class AppStateConnectionHealthTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: AppState.lastNetworkDeviceUpdateKey)
        UserDefaults.standard.removeObject(forKey: "lastDeviceUpdateTime")
        super.tearDown()
    }

    func testConnectionHealthTransitionsWithConnectivity() {
        let appState = AppState(testMode: true)

        XCTAssertEqual(appState.selectedDeviceConnectionHealth, .unknown)

        appState.sdmAccessToken = "test-token"
        appState.selectedDevice = TestFixtures.thermostatDevice(connectivity: "ONLINE")

        XCTAssertEqual(appState.selectedDeviceConnectionHealth, .connected)
        XCTAssertTrue(appState.isDeviceInteractive)

        appState.selectedDevice = TestFixtures.thermostatDevice(connectivity: "OFFLINE")

        XCTAssertEqual(appState.selectedDeviceConnectionHealth, .disconnected)
        XCTAssertFalse(appState.isDeviceInteractive)

        appState.sdmAccessToken = ""

        XCTAssertEqual(appState.selectedDeviceConnectionHealth, .unknown)
        XCTAssertFalse(appState.isDeviceInteractive)
    }

    func testOnlineSelectedDeviceClearsStaleDisconnectedState() {
        let appState = AppState(testMode: true)
        appState.sdmAccessToken = "test-token"

        appState.selectedDevice = TestFixtures.thermostatDevice(connectivity: "OFFLINE")
        XCTAssertEqual(appState.selectedDeviceConnectionHealth, .disconnected)

        appState.selectedDevice = TestFixtures.thermostatDevice(connectivity: "ONLINE")

        XCTAssertEqual(appState.selectedDeviceConnectionHealth, .connected)
        XCTAssertTrue(appState.isDeviceInteractive)
    }

    func testLocalSelectionDoesNotMarkNetworkFreshness() {
        let appState = AppState(testMode: true)
        appState.sdmAccessToken = "test-token"

        appState.selectedDevice = TestFixtures.thermostatDevice(connectivity: "ONLINE")

        XCTAssertEqual(UserDefaults.standard.double(forKey: AppState.lastNetworkDeviceUpdateKey), 0)
    }

    func testSignOutResetsWorkloadIdentityProviderButKeepsListenerAttached() {
        let appState = AppState(testMode: true)
        let provider = WorkloadIdentityTokenProvider()
        provider.setServiceAccountTokenForTesting("service-token")
        appState.workloadIdentityProvider = provider
        appState.sdmAccessToken = "test-token"

        appState.signOut()

        XCTAssertTrue(provider.serviceAccountAccessToken.isEmpty)
        XCTAssertNil(provider.serviceAccountTokenExpiresAt)
        XCTAssertNotNil(appState.workloadIdentityTokenSubscription)
    }
}
