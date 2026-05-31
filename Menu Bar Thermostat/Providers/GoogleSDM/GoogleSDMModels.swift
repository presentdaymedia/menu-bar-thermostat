import Foundation

struct GoogleUserProfile: Decodable {
    let name: String
    let email: String
    let picture: String?
}

struct StructureListResponse: Decodable {
    let structures: [Structure]
}

struct Structure: Decodable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let traits: Traits

    struct Traits: Decodable {
        let info: Info?

        struct Info: Decodable {
            let customName: String?
        }

        enum CodingKeys: String, CodingKey {
            case info = "sdm.structures.traits.Info"
        }
    }

    var displayName: String {
        traits.info?.customName ?? name
    }

    static func == (lhs: Structure, rhs: Structure) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

extension Structure: CustomDebugStringConvertible {
    var debugDescription: String {
        "Structure(id: \(id), name: \(name), customName: \(traits.info?.customName ?? "N/A"))"
    }
}

struct GoogleSDMDeviceListResponse: Decodable {
    let devices: [GoogleSDMThermostatDevice]
}

struct GoogleSDMThermostatDevice: Decodable, Identifiable {
    let id: String
    let name: String
    let type: String
    var traits: Traits
    let parentRelations: [ParentRelation]?

    enum CodingKeys: String, CodingKey {
        case id = "name"
        case type
        case traits
        case parentRelations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = id
        type = try container.decode(String.self, forKey: .type)
        traits = try container.decode(Traits.self, forKey: .traits)
        parentRelations = try container.decodeIfPresent([ParentRelation].self, forKey: .parentRelations)
    }

    var displayName: String {
        if let customName = traits.info?.customName, !customName.isEmpty {
            return customName
        }

        if let nickname = traits.info?.nickname, !nickname.isEmpty {
            return nickname
        }

        if let parentName = parentRelations?.compactMap({ $0.displayName }).first(where: { !$0.isEmpty }) {
            return parentName
        }

        if let lastComponent = id.split(separator: "/").last, !lastComponent.isEmpty {
            return String(lastComponent)
        }

        return id
    }

    func belongsToStructure(_ structureID: String) -> Bool {
        let normalizedStructureID = structureID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedStructureID.isEmpty else { return false }

        return parentRelations?.contains(where: { relation in
            guard let parent = relation.parent?.trimmingCharacters(in: .whitespacesAndNewlines), !parent.isEmpty else {
                return false
            }
            if parent == normalizedStructureID {
                return true
            }
            if parent.hasPrefix(normalizedStructureID + "/") {
                return true
            }
            if let roomRange = parent.range(of: "/rooms/") {
                let structureComponent = String(parent[..<roomRange.lowerBound])
                return structureComponent == normalizedStructureID
            }
            return false
        }) ?? false
    }

    struct Traits: Decodable {
        var connectivity: Connectivity?
        var fan: Fan?
        let humidity: Humidity?
        let info: Info?
        let settings: Settings?
        var temperature: Temperature?
        var thermostatEco: ThermostatEco?
        var thermostatHvac: ThermostatHvac?
        var thermostatMode: ThermostatMode?
        var thermostatTemperatureSetpoint: ThermostatTemperatureSetpoint?

        enum CodingKeys: String, CodingKey {
            case connectivity = "sdm.devices.traits.Connectivity"
            case fan = "sdm.devices.traits.Fan"
            case humidity = "sdm.devices.traits.Humidity"
            case info = "sdm.devices.traits.Info"
            case settings = "sdm.devices.traits.Settings"
            case temperature = "sdm.devices.traits.Temperature"
            case thermostatEco = "sdm.devices.traits.ThermostatEco"
            case thermostatHvac = "sdm.devices.traits.ThermostatHvac"
            case thermostatMode = "sdm.devices.traits.ThermostatMode"
            case thermostatTemperatureSetpoint = "sdm.devices.traits.ThermostatTemperatureSetpoint"
        }

        struct Connectivity: Decodable {
            var status: String
        }

        struct Fan: Decodable {
            var timerMode: String?
            var timerTimeout: String?
        }

        struct Humidity: Decodable {
            let ambientHumidityPercent: Int
        }

        struct Info: Decodable {
            let customName: String?
            let nickname: String?
        }

        struct Settings: Decodable {
            let temperatureScale: String?
        }

        struct Temperature: Decodable {
            var ambientTemperatureCelsius: Double?
        }

        struct ThermostatEco: Decodable, Equatable {
            var availableModes: [String]
            var coolCelsius: Double?
            var heatCelsius: Double?
            var mode: String?
        }

