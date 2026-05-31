import Foundation
import Combine
import Alamofire
import GoogleSignIn

/// Exchanges the Google ID-token received from `GIDSignIn` for a short-lived service-account
/// access-token via Workload-Identity Federation (STS).
final class WorkloadIdentityTokenProvider: ObservableObject {
    /// Published token your Pub/Sub helpers should add as `Authorization: Bearer …`.
    @Published private(set) var serviceAccountAccessToken: String = ""
    
    /// Expiration time of the service account access token.
    @Published private(set) var serviceAccountTokenExpiresAt: Date?
    
    /// Returns true if the service account token is non-empty and not expired (with 5 min buffer).
    var isTokenValid: Bool {
        guard !serviceAccountAccessToken.isEmpty else { return false }
        guard let expiresAt = serviceAccountTokenExpiresAt else { return false }
        return expiresAt.timeIntervalSinceNow > 300 // 5 minute buffer
    }

    private let config: AppConfig
    private let session: Session

    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(config: AppConfig = .current, session: Session = AF) {
        self.config = config
        self.session = session
    }

    /// Call this right after Google Sign-In succeeds.
    /// - Parameter idToken: `user.idToken?.tokenString` from GIDSignIn.
    func start(idToken: String) {
        guard !idToken.isEmpty else { 
            print("🚨 Workload Identity: Empty ID-token provided, cannot proceed with token exchange")
            return 
        }
        guard !config.workloadIdentityAudience.isEmpty,
              !config.pubSubServiceAccountEmail.isEmpty else {
            print("Workload Identity: Missing WORKLOAD_IDENTITY_AUDIENCE or PUBSUB_SERVICE_ACCOUNT_EMAIL in AppConfig.local.plist")
            return
        }
        
        print("🔄 Workload Identity: Starting token exchange process")
        print("📝 Workload Identity: ID-token preview: \(redactedToken(idToken))")
        print("🎯 Workload Identity: Using audience: \(config.workloadIdentityAudience)")
        
        // Decode and log some ID-token details for debugging
        if let payload = decodeJWTPayload(idToken) {
            print("📋 Workload Identity: ID-token details:")
            print("   • Issuer: \(payload["iss"] as? String ?? "unknown")")
            print("   • Audience: \(payload["aud"] as? String ?? "unknown")")
            print("   • Subject: \(payload["sub"] as? String ?? "unknown")")
            if let email = payload["email"] as? String {
                print("   • Email: \(redactedEmail(email))")
            }
            if let exp = payload["exp"] as? Int {
                let expDate = Date(timeIntervalSince1970: TimeInterval(exp))
                print("   • Expires: \(expDate)")
            }
        }
        
        // Clear any existing Combine pipelines before starting a new exchange to avoid memory-leaks and duplicate work
        cancellables.removeAll()
        exchange(idToken: idToken)
    }

