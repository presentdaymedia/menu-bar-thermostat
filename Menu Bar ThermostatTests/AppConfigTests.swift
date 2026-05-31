import XCTest

final class AppConfigTests: XCTestCase {
    func testEnvironmentValuesOverrideLocalAndExampleConfig() {
        let config = AppConfig.load(
            environment: configValues(prefix: "env"),
            localValues: configValues(prefix: "local"),
            exampleValues: configValues(prefix: "example")
        )

        XCTAssertEqual(config.deviceAccessEnterpriseID, "env-enterprise")
        XCTAssertEqual(config.pubSubGoogleCloudProjectID, "env-cloud-project")
        XCTAssertEqual(config.pubSubTopicID, "env-topic")
        XCTAssertEqual(config.workloadIdentityAudience, "env-audience")
        XCTAssertEqual(config.pubSubServiceAccountEmail, "env-service-account")
    }

    func testLocalValuesOverrideExampleConfigWhenEnvironmentIsEmpty() {
        let config = AppConfig.load(
            environment: emptyConfigValues(),
            localValues: configValues(prefix: "local"),
            exampleValues: configValues(prefix: "example")
        )

        XCTAssertEqual(config.deviceAccessEnterpriseID, "local-enterprise")
        XCTAssertEqual(config.pubSubGoogleCloudProjectID, "local-cloud-project")
        XCTAssertEqual(config.pubSubTopicID, "local-topic")
        XCTAssertEqual(config.workloadIdentityAudience, "local-audience")
        XCTAssertEqual(config.pubSubServiceAccountEmail, "local-service-account")
    }

    func testExampleValuesAreUsedWhenEnvironmentAndLocalConfigAreMissing() {
        let config = AppConfig.load(
            environment: [:],
            localValues: [:],
            exampleValues: configValues(prefix: "example")
        )

        XCTAssertEqual(config.deviceAccessEnterpriseID, "example-enterprise")
        XCTAssertEqual(config.pubSubGoogleCloudProjectID, "example-cloud-project")
        XCTAssertEqual(config.pubSubTopicID, "example-topic")
        XCTAssertEqual(config.workloadIdentityAudience, "example-audience")
        XCTAssertEqual(config.pubSubServiceAccountEmail, "example-service-account")
    }

    func testMissingValuesResolveToEmptyStrings() {
        let config = AppConfig.load(
            environment: [:],
            localValues: [:],
            exampleValues: [:]
        )

        XCTAssertEqual(config.deviceAccessEnterpriseID, "")
        XCTAssertEqual(config.pubSubGoogleCloudProjectID, "")
        XCTAssertEqual(config.pubSubTopicID, "")
        XCTAssertEqual(config.workloadIdentityAudience, "")
        XCTAssertEqual(config.pubSubServiceAccountEmail, "")
    }

    private func configValues(prefix: String) -> [String: String] {
        [
            "DEVICE_ACCESS_ENTERPRISE_ID": "\(prefix)-enterprise",
            "PUBSUB_GOOGLE_CLOUD_PROJECT_ID": "\(prefix)-cloud-project",
            "PUBSUB_TOPIC_ID": "\(prefix)-topic",
            "WORKLOAD_IDENTITY_AUDIENCE": "\(prefix)-audience",
            "PUBSUB_SERVICE_ACCOUNT_EMAIL": "\(prefix)-service-account"
        ]
    }

    private func emptyConfigValues() -> [String: String] {
        [
            "DEVICE_ACCESS_ENTERPRISE_ID": "",
            "PUBSUB_GOOGLE_CLOUD_PROJECT_ID": "",
            "PUBSUB_TOPIC_ID": "",
            "WORKLOAD_IDENTITY_AUDIENCE": "",
            "PUBSUB_SERVICE_ACCOUNT_EMAIL": ""
        ]
    }
}
