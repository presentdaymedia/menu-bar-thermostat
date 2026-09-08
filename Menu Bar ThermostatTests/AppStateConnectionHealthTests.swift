import XCTest
import Combine

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

final class AuthenticationRecoveryTests: XCTestCase {
    private var state: AppState!

    override func setUp() {
        super.setUp()
        state = AppState(testMode: true)
        state.authenticationStatus = .restoring
    }

    override func tearDown() {
        state.cleanup()
        state = nil
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    private func drainMainQueue() {
        let done = expectation(description: "authentication completion")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 2)
    }

    func testOfflineStartupKeepsCachedSessionAndRecoversOnRetry() {
        state.sdmAccessToken = "cached"
        state.hasRestorableGoogleSession = true
        state.selectedDevice = TestFixtures.thermostatDevice()
        let selectedID = state.selectedDevice?.id
        var attempts = 0
        state.authenticationRequest = { completion in
            attempts += 1
            if attempts == 1 { completion(.failure(URLError(.notConnectedToInternet))) }
            else { completion(.success(GoogleSessionTokens(accessToken: "renewed", idToken: nil,
                                                           expiration: Date().addingTimeInterval(3600)))) }
        }
        state.refreshTokenIfNeeded(force: true)
        drainMainQueue()
        XCTAssertEqual(state.authenticationStatus, .retrying)
        XCTAssertEqual(state.sdmAccessToken, "cached")
        XCTAssertEqual(state.selectedDevice?.id, selectedID)
        XCTAssertNotNil(state.nextAuthenticationAttempt)
        XCTAssertFalse(state.isDeviceInteractive)
        state.refreshTokenIfNeeded(force: true)
        state.reconnectAfterWake()
        XCTAssertEqual(attempts, 1, "Automatic events must respect the retry backoff")
        state.tokenRefreshTimer?.fire()
        drainMainQueue()
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(state.authenticationStatus, .connected)
        XCTAssertEqual(state.sdmAccessToken, "renewed")
        XCTAssertEqual(state.selectedDevice?.id, selectedID)
        XCTAssertTrue(state.isDeviceInteractive)
        XCTAssertGreaterThan(state.nextAuthenticationAttempt!.timeIntervalSinceNow, 3500)
    }

    func testOnlyExplicitInvalidGrantRequiresReauthentication() {
        let cases: [(Error, AuthenticationStatus)] = [
            (URLError(.timedOut), .retrying),
            (NSError(domain: "com.google.GIDSignIn", code: -2), .retrying),
            (NSError(domain: "com.google.GIDSignIn", code: -4), .retrying),
            (NSError(domain: "org.openid.appauth.oauth_token", code: -10), .reauthenticationRequired)
        ]
        for (error, expected) in cases {
            state.cancelAuthenticationRecovery()
            state.authenticationStatus = .connected
            state.sdmAccessToken = "cached"
            state.hasRestorableGoogleSession = true
            state.authenticationRequest = { $0(.failure(error)) }
            state.refreshTokenIfNeeded(force: true)
            drainMainQueue()
            XCTAssertEqual(state.authenticationStatus, expected)
            XCTAssertEqual(state.sdmAccessToken.isEmpty, expected == .reauthenticationRequired)
        }
        XCTAssertNil(state.tokenRefreshTimer)
    }

    func testNoSavedCredentialsOnFirstLaunchShowsSignInWithoutRetrying() {
        state.authenticationRequest = { $0(.failure(NSError(domain: "com.google.GIDSignIn", code: -4))) }
        state.refreshTokenIfNeeded(force: true)
        drainMainQueue()
        XCTAssertEqual(state.authenticationStatus, .signedOut)
        XCTAssertNil(state.tokenRefreshTimer)
    }

    func testTemporarilyUnavailableKeychainWithoutCachedAccessTokenStillRetriesKnownSession() {
        state.hasRestorableGoogleSession = true
        state.authenticationRequest = { $0(.failure(NSError(domain: "com.google.GIDSignIn", code: -4))) }
        state.refreshTokenIfNeeded(force: true)
        drainMainQueue()
        XCTAssertEqual(state.authenticationStatus, .retrying)
        XCTAssertNotNil(state.tokenRefreshTimer)
    }

    func testLateRefreshCannotSignUserBackInAfterSignOut() {
        var finish: ((Result<GoogleSessionTokens, Error>) -> Void)?
        state.authenticationRequest = { finish = $0 }
        state.refreshTokenIfNeeded(force: true)
        state.signOut()
        finish?(.success(GoogleSessionTokens(accessToken: "obsolete", idToken: nil, expiration: Date().addingTimeInterval(3600))))
        drainMainQueue()
        XCTAssertEqual(state.authenticationStatus, .signedOut)
        XCTAssertTrue(state.sdmAccessToken.isEmpty)
        XCTAssertNil(state.tokenRefreshTimer)
    }

