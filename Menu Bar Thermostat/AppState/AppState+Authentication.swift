import Foundation
import Combine
import AppKit
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

private enum AuthStorageKeys {
    static let sdmAccessTokenExpiration = "sdmAccessTokenExpirationDate"
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

    func refreshTokenIfNeeded(force: Bool = false) {
#if canImport(GoogleSignIn)
        if isRefreshingToken {
            print("refreshTokenIfNeeded: Refresh already in progress – skipping request")
            return
        }

        let lastRefreshTime = UserDefaults.standard.double(forKey: "lastSDMTokenRefreshTime")
        let currentTime = Date().timeIntervalSince1970
        guard force || currentTime - lastRefreshTime > 300.0 else { return }

        isRefreshingToken = true
        print("Attempting to refresh authentication token…")
        configureGoogleSignInIfNeeded()

        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                defer {
                    self.isRefreshingToken = false
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastSDMTokenRefreshTime")
                }

                if let error = error {
                    print("Error restoring sign-in: \(error.localizedDescription)")
                    self.clearStoredAuthentication()
                    return
                }

                guard let user = user else {
                    print("No previous user session found while refreshing token")
                    self.clearStoredAuthentication()
                    return
                }

                let newSDMAccessToken = user.accessToken.tokenString
                self.storeSDMAccessTokenExpiration(user.accessToken.expirationDate)
                let idToken = user.idToken?.tokenString ?? ""

                if self.sdmAccessToken != newSDMAccessToken {
                    print("OAuth token refreshed (first 10 chars): \(newSDMAccessToken.prefix(10))…")
                    self.beginAuthenticatedSession(
                        sdmAccessToken: newSDMAccessToken,
                        idToken: idToken,
                        expiration: user.accessToken.expirationDate
                    )
                } else {
                    print("OAuth token unchanged after refresh")
                    self.scheduleAutoRefresh()
                }

                if force || !(self.workloadIdentityProvider?.isTokenValid ?? false) {
                    if idToken.isEmpty {
                        print("refreshTokenIfNeeded: Cannot start Workload Identity – missing ID token")
                    } else {
                        print("refreshTokenIfNeeded: Starting Workload Identity exchange (forced: \(force), tokenValid: \(self.workloadIdentityProvider?.isTokenValid ?? false))")
                        self.workloadIdentityProvider?.start(idToken: idToken)
                    }
                }
            }
        }
#else
        print("refreshTokenIfNeeded: GoogleSignIn is unavailable in this build.")
#endif
    }

    func scheduleAutoRefresh() {
#if canImport(GoogleSignIn)
        tokenRefreshTimer?.invalidate()
        tokenRefreshTimer = nil

        let expiration = GIDSignIn.sharedInstance.currentUser?.accessToken.expirationDate ?? storedSDMAccessTokenExpiration

        guard let expiration else {
            print("scheduleAutoRefresh: No access-token expiration date – not scheduling.")
            return
        }

        let timeUntilExpiration = expiration.timeIntervalSinceNow
        if timeUntilExpiration <= 0 {
            print("scheduleAutoRefresh: Access token already expired – refreshing immediately.")
            refreshTokenIfNeeded(force: true)
            return
        }

        let interval = timeUntilExpiration - 300
        let delay = max(30, interval)

        tokenRefreshTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            print("Auto-refreshing OAuth token (scheduled)")
            self?.refreshTokenIfNeeded()
            self?.scheduleAutoRefresh()
        }

        print("Scheduled token auto-refresh in \(Int(delay)) seconds (token expires at \(expiration))")
#else
        tokenRefreshTimer?.invalidate()
        tokenRefreshTimer = nil
        print("scheduleAutoRefresh: GoogleSignIn unavailable; auto-refresh disabled.")
#endif
    }

    func signOut() {
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
        storeSDMAccessTokenExpiration(expiration)
        let tokenChanged = self.sdmAccessToken != sdmAccessToken
        self.sdmAccessToken = sdmAccessToken

        if !tokenChanged {
            scheduleAutoRefresh()
            startSessionBootstrapIfNeeded()
        }

        if let idToken, !idToken.isEmpty {
            workloadIdentityProvider?.start(idToken: idToken)
        } else if workloadIdentityProvider?.isTokenValid == true {
            startPubSubSyncIfNeeded()
        } else {
            print("beginAuthenticatedSession: Waiting for Workload Identity token before Pub/Sub setup")
        }
    }

    func clearStoredAuthentication() {
        isRestoringSession = false
        KeychainManager.delete(for: "sdmAccessToken")
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
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationObservers.removeAll()

        let center = NSWorkspace.shared.notificationCenter

        let willSleep = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            print("AppState: System will sleep – stopping Pub/Sub polling")
            self?.stopPubSubPolling(shouldRestartPolling: false)
        }

        let didWake = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            print("AppState: System woke from sleep – reconnecting")
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
        let timestamp = UserDefaults.standard.double(forKey: AuthStorageKeys.sdmAccessTokenExpiration)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }

    func storeSDMAccessTokenExpiration(_ date: Date?) {
        if let date {
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: AuthStorageKeys.sdmAccessTokenExpiration)
        } else {
            UserDefaults.standard.removeObject(forKey: AuthStorageKeys.sdmAccessTokenExpiration)
        }
    }
}
