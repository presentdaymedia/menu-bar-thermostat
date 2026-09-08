import Foundation

extension AppState {
    func scheduleDevicePolling() {
        guard !sdmAccessToken.isEmpty, !authenticationStatus.isRecovering else {
            print("AppState: Cannot start device timer - user not signed in")
            return
        }

        devicePollingTimer?.invalidate()

        let selectedDeviceID = selectedDevice?.id
        let lastUpdateEpoch = lastNetworkDeviceUpdateTime(for: selectedDeviceID)
        let secondsSinceUpdate: TimeInterval
        if lastUpdateEpoch <= 0 {
            secondsSinceUpdate = Double.greatestFiniteMagnitude
        } else {
            secondsSinceUpdate = Date().timeIntervalSince1970 - lastUpdateEpoch
        }

        let lastFullSnapshotEpoch = lastFullDeviceSnapshotTime(for: selectedDeviceID)
        let fullSnapshotFresh = lastFullSnapshotEpoch > 0 && Date().timeIntervalSince1970 - lastFullSnapshotEpoch < Self.stateFreshnessInterval
        let pubSubFresh = secondsSinceUpdate < Self.stateFreshnessInterval
        let requiresFullStateVerification = selectedThermostatNeedsFullSnapshot()
        let canRelyOnPubSub = pubSubFresh && (!requiresFullStateVerification || fullSnapshotFresh)
        let pubSubIsActive = isPubSubActive && pubSubSubscriptionResourceName != nil && consecutiveAuthFailures < 3 && canRelyOnPubSub
        let decision = pollManager.shouldPoll(pubSubActive: pubSubIsActive, windowVisible: isPopoverVisible)

        let scheduleNext: (TimeInterval) -> Void = { [weak self] interval in
            guard let self else { return }
            self.devicePollingTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                self?.scheduleDevicePolling()
            }
            self.devicePollingTimer?.tolerance = interval * 0.1
        }

        guard decision.should else {
            print("PollManager: Skipping poll – rechecking in \(decision.interval)s (PubSubActive: \(pubSubIsActive))")
            scheduleNext(decision.interval)
            return
        }

        print("PollManager: Triggering fallback poll (next check in \(decision.interval)s, PubSubActive: \(pubSubIsActive))")
        pollSelectedDeviceState()
        scheduleNext(decision.interval)
    }

    func pollSelectedDeviceState() {
        guard let deviceID = selectedDevice?.id else {
            print("Polling update: No selected device – skipping fetch.")
            return
        }

        let isPubSubHealthy = isPubSubActive && pubSubSubscriptionResourceName != nil && consecutiveAuthFailures < 3
        let reason = isPubSubHealthy ? "Backup Poll" : "Regular Poll"
        print("\(reason) – Fetching device state at: \(Date())")

        loadDeviceSnapshot(deviceID: deviceID) { updatedDevice in
            if updatedDevice == nil {
                print("Polling update: Failed to fetch device state.")
            }
        }
    }

    func stopDevicePolling() {
        devicePollingTimer?.invalidate()
        devicePollingTimer = nil
    }

    func handleRateLimitError() {
        print("Rate limit hit - adjusting polling intervals")

        if isPopoverVisible {
            let currentInterval = devicePollingTimer?.timeInterval ?? 15.0
            let newInterval = min(currentInterval * 2, 60.0)
            print("Increasing visible polling interval from \(currentInterval) to \(newInterval) seconds")
        }

        pollManager.recordRateLimit()
        scheduleDevicePolling()
    }
}
