import Foundation

struct AppConfig {
    let deviceAccessEnterpriseID: String
    let pubSubGoogleCloudProjectID: String
    let pubSubTopicID: String
    let workloadIdentityAudience: String
    let pubSubServiceAccountEmail: String

    static let current = AppConfig.load()

    static func load(bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) -> AppConfig {
        let localValues = loadPlist(named: "AppConfig.local", bundle: bundle)
        let exampleValues = loadPlist(named: "AppConfig.example", bundle: bundle)

        return load(environment: environment, localValues: localValues, exampleValues: exampleValues)
    }

    static func load(
        environment: [String: String],
        localValues: [String: String],
        exampleValues: [String: String]
    ) -> AppConfig {
        func value(_ key: Key) -> String {
            if let envValue = environment[key.rawValue], !envValue.isEmpty {
                return envValue
            }
            if let localValue = localValues[key.rawValue], !localValue.isEmpty {
                return localValue
            }
            if let exampleValue = exampleValues[key.rawValue], !exampleValue.isEmpty {
                return exampleValue
            }
            return ""
        }

        return AppConfig(
            deviceAccessEnterpriseID: value(.deviceAccessEnterpriseID),
            pubSubGoogleCloudProjectID: value(.pubSubGoogleCloudProjectID),
            pubSubTopicID: value(.pubSubTopicID),
            workloadIdentityAudience: value(.workloadIdentityAudience),
            pubSubServiceAccountEmail: value(.pubSubServiceAccountEmail)
        )
    }

    private static func loadPlist(named name: String, bundle: Bundle) -> [String: String] {
        guard let url = bundle.url(forResource: name, withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else {
            return [:]
        }
        return plist
    }

    private enum Key: String {
        case deviceAccessEnterpriseID = "DEVICE_ACCESS_ENTERPRISE_ID"
        case pubSubGoogleCloudProjectID = "PUBSUB_GOOGLE_CLOUD_PROJECT_ID"
        case pubSubTopicID = "PUBSUB_TOPIC_ID"
        case workloadIdentityAudience = "WORKLOAD_IDENTITY_AUDIENCE"
        case pubSubServiceAccountEmail = "PUBSUB_SERVICE_ACCOUNT_EMAIL"
    }
}
