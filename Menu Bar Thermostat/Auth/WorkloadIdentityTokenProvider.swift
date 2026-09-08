import Foundation
import Combine
import Alamofire

/// Exchanges Google's ID token for the service-account token used only by Pub/Sub.
/// Google token renewal stays owned by AppState so SDM and Pub/Sub cannot diverge.
final class WorkloadIdentityTokenProvider: ObservableObject {
    @Published private(set) var serviceAccountAccessToken = ""
    @Published private(set) var serviceAccountTokenExpiresAt: Date?
    var requestGoogleTokenRefresh: (() -> Void)?

    var isTokenValid: Bool {
        !serviceAccountAccessToken.isEmpty && (serviceAccountTokenExpiresAt?.timeIntervalSinceNow ?? 0) > 300
    }

    private let config: AppConfig
    private let session: Session
    private var refreshTimer: Timer?
    private var request: DataRequest?
    private var generation = UUID()
    private var isExchanging = false
    private(set) var retryDelay: TimeInterval = 5
    private(set) var nextRefreshDate: Date?

    init(config: AppConfig = .current, session: Session = AF) {
        self.config = config
        self.session = session
    }

    func start(idToken: String) {
        guard !isExchanging else { return }
        if retryDelay > 5, let nextRefreshDate, nextRefreshDate > Date() { return }
        guard !idToken.isEmpty else {
            scheduleRetry()
            return
        }
        guard !config.workloadIdentityAudience.isEmpty, !config.pubSubServiceAccountEmail.isEmpty else {
            AuthenticationDiagnostics.record("wif_configuration_missing")
            return
        }
        refreshTimer?.invalidate()
        nextRefreshDate = nil
        isExchanging = true
        let attempt = generation
        AuthenticationDiagnostics.record("wif_exchange_started")
        let params: Parameters = [
            "grant_type": "urn:ietf:params:oauth:grant-type:token-exchange",
            "audience": config.workloadIdentityAudience,
            "requested_token_type": "urn:ietf:params:oauth:token-type:access_token",
            "subject_token_type": "urn:ietf:params:oauth:token-type:id_token",
            "subject_token": idToken,
            "scope": "https://www.googleapis.com/auth/cloud-platform"
        ]
        request = session.request("https://sts.googleapis.com/v1/token", method: .post, parameters: params)
            .validate()
            .responseDecodable(of: STSResponse.self) { [weak self] response in
                guard let self, self.generation == attempt else { return }
                switch response.result {
                case .success(let sts):
                    self.impersonateServiceAccount(with: sts, generation: attempt)
                case .failure(let error):
                    self.exchangeFailed(stage: "sts", status: response.response?.statusCode, error: error)
                }
            }
    }

    func reset() {
        generation = UUID()
        request?.cancel()
        request = nil
        isExchanging = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        nextRefreshDate = nil
        retryDelay = 5
        serviceAccountTokenExpiresAt = nil
        serviceAccountAccessToken = ""
    }

    private func impersonateServiceAccount(with sts: STSResponse, generation attempt: UUID) {
        let url = "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/\(config.pubSubServiceAccountEmail):generateAccessToken"
        let headers: HTTPHeaders = ["Authorization": "Bearer \(sts.access_token)", "Content-Type": "application/json"]
        let body: [String: Any] = ["scope": ["https://www.googleapis.com/auth/cloud-platform"], "lifetime": "3600s"]
        request = session.request(url, method: .post, parameters: body, encoding: JSONEncoding.default, headers: headers)
            .validate()
            .responseDecodable(of: ImpersonationResponse.self) { [weak self] response in
                guard let self, self.generation == attempt else { return }
                switch response.result {
                case .success(let token):
                    let formatter = ISO8601DateFormatter()
                    let plainDate = formatter.date(from: token.expireTime)
                    formatter.formatOptions.insert(.withFractionalSeconds)
                    guard !token.accessToken.isEmpty,
                          let expiresAt = plainDate ?? formatter.date(from: token.expireTime),
                          expiresAt > Date() else {
                        self.exchangeFailed(stage: "iam_invalid_expiry", status: response.response?.statusCode, error: nil)
                        return
                    }
                    self.acceptServiceAccountToken(token.accessToken, expiresAt: expiresAt)
                case .failure(let error):
                    self.exchangeFailed(stage: "iam", status: response.response?.statusCode, error: error)
                }
            }
    }

    func acceptServiceAccountToken(_ token: String, expiresAt: Date) {
        request = nil
        isExchanging = false
        retryDelay = 5
        // Publish expiry before the token; listeners must see a consistent valid pair.
        serviceAccountTokenExpiresAt = expiresAt
        serviceAccountAccessToken = token
        AuthenticationDiagnostics.record("wif_exchange_succeeded")
        scheduleRefresh(in: max(1, expiresAt.timeIntervalSinceNow - 300))
    }

    private func exchangeFailed(stage: String, status: Int?, error: Error?) {
        request = nil
        isExchanging = false
        AuthenticationDiagnostics.record("wif_\(stage)_failed http_status=\(status ?? 0)", error: error)
        // WIF/IAM failures must never erase the user's Nest authorization.
        scheduleRetry()
    }

    private func scheduleRetry() {
        let delay = retryDelay
        retryDelay = min(delay * 2, 60)
        scheduleRefresh(in: delay)
    }

    private func scheduleRefresh(in delay: TimeInterval) {
        refreshTimer?.invalidate()
        nextRefreshDate = Date().addingTimeInterval(delay)
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.nextRefreshDate = nil
            self.requestGoogleTokenRefresh?()
        }
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        AuthenticationDiagnostics.record("wif_refresh_scheduled delay_seconds=\(Int(ceil(delay)))")
    }

    deinit {
        request?.cancel()
        refreshTimer?.invalidate()
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
