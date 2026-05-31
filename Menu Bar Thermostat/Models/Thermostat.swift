import Foundation

enum ThermostatOperatingMode: Equatable {
    case off
    case heat
    case cool
    case heatCool
    case eco
    case unknown(String)

    init(commandValue: String?) {
        switch commandValue {
        case "OFF":
            self = .off
        case "HEAT":
            self = .heat
        case "COOL":
            self = .cool
        case "HEATCOOL":
            self = .heatCool
        case "ECO":
            self = .eco
        case let value?:
            self = .unknown(value)
        case nil:
            self = .off
        }
    }

    var commandValue: String {
        switch self {
        case .off:
            return "OFF"
        case .heat:
            return "HEAT"
        case .cool:
            return "COOL"
        case .heatCool:
            return "HEATCOOL"
        case .eco:
            return "ECO"
        case .unknown(let value):
            return value
        }
    }

    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .heat:
            return "Heat"
        case .cool:
            return "Cool"
        case .heatCool:
            return "Heat-Cool"
        case .eco:
            return "Eco"
        case .unknown(let value):
            return value
        }
    }
}

enum ThermostatHvacState: Equatable {
    case off
    case heating
    case cooling
    case unknown(String?)

    var commandValue: String {
        switch self {
        case .off:
            return "OFF"
        case .heating:
            return "HEATING"
        case .cooling:
            return "COOLING"
        case .unknown(let value):
            return value ?? "UNKNOWN"
        }
    }

    var isRunning: Bool {
        self == .heating || self == .cooling
    }
}

enum ThermostatConnectionState: Equatable {
    case online
    case offline
    case unknown
    case other(String)
}

struct ThermostatSetpoints: Equatable {
    var coolCelsius: Double?
    var heatCelsius: Double?
}

struct ThermostatEcoState: Equatable {
    var availableModes: [String]
    var coolCelsius: Double?
    var heatCelsius: Double?
    var mode: String?

    var isActive: Bool {
        mode == "MANUAL_ECO"
    }

    var supportsManualEco: Bool {
        availableModes.contains("MANUAL_ECO") || isActive
    }
}

struct ThermostatFanState: Equatable {
    var isTimerOn: Bool
    var timerTimeout: String?
    var isAvailable: Bool
}

struct ThermostatCapabilities: Equatable {
    var availableModes: [ThermostatOperatingMode]
    var supportsEco: Bool
    var hasFan: Bool
}

struct Thermostat: Identifiable, Equatable {
    var id: String
    var displayName: String
    var ambientTemperatureCelsius: Double?
    var ambientHumidityPercent: Int?
    var connectionState: ThermostatConnectionState
    var mode: ThermostatOperatingMode
    var hvacState: ThermostatHvacState
    var setpoints: ThermostatSetpoints
    var eco: ThermostatEcoState
    var fan: ThermostatFanState
    var capabilities: ThermostatCapabilities
}

struct ThermostatLocation: Identifiable, Equatable {
    var id: String
    var displayName: String
}

protocol ThermostatProvider {
    var displayName: String { get }

    func loadLocations(completion: @escaping (Result<[ThermostatLocation], Error>) -> Void)
    func loadThermostats(completion: @escaping (Result<[Thermostat], Error>) -> Void)
    func loadThermostatSnapshot(id: String, completion: @escaping (Result<Thermostat, Error>) -> Void)

    func setMode(thermostatID: String, mode: ThermostatOperatingMode, completion: @escaping (Bool) -> Void)
    func setSetpoints(thermostatID: String, coolCelsius: Double?, heatCelsius: Double?, completion: @escaping (Bool) -> Void)
    func setEcoMode(thermostatID: String, enabled: Bool, completion: @escaping (Bool) -> Void)
    func setEcoTemperature(thermostatID: String, coolCelsius: Double?, heatCelsius: Double?, completion: @escaping (Bool) -> Void)
    func setFanTimer(thermostatID: String, duration: TimeInterval, completion: @escaping (Bool) -> Void)
    func turnOffFan(thermostatID: String, completion: @escaping (Bool) -> Void)
}
