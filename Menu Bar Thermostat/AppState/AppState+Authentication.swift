import Foundation
import Combine
import AppKit
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

private enum AuthStorageKeys {
    static let sdmAccessTokenExpiration = "sdmAccessTokenExpirationDate"
}

enum AuthenticationStatus {
    case signedOut, restoring, connected, retrying, reauthenticationRequired, configurationError

    var message: String? {
        switch self {
        case .restoring: return "Restoring your Google connection…"
        case .retrying: return "Reconnecting to Google automatically. Your saved sign-in is being kept."
        case .reauthenticationRequired: return "Google authorization expired or was revoked. Please sign in again."
        case .configurationError: return "Google Sign-In configuration needs attention. See the connection log."
        default: return nil
        }
    }

    var isRecovering: Bool { self == .restoring || self == .retrying }
}

struct GoogleSessionTokens {
    let accessToken: String
    let idToken: String?
    let expiration: Date?
}

enum GoogleSessionError: Error {
    case missingCredentials, configuration

    enum Disposition { case revoked, missingCredentials, configuration, transient }

    static func disposition(of error: Error) -> Disposition {
        if let local = error as? GoogleSessionError {
            return local == .configuration ? .configuration : .missingCredentials
        }
        var current = error as NSError
        for _ in 0..<6 {
            if current.domain == "org.openid.appauth.oauth_token" {
                let response = current.userInfo["OIDOAuthErrorResponseErrorKey"] as? [String: Any]
                if current.code == -10 || response?["error"] as? String == "invalid_grant" { return .revoked }
                if let reason = response?["error"] as? String,
                   ["invalid_client", "unauthorized_client", "invalid_scope"].contains(reason) { return .configuration }
            }
            if current.domain == "com.google.GIDSignIn", current.code == -4 { return .missingCredentials }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
            current = underlying
        }
        return .transient
    }
}

extension AppState {
    func configureGoogleSignInIfNeeded() {
#if canImport(GoogleSignIn)
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: "CLIENT_ID") as? String,
              !clientID.isEmpty,
              !clientID.hasPrefix("$(") else {
            print("AppState: CLIENT_ID missing from Info.plist/build settings – unable to restore previous Google Sign-In session.")
            return
        }

        if let existingConfig = GIDSignIn.sharedInstance.configuration,
           existingConfig.clientID == clientID {
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID, serverClientID: clientID)
#else
        print("configureGoogleSignInIfNeeded: GoogleSignIn is unavailable in this build.")
#endif
    }

    /// All startup, wake, API and WIF requests share one refresh operation and retry timer.
    func refreshTokenIfNeeded(force: Bool = false) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.refreshTokenIfNeeded(force: force) }
            return
        }
        guard !isRefreshingToken else { return }
        guard authenticationStatus != .reauthenticationRequired,
              authenticationStatus != .configurationError else { return }
        guard authenticationStatus != .signedOut || !sdmAccessToken.isEmpty else { return }
        let now = Date()
        // Automatic callers must not bypass a transient-failure backoff, even on HTTP 401.
        if authenticationStatus == .retrying, let nextAuthenticationAttempt, nextAuthenticationAttempt > now { return }
        if force, let lastAuthenticationAttempt, now.timeIntervalSince(lastAuthenticationAttempt) < 5 {
            scheduleAuthenticationAttempt(after: 5 - now.timeIntervalSince(lastAuthenticationAttempt))
            return
        }
        tokenRefreshTimer?.invalidate()
        tokenRefreshTimer = nil
        nextAuthenticationAttempt = nil
        isRefreshingToken = true
        lastAuthenticationAttempt = now
        let attempt = UUID()
        authenticationAttemptID = attempt
        AuthenticationDiagnostics.record("google_refresh_started")
        let completion: (Result<GoogleSessionTokens, Error>) -> Void = { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.authenticationAttemptID == attempt else { return }
                self.isRefreshingToken = false
                self.isRestoringSession = false
                switch result {
                case .success(let tokens):
                    guard !tokens.accessToken.isEmpty else {
                        self.handleAuthenticationFailure(GoogleSessionError.missingCredentials)
                        return
                    }
                    self.authenticationStatus = .connected
                    self.authenticationRetryDelay = 5
                    self.hasRestorableGoogleSession = true
                    if !self.isTestMode {
                        UserDefaults.standard.set(true, forKey: "hasAuthorizedGoogleSession")
                    }
                    AuthenticationDiagnostics.record("google_refresh_succeeded")
                    if self.userInfo == nil || self.selectedDevice == nil {
                        self.hasStartedSessionBootstrap = false
                    }
                    self.beginAuthenticatedSession(sdmAccessToken: tokens.accessToken,
                                                   idToken: tokens.idToken,
                                                   expiration: tokens.expiration)
                    if !self.isTestMode {
                        self.startSessionBootstrapIfNeeded()
                        self.scheduleDevicePolling()
                    }
                case .failure(let error):
                    self.handleAuthenticationFailure(error)
                }
            }
        }
        if let authenticationRequest {
            authenticationRequest(completion)
            return
        }
