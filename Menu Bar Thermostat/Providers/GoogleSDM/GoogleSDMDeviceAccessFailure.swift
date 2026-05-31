import Foundation
import Alamofire

enum DeviceAccessRequestFailure {
    case authentication
    case rateLimited
    case rejectedCommand
    case explicitOffline
    case networkOrServerFailure
    case other
}

extension AppState {
    @discardableResult
    func handleOAuthBackedFailure(context: String, error: AFError, statusCode: Int?, responseData: Data?) -> DeviceAccessRequestFailure {
        let failure = classifyFailure(statusCode: statusCode, responseData: responseData, error: error)
        if let responseData, let responseString = String(data: responseData, encoding: .utf8) {
            print("Response Data: \(responseString)")
        }

        switch failure {
        case .authentication:
            print("\(context): Authentication error detected, refreshing token")
            refreshTokenIfNeeded(force: true)
        case .rateLimited:
            print("\(context): Rate limit detected")
            handleRateLimitError()
        default:
            break
        }

        return failure
    }

    @discardableResult
    func handleCommandFailure(context: String, error: AFError, statusCode: Int?, responseData: Data?) -> DeviceAccessRequestFailure {
        let failure = handleOAuthBackedFailure(context: context, error: error, statusCode: statusCode, responseData: responseData)

        switch failure {
        case .explicitOffline, .networkOrServerFailure:
            markConnectionUnhealthy()
        case .authentication, .rateLimited, .rejectedCommand, .other:
            break
        }

        return failure
    }

    private func classifyFailure(statusCode: Int?, responseData: Data?, error: AFError) -> DeviceAccessRequestFailure {
        let responseString = responseData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let uppercasedResponse = responseString.uppercased()

        if statusCode == 401 || statusCode == 403 ||
            uppercasedResponse.contains("UNAUTHENTICATED") ||
            uppercasedResponse.contains("AUTHENTICATION CREDENTIAL") {
            return .authentication
        }

        if statusCode == 429 ||
            uppercasedResponse.contains("RESOURCE_EXHAUSTED") ||
            uppercasedResponse.contains("RATE LIMITED") {
            return .rateLimited
        }

        if uppercasedResponse.contains("FAILED_PRECONDITION") ||
            uppercasedResponse.contains("THERMOSTAT FAN UNAVAILABLE") ||
            uppercasedResponse.contains("CANNOT BE OVERRIDDEN") ||
            uppercasedResponse.contains("ALREADY ENGAGED") {
            return .rejectedCommand
        }

        if uppercasedResponse.contains("OFFLINE") ||
            uppercasedResponse.contains("DEVICE IS NOT CONNECTED") {
            return .explicitOffline
        }

        if let statusCode, statusCode >= 500 {
            return .networkOrServerFailure
        }

        switch error {
        case .sessionTaskFailed:
            return .networkOrServerFailure
        default:
            return .other
        }
    }
}
