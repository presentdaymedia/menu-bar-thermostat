import Foundation

extension AppState {
    func markNetworkDeviceUpdate(deviceID: String? = nil, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        UserDefaults.standard.set(timestamp, forKey: Self.lastNetworkDeviceUpdateKey)
        if let deviceID {
            lastNetworkSnapshotTimesByDeviceID[deviceID] = timestamp
        }
    }

    func lastNetworkDeviceUpdateTime(for deviceID: String? = nil) -> TimeInterval {
        if let deviceID, let timestamp = lastNetworkSnapshotTimesByDeviceID[deviceID] {
            return timestamp
        }
        return UserDefaults.standard.double(forKey: Self.lastNetworkDeviceUpdateKey)
    }

    func recordFullDeviceSnapshot(_ device: GoogleSDMThermostatDevice, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        lastFullSnapshotTimesByDeviceID[device.id] = timestamp
        markNetworkDeviceUpdate(deviceID: device.id, timestamp: timestamp)
    }

    func recordFullDeviceSnapshots(_ availableThermostats: [GoogleSDMThermostatDevice], timestamp: TimeInterval = Date().timeIntervalSince1970) {
        guard !availableThermostats.isEmpty else { return }
        for device in availableThermostats {
            lastFullSnapshotTimesByDeviceID[device.id] = timestamp
            lastNetworkSnapshotTimesByDeviceID[device.id] = timestamp
        }
        UserDefaults.standard.set(timestamp, forKey: Self.lastNetworkDeviceUpdateKey)
    }

    func lastFullDeviceSnapshotTime(for deviceID: String?) -> TimeInterval {
        guard let deviceID else { return 0 }
        return lastFullSnapshotTimesByDeviceID[deviceID] ?? 0
    }

    func selectedThermostatNeedsFullSnapshot() -> Bool {
        guard let selectedDevice else { return false }
        if selectedDeviceConnectionHealth == .disconnected {
            return true
        }
        if selectedDevice.traits.connectivity?.status == "OFFLINE" {
            return true
        }
        switch selectedDevice.traits.thermostatHvac?.status {
        case "HEATING", "COOLING":
            return true
        default:
            return false
        }
    }

    func shouldApplyPubSubTrait(deviceID: String, traitName: String, eventTimestamp: Date) -> Bool {
        let fullSnapshotTime = lastFullDeviceSnapshotTime(for: deviceID)
        if fullSnapshotTime > 0, eventTimestamp.timeIntervalSince1970 <= fullSnapshotTime {
            print("Pub/Sub: Ignoring stale \(traitName) event for \(deviceID); full snapshot is newer.")
            return false
        }

        if let lastTraitEventTime = lastTraitEventTimesByDeviceID[deviceID]?[traitName],
           eventTimestamp < lastTraitEventTime {
            print("Pub/Sub: Ignoring out-of-order \(traitName) event for \(deviceID).")
            return false
        }

        return true
    }

    func recordPubSubTraitEvent(deviceID: String, traitName: String, eventTimestamp: Date) {
        var traitTimes = lastTraitEventTimesByDeviceID[deviceID] ?? [:]
        if let existing = traitTimes[traitName] {
            traitTimes[traitName] = max(existing, eventTimestamp)
        } else {
            traitTimes[traitName] = eventTimestamp
        }
        lastTraitEventTimesByDeviceID[deviceID] = traitTimes
    }

    func hasProcessedPubSubEvent(id: String) -> Bool {
        processedPubSubEventIDs.contains(id)
    }

    func rememberProcessedPubSubEvent(id: String) {
        guard !id.isEmpty, processedPubSubEventIDs.insert(id).inserted else { return }
        processedPubSubEventIDOrder.append(id)

        while processedPubSubEventIDOrder.count > Self.maxRememberedPubSubEventIDs {
            let oldestID = processedPubSubEventIDOrder.removeFirst()
            processedPubSubEventIDs.remove(oldestID)
        }
    }

    func markConnectionHealthy() {
        if selectedDeviceConnectionHealth != .connected {
            selectedDeviceConnectionHealth = .connected
        }
    }

    func markConnectionUnhealthy() {
        if selectedDeviceConnectionHealth != .disconnected {
            selectedDeviceConnectionHealth = .disconnected
        }
    }

    func updateSelectedDeviceConnectionHealth() {
        guard sdmAccessToken.isEmpty == false else {
            selectedDeviceConnectionHealth = .unknown
            return
        }

        guard let device = selectedDevice else {
            selectedDeviceConnectionHealth = .unknown
            return
        }

        if device.traits.connectivity?.status == "OFFLINE" {
            markConnectionUnhealthy()
        } else if device.traits.connectivity?.status == "ONLINE" {
            markConnectionHealthy()
        } else if selectedDeviceConnectionHealth == .unknown {
            markConnectionHealthy()
        }
    }

    func refreshSelectedDeviceAfterSelectionChange(oldDeviceID: String?) {
        guard !isTestMode,
              !sdmAccessToken.isEmpty,
              let deviceID = selectedDevice?.id,
              deviceID != oldDeviceID else { return }

        let lastUpdateEpoch = lastNetworkDeviceUpdateTime(for: deviceID)
        let hasFreshNetworkState = lastUpdateEpoch > 0 && Date().timeIntervalSince1970 - lastUpdateEpoch < Self.stateFreshnessInterval
        guard !hasFreshNetworkState else { return }

        loadDeviceSnapshot(deviceID: deviceID) { _ in }
    }
}
