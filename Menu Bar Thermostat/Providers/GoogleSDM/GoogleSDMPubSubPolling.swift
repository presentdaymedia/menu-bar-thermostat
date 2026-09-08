import Foundation
import Alamofire

extension AppState {
    func startPubSubPolling() {
        guard !sdmAccessToken.isEmpty, !authenticationStatus.isRecovering, let _ = pubSubSubscriptionResourceName, !pubSubAccessToken.isEmpty else {
            print("Cannot start Pub/Sub polling: Missing subscription or access token")
            return
        }
        guard !isPubSubActive else {
            print("Pub/Sub polling already active")
            return
        }

        print("Starting Pub/Sub long polling")
        isPubSubActive = true
        pubSubPollingTask = Task { [weak self] in
            await self?.runPubSubPollingLoop()
        }
    }

    func stopPubSubPolling(shouldRestartPolling: Bool = true) {
        isPubSubActive = false
        pubSubPollingTask?.cancel()
        pubSubPollingTask = nil
        print("Pub/Sub polling stopped")

        if shouldRestartPolling {
            scheduleDevicePolling()
        }
    }

    func cancelPubSubSetup() {
        scheduledPubSubRetry?.cancel()
        scheduledPubSubRetry = nil
        pubSubSubscriptionSetupTask?.cancel()
        pubSubSubscriptionSetupTask = nil
    }

    @MainActor
    private func runPubSubPollingLoop() async {
        while isPubSubActive && !sdmAccessToken.isEmpty && !pubSubAccessToken.isEmpty {
            do {
                guard isPubSubActive else { break }
                let success = await pullPubSubMessages()
                if success {
                    pubSubBackoffDelay = 1.0
                    consecutiveAuthFailures = 0
                } else {
                    await handlePubSubError()
                }

                if isPubSubActive {
                    try await Task.sleep(nanoseconds: UInt64(1.0 * 1_000_000_000))
                }
            } catch {
                if error is CancellationError {
                    print("Pub/Sub polling cancelled")
                    break
                } else {
                    print("Unexpected error in continuous polling: \(error)")
                    await handlePubSubError()
                }
            }
        }

        print("Continuous long polling ended")
    }

    private func handlePubSubError() async {
        guard let last = latestPubSubError else { return }

        switch last {
        case .networkError, .decodingError:
            consecutiveNetworkFailures += 1

            if consecutiveNetworkFailures >= 2 {
                await MainActor.run {
                    self.pollManager.recordPubSubFailure()
                    self.scheduleDevicePolling()
                }
            }

            pubSubBackoffDelay = min(pubSubBackoffDelay * 2, 16.0)
            let jitter = Double.random(in: 0...(pubSubBackoffDelay * 0.2))
            let delay = pubSubBackoffDelay + jitter
            print("Transient Pub/Sub network error – backing off for \(String(format: "%.2f", delay))s")
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        case .authenticationFailure:
            await MainActor.run {
                self.pollManager.recordPubSubFailure()
                self.scheduleDevicePolling()
            }

        default:
            await MainActor.run {
                self.isPubSubActive = false
                self.pollManager.recordPubSubFailure()
                self.scheduleDevicePolling()
            }

            pubSubBackoffDelay = min(pubSubBackoffDelay * 2, 16.0)
            print("Backing off for \(pubSubBackoffDelay) seconds after error (non-transient)")
            try? await Task.sleep(nanoseconds: UInt64(pubSubBackoffDelay * 1_000_000_000))
        }
    }

    func pullPubSubMessages() async -> Bool {
        guard !sdmAccessToken.isEmpty, let subscription = pubSubSubscriptionResourceName, !pubSubAccessToken.isEmpty else {
            print("Skipping Pub/Sub pull: No subscription or access token")
            return false
        }

        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(pubSubAccessToken)",
            "Content-Type": "application/json"
        ]

        let url = "https://pubsub.googleapis.com/v1/\(subscription):pull"
        let parameters: [String: Any] = [
            "maxMessages": 50
        ]

