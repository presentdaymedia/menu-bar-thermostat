import Foundation

enum TestFixtures {
    static func thermostatDevice(
        id: String = "enterprises/test-enterprise/devices/device-1",
        customName: String? = nil,
        connectivity: String = "ONLINE",
        mode: String = "OFF",
        hvacStatus: String = "OFF",
        heatCelsius: Double? = nil,
        coolCelsius: Double? = nil,
        ambientTemperatureCelsius: Double? = nil,
        ambientHumidityPercent: Int? = nil,
        ecoMode: String? = nil,
        ecoAvailableModes: [String] = [],
        ecoHeatCelsius: Double? = nil,
        ecoCoolCelsius: Double? = nil,
        fanTimerMode: String? = nil,
        fanTimerTimeout: String? = nil
    ) -> GoogleSDMThermostatDevice {
        var traits: [String: Any] = [
            "sdm.devices.traits.Connectivity": ["status": connectivity],
            "sdm.devices.traits.ThermostatMode": [
                "availableModes": ["OFF", "HEAT", "COOL", "HEATCOOL"],
                "mode": mode
            ],
            "sdm.devices.traits.ThermostatHvac": ["status": hvacStatus]
        ]

        if let customName {
            traits["sdm.devices.traits.Info"] = ["customName": customName]
        }

        if let ambientTemperatureCelsius {
            traits["sdm.devices.traits.Temperature"] = ["ambientTemperatureCelsius": ambientTemperatureCelsius]
        }

        if let ambientHumidityPercent {
            traits["sdm.devices.traits.Humidity"] = ["ambientHumidityPercent": ambientHumidityPercent]
        }

        var setpoint: [String: Any] = [:]
        if let heatCelsius {
            setpoint["heatCelsius"] = heatCelsius
        }
        if let coolCelsius {
            setpoint["coolCelsius"] = coolCelsius
        }
        if !setpoint.isEmpty {
            traits["sdm.devices.traits.ThermostatTemperatureSetpoint"] = setpoint
        }

        var eco: [String: Any] = [:]
        if !ecoAvailableModes.isEmpty {
            eco["availableModes"] = ecoAvailableModes
        }
        if let ecoMode {
            eco["mode"] = ecoMode
        }
        if let ecoHeatCelsius {
            eco["heatCelsius"] = ecoHeatCelsius
        }
        if let ecoCoolCelsius {
            eco["coolCelsius"] = ecoCoolCelsius
        }
        if !eco.isEmpty {
            traits["sdm.devices.traits.ThermostatEco"] = eco
        }

        var fan: [String: Any] = [:]
        if let fanTimerMode {
            fan["timerMode"] = fanTimerMode
        }
        if let fanTimerTimeout {
            fan["timerTimeout"] = fanTimerTimeout
        }
        if !fan.isEmpty {
            traits["sdm.devices.traits.Fan"] = fan
        }

        let payload: [String: Any] = [
            "name": id,
            "type": "sdm.devices.types.THERMOSTAT",
            "traits": traits
        ]

        let data = try! JSONSerialization.data(withJSONObject: payload)
        return try! JSONDecoder().decode(GoogleSDMThermostatDevice.self, from: data)
    }

    static func connectivityUpdate(deviceID: String, status: String) -> EventMessage.ResourceUpdate {
        EventMessage.ResourceUpdate(
            name: deviceID,
            traits: [
                "sdm.devices.traits.Connectivity": JSONAny(value: ["status": status])
            ]
        )
    }

    static func hvacUpdate(deviceID: String, status: String) -> EventMessage.ResourceUpdate {
        EventMessage.ResourceUpdate(
            name: deviceID,
            traits: [
                "sdm.devices.traits.ThermostatHvac": JSONAny(value: ["status": status])
            ]
        )
    }

    static func setpointUpdate(deviceID: String, heatCelsius: Double? = nil, coolCelsius: Double? = nil) -> EventMessage.ResourceUpdate {
        var setpoint: [String: Any] = [:]
        if let heatCelsius {
            setpoint["heatCelsius"] = heatCelsius
        }
        if let coolCelsius {
            setpoint["coolCelsius"] = coolCelsius
        }

        return EventMessage.ResourceUpdate(
            name: deviceID,
            traits: [
                "sdm.devices.traits.ThermostatTemperatureSetpoint": JSONAny(value: setpoint)
            ]
        )
    }

    static func pubSubMessage(
        eventID: String,
        deviceID: String,
        timestamp: Date,
        traits: [String: Any]
    ) -> PubSubReceivedMessage {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestampString = formatter.string(from: timestamp)
        let eventPayload: [String: Any] = [
            "eventId": eventID,
            "timestamp": timestampString,
            "resourceUpdate": [
                "name": deviceID,
                "traits": traits
            ]
        ]
        let eventData = try! JSONSerialization.data(withJSONObject: eventPayload)
        let pubSubPayload: [String: Any] = [
            "ackId": "ack-\(eventID)",
            "message": [
                "messageId": "message-\(eventID)",
                "publishTime": timestampString,
                "data": eventData.base64EncodedString()
            ]
        ]
        let pubSubData = try! JSONSerialization.data(withJSONObject: pubSubPayload)
        return try! JSONDecoder().decode(PubSubReceivedMessage.self, from: pubSubData)
    }

    static func deviceListResponse(devices: [GoogleSDMThermostatDevice]) -> Data {
        let payload: [String: Any] = [
            "devices": devices.map { devicePayload(from: $0) }
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    private static func devicePayload(from device: GoogleSDMThermostatDevice) -> [String: Any] {
        var traits: [String: Any] = [
            "sdm.devices.traits.Connectivity": ["status": device.traits.connectivity?.status ?? "ONLINE"],
            "sdm.devices.traits.ThermostatMode": [
                "availableModes": device.traits.thermostatMode?.availableModes ?? ["OFF", "HEAT"],
                "mode": device.traits.thermostatMode?.mode ?? "OFF"
            ],
            "sdm.devices.traits.ThermostatHvac": ["status": device.traits.thermostatHvac?.status ?? "OFF"]
        ]

        if let setpoint = device.traits.thermostatTemperatureSetpoint {
            var payload: [String: Any] = [:]
            if let heat = setpoint.heatCelsius {
                payload["heatCelsius"] = heat
            }
            if let cool = setpoint.coolCelsius {
                payload["coolCelsius"] = cool
            }
            traits["sdm.devices.traits.ThermostatTemperatureSetpoint"] = payload
        }

        return [
            "name": device.id,
            "type": device.type,
            "traits": traits
        ]
    }
}
