import Foundation
import AppKit

extension AppState {
    func resetAuthenticatedSessionState() {
        authSessionVersion += 1
        stopDevicePolling()
        stopPubSubPolling(shouldRestartPolling: false)
        cancelPubSubSetup()
        pollManager.reset()
        cancelRetryWorkItems()
        resetRetryBackoffs()
        workloadIdentityProvider?.reset()
        pubSubSubscriptionResourceName = nil
        hasValidatedPubSubTopic = false
        latestPubSubError = nil
        consecutiveAuthFailures = 0
        consecutiveNetworkFailures = 0
        lastNetworkSnapshotTimesByDeviceID.removeAll()
        lastFullSnapshotTimesByDeviceID.removeAll()
        lastTraitEventTimesByDeviceID.removeAll()
        processedPubSubEventIDs.removeAll()
        processedPubSubEventIDOrder.removeAll()
        lastProcessedPubSubEventTime = .distantPast

        currentTemperatureCelsius = nil
        userInfo = nil
        availableStructures = []
        availableThermostats = []
        selectedDevice = nil
        selectedStructure = nil
        selectedDeviceID = ""
        selectedStructureID = ""
        promptShownEmails.removeAll()
        selectedDeviceConnectionHealth = .unknown
        UserDefaults.standard.removeObject(forKey: Self.lastNetworkDeviceUpdateKey)
        UserDefaults.standard.removeObject(forKey: "lastDeviceUpdateTime")
    }

    func cleanup() {
        cancelAuthenticationRecovery()
        notificationObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        stopDevicePolling()
        stopPubSubPolling(shouldRestartPolling: false)
        cancelPubSubSetup()
        cancelRetryWorkItems()

        tokenRefreshTimer?.invalidate()
        tokenRefreshTimer = nil

        workloadIdentityTokenSubscription?.cancel()
        workloadIdentityTokenSubscription = nil
        workloadIdentityProvider?.reset()

        print("AppState cleanup completed")
    }

    func reconnectAfterWake() {
        print("AppState: Reconnecting after wake from sleep")

        guard authenticationStatus != .signedOut,
              authenticationStatus != .reauthenticationRequired else { return }
        // Resume through the shared refresh completion, after credentials are ready.
        refreshTokenIfNeeded(force: true)
    }

    func startSessionBootstrapIfNeeded() {
        guard !hasStartedSessionBootstrap else { return }
        hasStartedSessionBootstrap = true
        loadSignedInGoogleUser()
    }

    func isCurrentAuthSession(_ generation: Int) -> Bool {
        generation == authSessionVersion && !sdmAccessToken.isEmpty
    }
}
