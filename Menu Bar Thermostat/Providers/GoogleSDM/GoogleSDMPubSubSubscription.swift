import Foundation
import Alamofire
import AppKit

private enum PubSubResourceStatus {
    case exists
    case missing
    case authorizationFailed
    case failed
}

private struct PubSubHTTPResult {
    let statusCode: Int?
    let data: Data?
    let error: AFError?
}

extension AppState {
    func ensurePubSubSubscription(sessionGeneration: Int? = nil) {
        let generation = sessionGeneration ?? authSessionVersion
        pubSubSubscriptionSetupTask?.cancel()
        pubSubSubscriptionSetupTask = Task { @MainActor [weak self] in
            guard let self, self.isCurrentAuthSession(generation) else { return }

            let topicStatus = await self.validatePubSubTopicWithRetry()
            guard !Task.isCancelled, self.isCurrentAuthSession(generation) else {
                self.pubSubSubscriptionSetupTask = nil
                return
            }

            guard topicStatus == .exists else {
                self.pubSubSubscriptionSetupTask = nil
                self.pollManager.recordPubSubFailure()
                self.scheduleDevicePolling()

                if topicStatus == .missing, !self.pubSubAccessToken.isEmpty {
                    self.presentAlert(message: "Could not find the Pub/Sub topic '\(self.pubSubTopicID)' in Google Cloud project '\(self.pubSubGoogleCloudProjectID)'. Please check your Google Device Access configuration and topic name in Settings.")
                } else if topicStatus == .authorizationFailed {
                    print("ensurePubSubSubscription: Pub/Sub topic validation failed due to authorization. Falling back to device polling.")
                } else {
                    print("ensurePubSubSubscription: Pub/Sub topic validation failed. Falling back to device polling.")
                }
                return
            }

            let subscriptionId = UserDefaults.standard.string(forKey: "menuBarThermostatSubscriptionId") ?? "menu-bar-thermostat-device-events-\(UUID().uuidString.prefix(8))"
            UserDefaults.standard.set(subscriptionId, forKey: "menuBarThermostatSubscriptionId")

            if self.pubSubSubscriptionResourceName != nil {
                self.stopPubSubPolling(shouldRestartPolling: false)
            }

            let subscriptionIsReady = await self.ensurePubSubSubscriptionExists(subscriptionId: subscriptionId)
            guard !Task.isCancelled, self.isCurrentAuthSession(generation) else {
                self.pubSubSubscriptionSetupTask = nil
                return
            }

            guard subscriptionIsReady else {
                self.pubSubSubscriptionSetupTask = nil
                self.pollManager.recordPubSubFailure()
                self.scheduleDevicePolling()
                print("ensurePubSubSubscription: Subscription setup failed. Falling back to device polling.")
                return
            }

            self.pubSubSubscriptionSetupTask = nil
            print("Pub/Sub subscription set to: \(self.pubSubSubscriptionResourceName ?? "none")")
            self.startPubSubPolling()
            self.primeDeviceAccessEvents()
        }
    }

