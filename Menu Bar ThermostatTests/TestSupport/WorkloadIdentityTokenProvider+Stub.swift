import Foundation
import Combine

final class WorkloadIdentityTokenProvider: ObservableObject {
    @Published private(set) var serviceAccountAccessToken: String = ""
    @Published private(set) var serviceAccountTokenExpiresAt: Date?

    var isTokenValid: Bool {
        guard !serviceAccountAccessToken.isEmpty else { return false }
        guard let serviceAccountTokenExpiresAt else { return false }
        return serviceAccountTokenExpiresAt.timeIntervalSinceNow > 300
    }

    func start(idToken: String) {}
    func reset() {
        serviceAccountAccessToken = ""
        serviceAccountTokenExpiresAt = nil
    }

    func setServiceAccountTokenForTesting(_ token: String, expiresAt: Date? = Date().addingTimeInterval(3600)) {
        serviceAccountAccessToken = token
        serviceAccountTokenExpiresAt = expiresAt
    }
}