    func testOldFailureCannotClearANewerInteractiveSession() {
        var finish: ((Result<GoogleSessionTokens, Error>) -> Void)?
        state.authenticationRequest = { finish = $0 }
        state.refreshTokenIfNeeded(force: true)
        state.cancelAuthenticationRecovery()
        state.beginAuthenticatedSession(sdmAccessToken: "new-login", idToken: nil, expiration: Date().addingTimeInterval(3600))
        finish?(.failure(NSError(domain: "org.openid.appauth.oauth_token", code: -10)))
        drainMainQueue()
        XCTAssertEqual(state.sdmAccessToken, "new-login")
        XCTAssertEqual(state.authenticationStatus, .connected)
    }

    func testConcurrentWakeAndRefreshShareOneRequest() {
        var attempts = 0
        state.authenticationRequest = { _ in attempts += 1 }
        state.refreshTokenIfNeeded(force: true)
        state.reconnectAfterWake()
        state.refreshTokenIfNeeded(force: true)
        XCTAssertEqual(attempts, 1)
    }

    func testUnchangedTokenDoesNotSuppressRefreshUntilExpiry() {
        let expiry = Date().addingTimeInterval(300)
        state.sdmAccessToken = "unchanged"
        state.authenticationRequest = { $0(.success(GoogleSessionTokens(accessToken: "unchanged", idToken: nil, expiration: expiry))) }
        state.refreshTokenIfNeeded(force: true)
        drainMainQueue()
        let scheduled = state.nextAuthenticationAttempt!
        XCTAssertEqual(scheduled.timeIntervalSince(expiry), -45, accuracy: 1)
        XCTAssertEqual(state.authenticationStatus, .connected)
    }

    func testExpiredTokenSchedulesAsynchronouslyInsteadOfRecursing() {
        XCTAssertEqual(AppState.authenticationRefreshDelay(expiration: Date().addingTimeInterval(-3600)), 1)
        XCTAssertEqual(AppState.authenticationRefreshDelay(expiration: Date().addingTimeInterval(20)), 1)
    }

    func testPermissionDeniedDoesNotRefreshOrClearSession() {
        state.sdmAccessToken = "cached"
        var attempts = 0
        state.authenticationRequest = { _ in attempts += 1 }
        let failure = state.handleOAuthBackedFailure(context: "test", error: .responseValidationFailed(reason: .unacceptableStatusCode(code: 403)),
                                                    statusCode: 403, responseData: Data("{\"error\":{\"status\":\"PERMISSION_DENIED\"}}".utf8))
        XCTAssertEqual(failure, .permissionDenied)
        XCTAssertEqual(attempts, 0)
        XCTAssertEqual(state.sdmAccessToken, "cached")
    }

    func testRetryBackoffIsBoundedAndSuccessResetsIt() {
        state.hasRestorableGoogleSession = true
        state.authenticationRequest = { $0(.failure(URLError(.timedOut))) }
        for delay in [5.0, 10, 20, 40, 60, 60] {
            if state.tokenRefreshTimer == nil { state.refreshTokenIfNeeded(force: true) }
            else { state.tokenRefreshTimer?.fire() }
            drainMainQueue()
            XCTAssertEqual(state.nextAuthenticationAttempt!.timeIntervalSinceNow, delay, accuracy: 1)
        }
        state.authenticationRequest = { $0(.success(GoogleSessionTokens(accessToken: "recovered", idToken: nil,
                                                                        expiration: Date().addingTimeInterval(3600)))) }
        state.tokenRefreshTimer?.fire()
        drainMainQueue()
        XCTAssertEqual(state.authenticationRetryDelay, 5)
        XCTAssertEqual(state.authenticationStatus, .connected)
    }