    private func presentAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func validatePubSubTopic() async -> PubSubResourceStatus {
        if let workloadIdentityProvider = workloadIdentityProvider, workloadIdentityProvider.serviceAccountAccessToken.isEmpty {
            print("validatePubSubTopic: SA token not ready yet - waiting briefly...")
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        guard !pubSubAccessToken.isEmpty else {
            print("validatePubSubTopic: Missing service-account token - skipping check")
            return .failed
        }

        if hasValidatedPubSubTopic { return .exists }

        let url = "https://pubsub.googleapis.com/v1/\(pubSubTopicResourceName)"
        let result = await pubSubDataRequest(url: url, headers: pubSubHeaders)
        let status = result.statusCode ?? -1
        print("validatePubSubTopic: Response status: \(status)")

        if let data = result.data, let responseString = String(data: data, encoding: .utf8) {
            print("validatePubSubTopic: Response body: \(responseString)")
        }

        switch status {
        case 200...299:
            print("validatePubSubTopic: Topic validation successful")
            hasValidatedPubSubTopic = true
            return .exists
        case 404:
            print("validatePubSubTopic: Topic returned 404 - treating as missing topic")
            return .missing
        case 401, 403:
            print("validatePubSubTopic: Auth error (status \(status)). Will refresh token and retry later.")
            refreshTokenIfNeeded(force: true)
            return .authorizationFailed
        default:
            if let error = result.error {
                print("validatePubSubTopic: Request failed - \(error.localizedDescription)")
            } else {
                print("validatePubSubTopic: Unexpected status \(status)")
            }
            return .failed
        }
    }

    private func validatePubSubTopicWithRetry(maxAttempts: Int = 3) async -> PubSubResourceStatus {
        if hasValidatedPubSubTopic {
            return .exists
        }

        var latestStatus: PubSubResourceStatus = .failed
        for attempt in 1...maxAttempts {
            let status = await validatePubSubTopic()
            latestStatus = status
            if status == .exists || status == .missing || status == .authorizationFailed {
                return status
            }

            if attempt < maxAttempts {
                let delay = pow(2.0, Double(attempt - 1))
                print("validatePubSubTopicWithRetry: attempt \(attempt) failed - retrying in \(delay)s")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        return latestStatus
    }

    func ensurePubSubSubscriptionExists(subscriptionId: String) async -> Bool {
        guard !pubSubAccessToken.isEmpty else {
            print("ensurePubSubSubscriptionExists: Missing service-account token")
            return false
        }

        let subscriptionResourceName = pubSubSubscriptionResourceName(for: subscriptionId)
        let url = "https://pubsub.googleapis.com/v1/\(subscriptionResourceName)"
        let result = await pubSubDataRequest(url: url, headers: pubSubHeaders)
        let status = result.statusCode ?? -1

        switch status {
        case 200...299:
            self.pubSubSubscriptionResourceName = subscriptionResourceName
            print("ensurePubSubSubscriptionExists: Subscription already exists")
            return true
        case 404:
            print("ensurePubSubSubscriptionExists: Subscription missing; creating")
            return await createPubSubSubscriptionIfNeeded(topicName: pubSubTopicResourceName, subscriptionId: subscriptionId)
        case 401, 403:
            print("ensurePubSubSubscriptionExists: Auth error (status \(status)). Will refresh token and retry later.")
            refreshTokenIfNeeded(force: true)
            return false
        default:
            if let data = result.data, let responseString = String(data: data, encoding: .utf8) {
                print("ensurePubSubSubscriptionExists: Response body - \(responseString)")
            }
            if let error = result.error {
                print("ensurePubSubSubscriptionExists: Request failed - \(error.localizedDescription)")
            } else {
                print("ensurePubSubSubscriptionExists: Unexpected status \(status)")
            }
            return false
        }
    }

    func createPubSubSubscription(topicName: String, subscriptionId: String) {
        Task { @MainActor in
            let created = await createPubSubSubscriptionIfNeeded(topicName: topicName, subscriptionId: subscriptionId)
            if created, !self.sdmAccessToken.isEmpty {
                self.startPubSubSyncIfNeeded()
            }
        }
    }

    private func createPubSubSubscriptionIfNeeded(topicName: String, subscriptionId: String) async -> Bool {
        guard !pubSubAccessToken.isEmpty else {
            print("createPubSubSubscription: Missing service-account token")
            return false
        }

        let subscriptionResourceName = pubSubSubscriptionResourceName(for: subscriptionId)
        let url = "https://pubsub.googleapis.com/v1/\(subscriptionResourceName)"
        let body: [String: Any] = [
            "topic": topicName,
            "ackDeadlineSeconds": 20
        ]

        let result = await pubSubDataRequest(
            url: url,
            method: .put,
            parameters: body,
            encoding: JSONEncoding.default,
            headers: pubSubHeaders
        )
        let status = result.statusCode ?? -1

        switch status {
        case 200...299, 409:
            print("createPubSubSubscription: Subscription ready")
            self.hasValidatedPubSubTopic = true
            self.pubSubSubscriptionResourceName = subscriptionResourceName
            return true
        default:
            print("createPubSubSubscription: Failed to create subscription - status \(status)")
            if let data = result.data, let string = String(data: data, encoding: .utf8) {
                print("createPubSubSubscription: Response body - \(string)")
            }
            if let error = result.error {
                print("createPubSubSubscription: Request failed - \(error.localizedDescription)")
            }
            return false
        }
    }

    private var pubSubGoogleCloudProjectID: String {
        if let envProjectID = ProcessInfo.processInfo.environment["GOOGLE_CLOUD_PROJECT_ID"], !envProjectID.isEmpty {
            return envProjectID
        }
        return AppConfig.current.pubSubGoogleCloudProjectID
    }

    var pubSubTopicResourceName: String {
        return "projects/\(pubSubGoogleCloudProjectID)/topics/\(pubSubTopicID)"
    }

    private var pubSubTopicID: String {
        if !customPubSubTopicID.isEmpty {
            return customPubSubTopicID
        }
        if let envTopic = ProcessInfo.processInfo.environment["PUBSUB_TOPIC_NAME"], !envTopic.isEmpty {
            return envTopic
        }
        return AppConfig.current.pubSubTopicID
    }

    private var pubSubHeaders: HTTPHeaders {
        [
            "Authorization": "Bearer \(pubSubAccessToken)",
            "Content-Type": "application/json"
        ]
    }

    private func pubSubSubscriptionResourceName(for subscriptionId: String) -> String {
        "projects/\(pubSubGoogleCloudProjectID)/subscriptions/\(subscriptionId)"
    }

    private func pubSubDataRequest(
        url: String,
        method: HTTPMethod = .get,
        parameters: Parameters? = nil,
        encoding: ParameterEncoding = URLEncoding.default,
        headers: HTTPHeaders
    ) async -> PubSubHTTPResult {
        await withCheckedContinuation { continuation in
            httpSession.request(url, method: method, parameters: parameters, encoding: encoding, headers: headers)
                .responseData { response in
                    continuation.resume(
                        returning: PubSubHTTPResult(
                            statusCode: response.response?.statusCode,
                            data: response.data,
                            error: response.error
                        )
                    )
                }
        }
    }
}
