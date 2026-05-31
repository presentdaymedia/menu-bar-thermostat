enum ThermostatModeDisplay {
    static func name(for mode: String) -> String {
        switch mode {
        case "COOL":
            return "Cool"
        case "HEAT":
            return "Heat"
        case "OFF":
            return "Off"
        case "HEATCOOL":
            return "Heat·Cool"
        case "ECO":
            return "Eco"
        default:
            return mode
        }
    }
}
