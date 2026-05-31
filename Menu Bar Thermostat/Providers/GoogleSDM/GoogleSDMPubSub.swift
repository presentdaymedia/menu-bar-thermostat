import Foundation

extension AppState {
    func startPubSubSyncIfNeeded() {
        guard !sdmAccessToken.isEmpty else {
            print("Cannot initialize Pub/Sub: No access token")
            return
        }
        guard pubSubSubscriptionSetupTask == nil else {
            print("startPubSubSyncIfNeeded: Subscription setup already in progress – skipping re-init")
            return
        }
        guard !isPubSubActive else {
            print("startPubSubSyncIfNeeded: Listener already active – skipping re-init")
            return
        }

        guard !pubSubAccessToken.isEmpty else {
            print("startPubSubSyncIfNeeded: Waiting for Workload Identity token…")
            scheduledPubSubRetry?.cancel()
            let generation = authSessionVersion
            let workItem = DispatchWorkItem { [weak self] in
                guard let self,
                      !self.sdmAccessToken.isEmpty,
                      self.isCurrentAuthSession(generation),
                      self.workloadIdentityProvider != nil else { return }
                self.scheduledPubSubRetry = nil
                self.startPubSubSyncIfNeeded()
            }
            scheduledPubSubRetry = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: workItem)
            return
        }

        consecutiveAuthFailures = 0
        consecutiveNetworkFailures = 0
        pubSubBackoffDelay = 1.0

        ensurePubSubSubscription(sessionGeneration: authSessionVersion)
        print("Pub/Sub initialization completed")
    }
}
