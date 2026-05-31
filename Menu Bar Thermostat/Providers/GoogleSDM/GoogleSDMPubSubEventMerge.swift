import Foundation
import Alamofire

private let iso8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

extension AppState {
    @MainActor
    func handlePubSubMessages(_ messages: [PubSubReceivedMessage]) {
        // Collect and sort valid messages
        var validEvents: [(event: EventMessage, ackId: String, timestamp: Date)] = []
        var validAckIds: [String] = [] // To collect ackIds for messages that are processed or explicitly ignored

        for receivedMessage in messages {
            // Include ALL ackIds to ensure we clear them from the subscription
            validAckIds.append(receivedMessage.ackId)

            guard let messageData = receivedMessage.message.data,
                  let data = Data(base64Encoded: messageData) else {
                print("Pub/Sub: Missing or invalid data in message, acknowledging to remove from queue.")
                continue
            }

            do {
                let eventMessage = try JSONDecoder().decode(EventMessage.self, from: data)
                // Parse timestamp
                if let date = iso8601Formatter.date(from: eventMessage.timestamp) {
                    validEvents.append((eventMessage, receivedMessage.ackId, date))
                } else {
                    // Fallback if parsing fails, but proceed
                    print("Pub/Sub: Could not parse timestamp for event \(eventMessage.eventId), using current date.")
                    validEvents.append((eventMessage, receivedMessage.ackId, Date()))
                }
            } catch {
                print("Error decoding Pub/Sub message: \(error.localizedDescription)")
            }
        }

        // Sort by timestamp (oldest first)
        validEvents.sort { $0.timestamp < $1.timestamp }

        for (eventMessage, _, timestamp) in validEvents {
            if hasProcessedPubSubEvent(id: eventMessage.eventId) {
                print("Pub/Sub: Ignoring duplicate event \(eventMessage.eventId)")
                continue
            }

            #if DEBUG
            print("Pub/Sub: Processing event \(eventMessage.eventId) from \(eventMessage.timestamp)")
            #endif

            if let resourceUpdate = eventMessage.resourceUpdate {
                self.mergePubSubResourceUpdate(resourceUpdate, eventTimestamp: timestamp)
            }
            rememberProcessedPubSubEvent(id: eventMessage.eventId)
            if timestamp > self.lastProcessedPubSubEventTime {
                self.lastProcessedPubSubEventTime = timestamp
            }
        }

        // Acknowledge all processed (and ignored) messages
        if !validAckIds.isEmpty {
            self.acknowledgePubSubMessageIDs(validAckIds)
        }
    }