        struct ThermostatHvac: Decodable, Equatable {
            var status: String?
        }

        struct ThermostatMode: Decodable, Equatable {
            var availableModes: [String]
            var mode: String?
        }

        struct ThermostatTemperatureSetpoint: Decodable, Equatable {
            var coolCelsius: Double?
            var heatCelsius: Double?
        }
    }

    struct ParentRelation: Decodable {
        let displayName: String?
        let parent: String?
    }

    func hasSameState(as other: GoogleSDMThermostatDevice) -> Bool {
        traits.connectivity?.status == other.traits.connectivity?.status &&
        traits.thermostatTemperatureSetpoint?.coolCelsius == other.traits.thermostatTemperatureSetpoint?.coolCelsius &&
        traits.thermostatTemperatureSetpoint?.heatCelsius == other.traits.thermostatTemperatureSetpoint?.heatCelsius &&
        traits.thermostatHvac?.status == other.traits.thermostatHvac?.status &&
        traits.thermostatMode?.mode == other.traits.thermostatMode?.mode &&
        traits.thermostatEco?.mode == other.traits.thermostatEco?.mode &&
        traits.temperature?.ambientTemperatureCelsius == other.traits.temperature?.ambientTemperatureCelsius &&
        traits.fan?.timerMode == other.traits.fan?.timerMode &&
        traits.fan?.timerTimeout == other.traits.fan?.timerTimeout
    }
}

extension GoogleSDMThermostatDevice.Traits.ThermostatMode {
    var normalizedMode: String {
        mode ?? "OFF"
    }
}

extension GoogleSDMThermostatDevice.Traits.ThermostatTemperatureSetpoint {
    var hasValues: Bool {
        coolCelsius != nil || heatCelsius != nil
    }
}

extension ThermostatOperatingMode {
    init(sdmMode: String?, sdmEcoMode: String?) {
        if sdmEcoMode == "MANUAL_ECO" {
            self = .eco
        } else {
            self.init(commandValue: sdmMode)
        }
    }
}

extension ThermostatHvacState {
    init(sdmStatus: String?) {
        switch sdmStatus {
        case "OFF":
            self = .off
        case "HEATING":
            self = .heating
        case "COOLING":
            self = .cooling
        default:
            self = .unknown(sdmStatus)
        }
    }
}

extension ThermostatConnectionState {
    init(sdmStatus: String?) {
        switch sdmStatus {
        case "ONLINE":
            self = .online
        case "OFFLINE":
            self = .offline
        case let value?:
            self = .other(value)
        case nil:
            self = .unknown
        }
    }
}

extension Thermostat {
    init(googleSDMDevice device: GoogleSDMThermostatDevice) {
        let ecoState = ThermostatEcoState(
            availableModes: device.traits.thermostatEco?.availableModes ?? [],
            coolCelsius: device.traits.thermostatEco?.coolCelsius,
            heatCelsius: device.traits.thermostatEco?.heatCelsius,
            mode: device.traits.thermostatEco?.mode
        )

        id = device.id
        displayName = device.displayName
        ambientTemperatureCelsius = device.traits.temperature?.ambientTemperatureCelsius
        ambientHumidityPercent = device.traits.humidity?.ambientHumidityPercent
        connectionState = ThermostatConnectionState(sdmStatus: device.traits.connectivity?.status)
        mode = ThermostatOperatingMode(
            sdmMode: device.traits.thermostatMode?.normalizedMode,
            sdmEcoMode: device.traits.thermostatEco?.mode
        )
        hvacState = ThermostatHvacState(sdmStatus: device.traits.thermostatHvac?.status)
        setpoints = ThermostatSetpoints(
            coolCelsius: device.traits.thermostatTemperatureSetpoint?.coolCelsius,
            heatCelsius: device.traits.thermostatTemperatureSetpoint?.heatCelsius
        )
        eco = ecoState
        fan = ThermostatFanState(
            isTimerOn: (device.traits.fan?.timerMode ?? "OFF") == "ON",
            timerTimeout: device.traits.fan?.timerTimeout,
            isAvailable: device.traits.fan != nil
        )
        capabilities = ThermostatCapabilities(
            availableModes: device.traits.thermostatMode?.availableModes.map { ThermostatOperatingMode(commandValue: $0) } ?? [],
            supportsEco: ecoState.supportsManualEco,
            hasFan: device.traits.fan != nil
        )
    }
}

extension GoogleSDMThermostatDevice {
    var thermostatSnapshot: Thermostat {
        Thermostat(googleSDMDevice: self)
    }
}

struct EmptyResponse: Decodable {}