#if canImport(GoogleSignIn)
        configureGoogleSignInIfNeeded()
        guard GIDSignIn.sharedInstance.configuration != nil else {
            completion(.failure(GoogleSessionError.configuration))
            return
        }
        let receive: (GIDGoogleUser?, Error?) -> Void = { user, error in
            if let error { completion(.failure(error)) }
            else if let user {
                completion(.success(GoogleSessionTokens(accessToken: user.accessToken.tokenString,
                                                       idToken: user.idToken?.tokenString,
                                                       expiration: user.accessToken.expirationDate)))
            } else { completion(.failure(GoogleSessionError.missingCredentials)) }
        }
        if let user = GIDSignIn.sharedInstance.currentUser {
            // Preserve the original refresh error, especially invalid_grant. Restore's fallback
            // can otherwise replace it with a less informative Keychain error.
            user.refreshTokensIfNeeded(completion: receive)
        } else {
            GIDSignIn.sharedInstance.restorePreviousSignIn(completion: receive)
        }
#else
        // Test targets inject the request above and never access Google or the user's Keychain.
        isRefreshingToken = false
#endif
    }

    func handleAuthenticationFailure(_ error: Error) {
        AuthenticationDiagnostics.record("google_refresh_failed", error: error)
        switch GoogleSessionError.disposition(of: error) {
        case .revoked:
            if !isTestMode { UserDefaults.standard.set(true, forKey: "googleReauthenticationRequired") }
            clearStoredAuthentication()
            authenticationStatus = .reauthenticationRequired
        case .configuration:
            authenticationStatus = .configurationError
            tokenRefreshTimer?.invalidate()
            tokenRefreshTimer = nil
        case .missingCredentials where !hasRestorableGoogleSession && sdmAccessToken.isEmpty:
            authenticationStatus = .signedOut
        default:
            // A failed Keychain read is not proof that the saved Google grant was revoked.
            authenticationStatus = .retrying
            stopDevicePolling()
            stopPubSubPolling(shouldRestartPolling: false)
            let delay = authenticationRetryDelay
            authenticationRetryDelay = min(delay * 2, 60)
            scheduleAuthenticationAttempt(after: delay)
        }
    }

    static func authenticationRefreshDelay(expiration: Date?, now: Date = Date()) -> TimeInterval {
        // GoogleSignIn 7.1 refreshes current-user tokens inside a 60-second window.
        // Use 45 seconds, and reschedule from the returned expiry even when unchanged.
        max(1, (expiration?.timeIntervalSince(now) ?? 60) - 45)
    }

    func scheduleAutoRefresh() {
        guard authenticationStatus == .connected else { return }
        scheduleAuthenticationAttempt(after: Self.authenticationRefreshDelay(expiration: storedSDMAccessTokenExpiration))
    }

    func scheduleAuthenticationAttempt(after delay: TimeInterval) {
        tokenRefreshTimer?.invalidate()
        nextAuthenticationAttempt = Date().addingTimeInterval(delay)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.nextAuthenticationAttempt = nil
            self.refreshTokenIfNeeded()
        }
        tokenRefreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        AuthenticationDiagnostics.record("google_refresh_scheduled delay_seconds=\(Int(ceil(delay)))")
    }

    func cancelAuthenticationRecovery() {
        authenticationAttemptID = UUID()
        isRefreshingToken = false
        tokenRefreshTimer?.invalidate()
        tokenRefreshTimer = nil
        nextAuthenticationAttempt = nil
        lastAuthenticationAttempt = nil
        authenticationRetryDelay = 5
    }

    func retryAuthenticationNow() {
        guard !isRefreshingToken else { return }
        cancelAuthenticationRecovery()
        authenticationStatus = .restoring
        refreshTokenIfNeeded(force: true)
    }

    func signOut() {
        cancelAuthenticationRecovery()
        authenticationStatus = .signedOut
        hasRestorableGoogleSession = false
        if !isTestMode {
            UserDefaults.standard.removeObject(forKey: "hasAuthorizedGoogleSession")
            UserDefaults.standard.removeObject(forKey: "googleReauthenticationRequired")
        }
        AuthenticationDiagnostics.record("user_signed_out")
        stopDevicePolling()
        stopPubSubPolling(shouldRestartPolling: false)
        cancelPubSubSetup()
        pollManager.reset()

        sdmAccessToken = ""
        currentTemperatureCelsius = nil
        userInfo = nil
        availableStructures = []
        availableThermostats = []
        selectedDevice = nil
        selectedStructure = nil
        selectedDeviceID = ""
        selectedStructureID = ""

        if let tokenRefreshTimer = tokenRefreshTimer {
            tokenRefreshTimer.invalidate()
            self.tokenRefreshTimer = nil
        }

        if let devicePollingTimer = devicePollingTimer {
            devicePollingTimer.invalidate()
            self.devicePollingTimer = nil
        }

        workloadIdentityProvider?.reset()
        attachWorkloadIdentityTokenListener()

        promptShownEmails.removeAll()

        print("Sign-out completed")
    }

    func beginAuthenticatedSession(sdmAccessToken: String, idToken: String?, expiration: Date?) {
        authenticationStatus = .connected
        hasRestorableGoogleSession = true
        if !isTestMode {
            UserDefaults.standard.set(true, forKey: "hasAuthorizedGoogleSession")
            UserDefaults.standard.removeObject(forKey: "googleReauthenticationRequired")
        }
        storeSDMAccessTokenExpiration(expiration)
        let tokenChanged = self.sdmAccessToken != sdmAccessToken
        self.sdmAccessToken = sdmAccessToken

        if !tokenChanged {
            scheduleAutoRefresh()
            if !isTestMode { startSessionBootstrapIfNeeded() }
        }
        // testMode suppresses the token observer's side effects, but exercises real scheduling.
        if isTestMode { scheduleAutoRefresh() }

        if let idToken, !idToken.isEmpty {
            workloadIdentityProvider?.start(idToken: idToken)
        } else if workloadIdentityProvider?.isTokenValid == true {
            startPubSubSyncIfNeeded()
        } else {
            print("beginAuthenticatedSession: Waiting for Workload Identity token before Pub/Sub setup")
        }
    }

    func clearStoredAuthentication() {
        cancelAuthenticationRecovery()
        isRestoringSession = false
        if !isTestMode { KeychainManager.delete(for: "sdmAccessToken") }
        storeSDMAccessTokenExpiration(nil)
        if sdmAccessToken.isEmpty {
            resetAuthenticatedSessionState()
        } else {
            sdmAccessToken = ""
        }
    }

    func attachWorkloadIdentityTokenListener() {
        workloadIdentityTokenSubscription?.cancel()
        workloadIdentityTokenSubscription = nil

        guard let provider = workloadIdentityProvider else {
            print("attachWorkloadIdentityTokenListener: No Workload Identity provider available")
            return
        }

        provider.requestGoogleTokenRefresh = { [weak self] in
            self?.refreshTokenIfNeeded(force: true)
        }
        workloadIdentityTokenSubscription = provider.$serviceAccountAccessToken
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] token in
                guard let self else { return }
                print("Workload Identity token updated – length: \(token.count)")
                if !token.isEmpty, !self.sdmAccessToken.isEmpty {
                    self.startPubSubSyncIfNeeded()
                }
            }
    }

    func setupNotificationObservers() {
        notificationObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        notificationObservers.removeAll()

        let center = NSWorkspace.shared.notificationCenter

        let willSleep = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            AuthenticationDiagnostics.record("system_will_sleep")
            self?.stopPubSubPolling(shouldRestartPolling: false)
        }

        let didWake = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            AuthenticationDiagnostics.record("system_did_wake")
            self?.reconnectAfterWake()
        }

        let didChangeSpace = center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            print("AppState: Active space changed – refreshing status item")
            self.menuBarStatusController?.updateStatusItemButton()
        }

        notificationObservers.append(contentsOf: [willSleep, didWake, didChangeSpace])
    }

    private var storedSDMAccessTokenExpiration: Date? {
        if isTestMode { return testTokenExpiration }
        let timestamp = UserDefaults.standard.double(forKey: AuthStorageKeys.sdmAccessTokenExpiration)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    func storeSDMAccessTokenExpiration(_ date: Date?) {
        if isTestMode { testTokenExpiration = date; return }
        if let date {
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: AuthStorageKeys.sdmAccessTokenExpiration)
        } else {
            UserDefaults.standard.removeObject(forKey: AuthStorageKeys.sdmAccessTokenExpiration)
        }
    }
}