    @MainActor
    @discardableResult
    private func mergePubSubResourceUpdate(_ resourceUpdate: EventMessage.ResourceUpdate, eventTimestamp: Date = Date()) -> Bool {
        #if DEBUG
        print("Processing traits update for device: \(resourceUpdate.name)")
        #endif

        guard let traitsFromEvent = resourceUpdate.traits else {
            #if DEBUG
            print("Pub/Sub: No traits found in resource update event. Ignoring.")
            #endif
            return false
        }

        let selectedIsTarget = selectedDevice?.id == resourceUpdate.name
        let deviceIndex = availableThermostats.firstIndex(where: { $0.id == resourceUpdate.name })

        guard let currentThermostat = selectedIsTarget ? selectedDevice : deviceIndex.map({ availableThermostats[$0] }) else {
            print("Pub/Sub: Update received for unknown device \(resourceUpdate.name); refreshing device list.")
            loadThermostats()
            return false
        }

        var potentialNewDevice = currentThermostat
        var traitsUpdated = false
        var freshTraitObserved = false

        func beginTraitUpdate(_ traitName: String) -> Bool {
            guard shouldApplyPubSubTrait(deviceID: resourceUpdate.name, traitName: traitName, eventTimestamp: eventTimestamp) else {
                return false
            }
            recordPubSubTraitEvent(deviceID: resourceUpdate.name, traitName: traitName, eventTimestamp: eventTimestamp)
            freshTraitObserved = true
            return true
        }

        if let connectivityTrait = traitsFromEvent["sdm.devices.traits.Connectivity"],
           let dict = connectivityTrait.value as? [String: Any],
           let status = dict["status"] as? String {
            if beginTraitUpdate("sdm.devices.traits.Connectivity") {
                if potentialNewDevice.traits.connectivity == nil {
                    potentialNewDevice.traits.connectivity = .init(status: status)
                    traitsUpdated = true
                } else if potentialNewDevice.traits.connectivity?.status != status {
                    potentialNewDevice.traits.connectivity?.status = status
                    traitsUpdated = true
                }

                if status == "OFFLINE" {
                    print("GoogleSDMThermostatDevice went offline: \(resourceUpdate.name)")
                } else if status == "ONLINE" {
                    print("GoogleSDMThermostatDevice came back online: \(resourceUpdate.name)")
                }
            }
        }

        if let temperatureTrait = traitsFromEvent["sdm.devices.traits.Temperature"],
           let dict = temperatureTrait.value as? [String: Any],
           let ambientTemp = dict["ambientTemperatureCelsius"] as? Double {
            if beginTraitUpdate("sdm.devices.traits.Temperature") {
                if abs((potentialNewDevice.traits.temperature?.ambientTemperatureCelsius ?? -999) - ambientTemp) > 0.01 {
                    #if DEBUG
                    print("Pub/Sub: Temperature update: \(ambientTemp)°C")
                    #endif
                    potentialNewDevice.traits.temperature = .init(ambientTemperatureCelsius: ambientTemp)
                    traitsUpdated = true
                }
            }
        }

        if let hvacTrait = traitsFromEvent["sdm.devices.traits.ThermostatHvac"],
           let dict = hvacTrait.value as? [String: Any],
           let status = dict["status"] as? String {
            if beginTraitUpdate("sdm.devices.traits.ThermostatHvac") {
                if potentialNewDevice.traits.thermostatHvac == nil { potentialNewDevice.traits.thermostatHvac = .init(status: nil) }
                if potentialNewDevice.traits.thermostatHvac?.status != status {
                    #if DEBUG
                    print("Pub/Sub: HVAC status update: \(status)")
                    #endif
                    potentialNewDevice.traits.thermostatHvac?.status = status
                    traitsUpdated = true
                }
            }
        }

        if let modeTrait = traitsFromEvent["sdm.devices.traits.ThermostatMode"],
           let dict = modeTrait.value as? [String: Any],
           let mode = dict["mode"] as? String {
            if beginTraitUpdate("sdm.devices.traits.ThermostatMode") {
                if potentialNewDevice.traits.thermostatMode == nil {
                    potentialNewDevice.traits.thermostatMode = .init(availableModes: currentThermostat.traits.thermostatMode?.availableModes ?? [], mode: mode)
                    traitsUpdated = true
                } else if potentialNewDevice.traits.thermostatMode?.mode != mode {
                    #if DEBUG
                    print("Pub/Sub: Thermostat mode update: \(mode)")
                    #endif
                    potentialNewDevice.traits.thermostatMode?.mode = mode
                    traitsUpdated = true
                }
                if potentialNewDevice.traits.thermostatTemperatureSetpoint == nil {
                    potentialNewDevice.traits.thermostatTemperatureSetpoint = .init(coolCelsius: nil, heatCelsius: nil)
                }
                switch mode {
                case "COOL":
                    potentialNewDevice.traits.thermostatTemperatureSetpoint?.heatCelsius = nil
                case "HEAT":
                    potentialNewDevice.traits.thermostatTemperatureSetpoint?.coolCelsius = nil
                default:
                    break
                }
                potentialNewDevice.traits.thermostatMode?.availableModes = currentThermostat.traits.thermostatMode?.availableModes ?? []
            }
        }

        if let ecoTrait = traitsFromEvent["sdm.devices.traits.ThermostatEco"],
           let dict = ecoTrait.value as? [String: Any],
           let mode = dict["mode"] as? String {
            if beginTraitUpdate("sdm.devices.traits.ThermostatEco") {
                if potentialNewDevice.traits.thermostatEco == nil {
                    potentialNewDevice.traits.thermostatEco = .init(
                        availableModes: currentThermostat.traits.thermostatEco?.availableModes ?? [],
                        coolCelsius: currentThermostat.traits.thermostatEco?.coolCelsius,
                        heatCelsius: currentThermostat.traits.thermostatEco?.heatCelsius,
                        mode: mode
                    )
                    traitsUpdated = true
                } else if potentialNewDevice.traits.thermostatEco?.mode != mode {
                    #if DEBUG
                    print("Pub/Sub: ECO mode update: \(mode)")
                    #endif
                    potentialNewDevice.traits.thermostatEco?.mode = mode
                    traitsUpdated = true
                }
            }
        }

        if let setpointTrait = traitsFromEvent["sdm.devices.traits.ThermostatTemperatureSetpoint"],
           let dict = setpointTrait.value as? [String: Any] {
            if beginTraitUpdate("sdm.devices.traits.ThermostatTemperatureSetpoint") {
                if potentialNewDevice.traits.thermostatTemperatureSetpoint == nil {
                    potentialNewDevice.traits.thermostatTemperatureSetpoint = .init(coolCelsius: nil, heatCelsius: nil)
                }

                if dict.keys.contains("coolCelsius") {
                    let coolCelsius = dict["coolCelsius"] as? Double
                    let oldCoolCelsius = potentialNewDevice.traits.thermostatTemperatureSetpoint?.coolCelsius
                    if oldCoolCelsius != coolCelsius {
                        let newTempStr = coolCelsius.map { "\($0)°C" } ?? "nil"
                        print("Pub/Sub: Cool setpoint update: \(oldCoolCelsius ?? -1)°C → \(newTempStr)")
                        potentialNewDevice.traits.thermostatTemperatureSetpoint?.coolCelsius = coolCelsius
                        traitsUpdated = true
                    }
                }

                if dict.keys.contains("heatCelsius") {
                    let heatCelsius = dict["heatCelsius"] as? Double
                    let oldHeatCelsius = potentialNewDevice.traits.thermostatTemperatureSetpoint?.heatCelsius
                    if oldHeatCelsius != heatCelsius {
                        let newTempStr = heatCelsius.map { "\($0)°C" } ?? "nil"
                        print("Pub/Sub: Heat setpoint update: \(oldHeatCelsius ?? -1)°C → \(newTempStr)")
                        potentialNewDevice.traits.thermostatTemperatureSetpoint?.heatCelsius = heatCelsius
                        traitsUpdated = true
                    }
                }
            }
        }

        if let fanTrait = traitsFromEvent["sdm.devices.traits.Fan"],
           let dict = fanTrait.value as? [String: Any],
           let timerMode = dict["timerMode"] as? String {
            if beginTraitUpdate("sdm.devices.traits.Fan") {
                let timerTimeout = dict["timerTimeout"] as? String
                let oldTimerMode = potentialNewDevice.traits.fan?.timerMode
                let oldTimerTimeout = potentialNewDevice.traits.fan?.timerTimeout

                if potentialNewDevice.traits.fan == nil {
                    potentialNewDevice.traits.fan = .init(timerMode: timerMode, timerTimeout: timerTimeout)
                    traitsUpdated = true
                } else if oldTimerMode != timerMode || oldTimerTimeout != timerTimeout {
                    potentialNewDevice.traits.fan?.timerMode = timerMode
                    potentialNewDevice.traits.fan?.timerTimeout = timerTimeout
                    traitsUpdated = true
                }
            }
        }

        // Additional trait merges can be added here.

        if let deviceIndex {
            self.availableThermostats[deviceIndex] = potentialNewDevice
        }

        if selectedIsTarget, traitsUpdated {
            self.selectedDevice = potentialNewDevice
            if let ambientTemperatureCelsius = potentialNewDevice.traits.temperature?.ambientTemperatureCelsius {
                self.currentTemperatureCelsius = ambientTemperatureCelsius
                self.updateDisplayedTemperature()
            }
            self.updateTemperatureUnitFromDevice()
        }

        if selectedIsTarget, freshTraitObserved, let connectivityStatus = potentialNewDevice.traits.connectivity?.status {
            if connectivityStatus == "OFFLINE" {
                self.markConnectionUnhealthy()
            } else {
                self.markConnectionHealthy()
            }
        }
        if freshTraitObserved {
            self.markNetworkDeviceUpdate(deviceID: resourceUpdate.name)
        }
        return freshTraitObserved
    }