        print("Long polling Pub/Sub messages from \(subscription)")

        return await withCheckedContinuation { continuation in
            httpSession.request(url, method: .post, parameters: parameters, encoding: JSONEncoding.default, headers: headers)
                .validate()
                .responseDecodable(of: PubSubResponse.self) { [weak self] response in
                    guard let self = self else {
                        continuation.resume(returning: false)
                        return
                    }

                    switch response.result {
                    case .success(let pubSubResponse):
                        if let receivedMessages = pubSubResponse.receivedMessages, !receivedMessages.isEmpty {
                            print("Received \(receivedMessages.count) Pub/Sub messages via long polling")
                            Task { @MainActor in
                                self.handlePubSubMessages(receivedMessages)
                            }
                            // Acknowledge messages after processing
                            // The new handlePubSubMessages handles its own acks, so this line is removed.
                            // self.acknowledgePubSubMessageIDs(ackIds)
                        } else {
                            print("Long polling completed with no messages")
                        }
                        continuation.resume(returning: true)
                        self.latestPubSubError = nil
                        self.consecutiveNetworkFailures = 0

                    case .failure(let error):
                        self.handlePubSubFailure(error: error, response: response)
                        continuation.resume(returning: false)
                    }
                }
        }
    }

    private func handlePubSubFailure(error: AFError, response: DataResponse<PubSubResponse, AFError>) {
        var pubSubError: PubSubError

        if let afError = error.asAFError {
            switch afError {
            case .responseValidationFailed(let reason):
                if case .unacceptableStatusCode(let code) = reason, code == 404 {
                    pubSubError = .subscriptionNotExists
                } else if case .unacceptableStatusCode(let code) = reason, code == 401 {
                    pubSubError = .authenticationFailure
                } else if case .unacceptableStatusCode(let code) = reason, code == 403 {
                    pubSubError = .permissionDenied
                    AuthenticationDiagnostics.record("pubsub_permission_denied http_status=403")
                } else {
                    pubSubError = .invalidResponse
                }
            case .responseSerializationFailed:
                pubSubError = .decodingError(error)
            default:
                pubSubError = .networkError(error)
            }
        } else {
            pubSubError = .networkError(error)
        }

        self.latestPubSubError = pubSubError
        print("Pub/Sub error: \(pubSubError.description)")

        if let data = response.data, let responseString = String(data: data, encoding: .utf8) {
            print("Response Data: \(responseString)")

            if responseString.contains("UNAUTHENTICATED") || responseString.contains("PERMISSION_DENIED") {
                print("Authentication issue detected with Pub/Sub, refreshing token may be needed")
                if responseString.contains("ACCESS_TOKEN_SCOPE_INSUFFICIENT") {
                    print("Pub/Sub service-account scope is insufficient. Check Workload Identity configuration.")
                }
            }

            if responseString.contains("Requested project not found") {
                print("ERROR: The Google Cloud Project ID might be incorrect. Check your Google Cloud Console for the correct project ID.")
            }

        }

        if case .subscriptionNotExists = pubSubError {
            let subscriptionId = pubSubSubscriptionResourceName?.components(separatedBy: "/").last
            print("Stopping Pub/Sub due to missing subscription")
            self.stopPubSubPolling()
            self.pubSubSubscriptionResourceName = nil
            if let subscriptionId {
                print("Subscription not found, attempting to create it")
                self.createPubSubSubscription(topicName: self.pubSubTopicResourceName, subscriptionId: subscriptionId)
            }
        } else if case .authenticationFailure = pubSubError {
            self.refreshTokenIfNeeded(force: true)
            self.consecutiveAuthFailures += 1
            print("Authentication failure \(self.consecutiveAuthFailures)/5")
            if self.consecutiveAuthFailures >= 5 {
                print("Stopping Pub/Sub after consecutive authentication failures")
                self.stopPubSubPolling()
                self.pubSubSubscriptionResourceName = nil
            }
        }
    }
}