    func reset() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        cancellables.removeAll()
        serviceAccountAccessToken = ""
        serviceAccountTokenExpiresAt = nil
    }

    // MARK: – Private helpers

    private func exchange(idToken: String) {
        print("🔄 Workload Identity: Preparing STS token exchange request")
        
        let params: Parameters = [
            "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
            "audience": config.workloadIdentityAudience,
            "requested_token_type": "urn:ietf:params:oauth:token-type:access_token",
            "subject_token_type": "urn:ietf:params:oauth:token-type:id_token",
            "subject_token": idToken,
            "scope": "https://www.googleapis.com/auth/cloud-platform"
        ]

        print("📤 Workload Identity: Sending STS request to https://sts.googleapis.com/v1/token")
        print("📋 Workload Identity: Request parameters:")
        print("   • grant_type: \(params["grant_type"] as? String ?? "")")
        print("   • audience: \(params["audience"] as? String ?? "")")
        print("   • requested_token_type: \(params["requested_token_type"] as? String ?? "")")
        print("   • subject_token_type: \(params["subject_token_type"] as? String ?? "")")
        print("   • scope: \(params["scope"] as? String ?? "")")
        print("   • subject_token: \(redactedToken(idToken))")

        session.request("https://sts.googleapis.com/v1/token", method: .post, parameters: params)
            .validate()
            .responseData { response in
                if let statusCode = response.response?.statusCode {
                    print("📥 Workload Identity: STS response received (status: \(statusCode))")
                } else {
                    print("📥 Workload Identity: STS response received without HTTP status (connection not established)")
                }
                if let dataSize = response.data?.count {
                    print("   • Payload size: \(dataSize) bytes")
                }
                
                if let error = response.error {
                    print("🚨 Workload Identity: Request failed with error: \(error)")
                    print("   • Error description: \(error.localizedDescription)")
                    if let underlyingError = error.underlyingError {
                        print("   • Underlying error: \(underlyingError)")
                    }
                }
            }
            .publishDecodable(type: STSResponse.self)
            .compactMap { response in
                if let error = response.error {
                    print("🚨 Workload Identity: Failed to decode STS response: \(error)")
                }
                return response.value
            }
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        print("✅ Workload Identity: STS token decoded successfully")
                    case .failure(let error):
                        print("🚨 Workload Identity: Token exchange failed: \(error)")
                    }
                },
                receiveValue: { [weak self] sts in
                    print("🔐 Workload Identity: STS token preview \(redactedToken(sts.access_token)) (expires in \(sts.expires_in)s)")
                    self?.impersonateServiceAccount(with: sts)
                }
            )
            .store(in: &cancellables)
    }

    private func impersonateServiceAccount(with sts: STSResponse) {
        let url = "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/\(config.pubSubServiceAccountEmail):generateAccessToken"
        let body: [String: Any] = [
            "scope": ["https://www.googleapis.com/auth/cloud-platform"],
            "lifetime": "3600s"
        ]

        print("🔄 Workload Identity: Impersonating service account to obtain final access token")

        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(sts.access_token)",
            "Content-Type": "application/json"
        ]

        session.request(url, method: .post, parameters: body, encoding: JSONEncoding.default, headers: headers)
            .validate()
            .responseDecodable(of: ImpersonationResponse.self) { [weak self] response in
                if let statusCode = response.response?.statusCode {
                    print("📥 Workload Identity: IAMCredentials response status: \(statusCode)")
                } else {
                    print("📥 Workload Identity: IAMCredentials completed without HTTP response (connection issue)")
                }
                if let dataSize = response.data?.count {
                    print("   • Payload size: \(dataSize) bytes")
                }

                switch response.result {
                case .success(let impersonation):
                    print("🎉 Workload Identity: Received service account access token (\(redactedToken(impersonation.accessToken)))")
                    self?.serviceAccountAccessToken = impersonation.accessToken

                    // Calculate expiry: pick 55 min to be safe if parse fails
                    var refreshInterval: TimeInterval = 3300
                    if let expDate = ISO8601DateFormatter().date(from: impersonation.expireTime) {
                        self?.serviceAccountTokenExpiresAt = expDate
                        refreshInterval = expDate.timeIntervalSinceNow - 300
                    } else {
                        // Fallback: assume 1 hour from now
                        self?.serviceAccountTokenExpiresAt = Date().addingTimeInterval(3600)
                    }
                    self?.scheduleRefresh(in: max(300, refreshInterval))
                case .failure(let error):
                    print("🚨 Workload Identity: Failed to impersonate service account: \(error)")
                }
            }
    }

    private func scheduleRefresh(in delay: TimeInterval) {
        print("⏰ Workload Identity: Scheduling token refresh in \(delay) seconds")
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: max(30, delay), repeats: false) { [weak self] _ in
            guard let self = self else { return }
            print("🔄 Workload Identity: Token refresh timer triggered")
            
            // We need a fresh ID-token. Refresh the Google tokens first to ensure ID token is valid.
            guard let user = GIDSignIn.sharedInstance.currentUser else {
                print("🚨 Workload Identity: No current user available for refresh")
                return
            }
            
            user.refreshTokensIfNeeded { user, error in
                if let error = error {
                    print("🚨 Workload Identity: Failed to refresh Google tokens: \(error.localizedDescription)")
                    return
                }
                
                guard let user = user, let idToken = user.idToken?.tokenString else {
                    print("🚨 Workload Identity: No ID-token available after refresh")
                    return
                }
                
                print("✅ Workload Identity: Got fresh ID-token for refresh")
                self.exchange(idToken: idToken)
            }
        }
    }
    
    private func decodeJWTPayload(_ jwt: String) -> [String: Any]? {
        let segments = jwt.components(separatedBy: ".")
        guard segments.count == 3 else { return nil }
        
        let payloadSegment = segments[1]
        // Add padding if necessary
        var paddedPayload = payloadSegment
        let remainder = paddedPayload.count % 4
        if remainder > 0 {
            paddedPayload += String(repeating: "=", count: 4 - remainder)
        }
        
        guard let data = Data(base64Encoded: paddedPayload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        return json
    }
}

private struct STSResponse: Decodable {
    let access_token: String
    let expires_in: Int
}

private struct ImpersonationResponse: Decodable {
    let accessToken: String
    let expireTime: String
} 