    func acknowledgePubSubMessageIDs(_ ackIds: [String]) {
        guard !pubSubAccessToken.isEmpty else {
            print("Cannot acknowledge Pub/Sub messages: Missing bearer token")
            return
        }

        guard let subscription = pubSubSubscriptionResourceName else {
            print("Cannot acknowledge Pub/Sub messages: Missing subscription")
            return
        }

        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(pubSubAccessToken)",
            "Content-Type": "application/json"
        ]

        let url = "https://pubsub.googleapis.com/v1/\(subscription):acknowledge"
        let request = PubSubAcknowledgeRequest(ackIds: ackIds)

        httpSession.request(url, method: .post, parameters: request, encoder: JSONParameterEncoder.default, headers: headers)
            .validate()
            .response { response in
                switch response.result {
                case .success:
                    print("Successfully acknowledged Pub/Sub messages")
                case .failure(let error):
                    print("Error acknowledging Pub/Sub messages: \(error.localizedDescription)")
                }
            }
    }

    @MainActor
    func applyResourceUpdateForTesting(_ resourceUpdate: EventMessage.ResourceUpdate) {
        mergePubSubResourceUpdate(resourceUpdate)
    }

    @MainActor
    func applyResourceUpdateForTesting(_ resourceUpdate: EventMessage.ResourceUpdate, timestamp: Date) {
        mergePubSubResourceUpdate(resourceUpdate, eventTimestamp: timestamp)
    }

    @MainActor
    func handlePubSubMessagesForTesting(_ messages: [PubSubReceivedMessage]) {
        handlePubSubMessages(messages)
    }
}
