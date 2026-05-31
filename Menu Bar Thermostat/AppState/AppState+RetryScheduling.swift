import Foundation

extension AppState {
    func cancelRetryWorkItems() {
        cancelStructuresRetry()
        cancelDevicesRetry()
        cancelGoogleUserProfileRetry()
    }

    func resetRetryBackoffs() {
        structuresRetryDelay = 5
        devicesRetryDelay = 5
        userInfoRetryDelay = 5
    }

    func cancelStructuresRetry() {
        structuresRetryWorkItem?.cancel()
        structuresRetryWorkItem = nil
    }

    func cancelDevicesRetry() {
        devicesRetryWorkItem?.cancel()
        devicesRetryWorkItem = nil
    }

    func cancelGoogleUserProfileRetry() {
        userInfoRetryWorkItem?.cancel()
        userInfoRetryWorkItem = nil
    }

    func scheduleStructuresRetry(after delay: TimeInterval) {
        guard !sdmAccessToken.isEmpty else { return }
        cancelStructuresRetry()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.structuresRetryWorkItem = nil
            self.loadStructures()
        }
        structuresRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func scheduleDevicesRetry(after delay: TimeInterval) {
        guard !sdmAccessToken.isEmpty else { return }
        cancelDevicesRetry()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.devicesRetryWorkItem = nil
            self.loadThermostats()
        }
        devicesRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func scheduleGoogleUserProfileRetry() {
        guard !sdmAccessToken.isEmpty else { return }
        cancelGoogleUserProfileRetry()
        let currentDelay = userInfoRetryDelay
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.userInfoRetryWorkItem = nil
            self.startSessionBootstrapIfNeeded()
        }
        userInfoRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + currentDelay, execute: workItem)
        userInfoRetryDelay = min(userInfoRetryDelay * 2, 60)
    }

    func handleBootstrapFailure() {
        hasStartedSessionBootstrap = false
        scheduleGoogleUserProfileRetry()
    }
}
