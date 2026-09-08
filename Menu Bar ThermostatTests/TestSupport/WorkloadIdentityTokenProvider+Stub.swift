import Foundation

// The test target now compiles the real provider; this extension only seeds existing fixtures.
extension WorkloadIdentityTokenProvider {
    func setServiceAccountTokenForTesting(_ token: String, expiresAt: Date? = Date().addingTimeInterval(3600)) {
        acceptServiceAccountToken(token, expiresAt: expiresAt ?? Date())
    }
}