    func testLogAppendsAndRotatesWithoutStdout() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("authentication.log")
        try AuthenticationDiagnostics.append("test_first_event", to: url)
        try AuthenticationDiagnostics.append("test_second_event", to: url)
        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.contains("test_first_event"))
        XCTAssertTrue(contents.contains("test_second_event"))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try Data(repeating: 65, count: 512 * 1024 + 1).write(to: url)
        try AuthenticationDiagnostics.append("test_after_rotation", to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("authentication.previous.log").path))
        XCTAssertLessThan(try Data(contentsOf: url).count, 1024)
    }

    func testDiagnosticsNeverIncludeErrorDescriptionsBodiesOrCredentials() {
        let underlying = NSError(domain: "org.openid.appauth.oauth_token", code: -10, userInfo: [
            "OIDOAuthErrorResponseErrorKey": ["error": "invalid_grant", "error_description": "secret-token", "access_token": "secret-token"],
            NSLocalizedDescriptionKey: "private@example.com secret-token"
        ])
        let error = NSError(domain: "unknown-secret-domain", code: 123, userInfo: [NSUnderlyingErrorKey: underlying])
        let summary = AuthenticationDiagnostics.safeErrorSummary(error)
        XCTAssertTrue(summary.contains("invalid_grant"))
        XCTAssertTrue(summary.contains("code=-10"))
        XCTAssertFalse(summary.contains("secret"))
        XCTAssertFalse(summary.contains("example.com"))
    }
}

final class WorkloadIdentityRecoveryTests: XCTestCase {
    private func provider() -> WorkloadIdentityTokenProvider {
        WorkloadIdentityTokenProvider(config: AppConfig(deviceAccessEnterpriseID: "test", pubSubGoogleCloudProjectID: "test",
                                                        pubSubTopicID: "test", workloadIdentityAudience: "test-audience",
                                                        pubSubServiceAccountEmail: "service@example.invalid"),
                                      session: MockURLProtocol.makeSession())
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testSTSNetworkFailureSchedulesRetryWithoutDroppingExistingToken() {
        let provider = provider()
        provider.acceptServiceAccountToken("existing", expiresAt: Date().addingTimeInterval(3600))
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        provider.start(idToken: "test-id-token")
        let retried = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in provider.retryDelay == 10 }, object: nil)
        wait(for: [retried], timeout: 2)
        XCTAssertEqual(provider.serviceAccountAccessToken, "existing")
        XCTAssertNotNil(provider.nextRefreshDate)
        provider.reset()
        XCTAssertNil(provider.nextRefreshDate)
    }

    func testIAMPermissionFailureSchedulesRetryAndDoesNotPublishToken() {
        let provider = provider()
        MockURLProtocol.requestHandler = { request in
            let isSTS = request.url?.host == "sts.googleapis.com"
            let data = isSTS ? "{\"access_token\":\"sts-token\",\"expires_in\":3600}" : "{\"error\":{\"status\":\"PERMISSION_DENIED\"}}"
            return (HTTPURLResponse(url: request.url!, statusCode: isSTS ? 200 : 403, httpVersion: nil, headerFields: nil)!, Data(data.utf8))
        }
        provider.start(idToken: "test-id-token")
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in provider.retryDelay == 10 }, object: nil)], timeout: 2)
        XCTAssertTrue(provider.serviceAccountAccessToken.isEmpty)
        XCTAssertNotNil(provider.nextRefreshDate)
        provider.reset()
    }

    func testResetDiscardsAnInFlightExchange() {
        let provider = provider()
        let received = expectation(description: "STS request started")
        let release = DispatchSemaphore(value: 0)
        MockURLProtocol.requestHandler = { request in
            received.fulfill()
            _ = release.wait(timeout: .now() + 2)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data("{\"access_token\":\"old-sts-token\",\"expires_in\":3600}".utf8))
        }
        let staleToken = expectation(description: "no token after reset")
        staleToken.isInverted = true
        let subscription = provider.$serviceAccountAccessToken.sink { if !$0.isEmpty { staleToken.fulfill() } }
        provider.start(idToken: "test-id-token")
        wait(for: [received], timeout: 2)
        provider.reset()
        release.signal()
        wait(for: [staleToken], timeout: 0.2)
        withExtendedLifetime(subscription) {}
        XCTAssertTrue(provider.serviceAccountAccessToken.isEmpty)
        XCTAssertNil(provider.nextRefreshDate)
    }

    func testSuccessfulExchangeParsesFractionalExpiryAndSchedulesRenewal() {
        let provider = provider()
        let expires = Date().addingTimeInterval(3600)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        MockURLProtocol.requestHandler = { request in
            let data = request.url?.host == "sts.googleapis.com"
                ? "{\"access_token\":\"sts-token\",\"expires_in\":3600}"
                : "{\"accessToken\":\"service-token\",\"expireTime\":\"\(formatter.string(from: expires))\"}"
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(data.utf8))
        }
        provider.start(idToken: "test-id-token")
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in provider.serviceAccountAccessToken == "service-token" }, object: nil)], timeout: 2)
        XCTAssertTrue(provider.isTokenValid)
        XCTAssertEqual(provider.nextRefreshDate!.timeIntervalSince(expires), -300, accuracy: 1)
        provider.reset()
    }
}
