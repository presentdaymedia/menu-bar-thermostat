import Foundation

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

        guard !sdmAccessToken.isEmpty else {
            print("AppState: Not signed in, skipping reconnection after wake")
            return
        }

        // Force refresh tokens - this will trigger Workload Identity exchange which will call
        // startPubSubSyncIfNeeded() via the Workload Identity token listener when complete
        refreshTokenIfNeeded(force: true)
        // Note: startPubSubSyncIfNeeded() is NOT called here because it would race with
        // the async token refresh. The Workload Identity token listener handles this.

        if let deviceID = selectedDevice?.id {
            print("AppState: Fetching device state after wake")
            loadDeviceSnapshot(deviceID: deviceID) { [weak self] updatedDevice in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let updatedDevice = updatedDevice {
                        print("AppState: GoogleSDMThermostatDevice state refreshed after wake")
                        self.selectedDevice = updatedDevice
                        if let ambientTemperatureCelsius = updatedDevice.traits.temperature?.ambientTemperatureCelsius {
                            self.currentTemperatureCelsius = ambientTemperatureCelsius
                            self.updateDisplayedTemperature()
                        }
                        self.updateTemperatureUnitFromDevice()
                    } else {
                        print("AppState: GoogleSDMThermostatDevice fetch failed after wake")
                    }
                }
            }
        }

        scheduleDevicePolling()
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
