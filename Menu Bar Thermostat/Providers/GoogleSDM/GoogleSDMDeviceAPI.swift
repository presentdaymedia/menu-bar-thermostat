import Foundation
import Alamofire

extension AppState {
    func loadSignedInGoogleUser() {
        guard !sdmAccessToken.isEmpty else {
            print("loadSignedInGoogleUser: Skipping – no access token.")
            return
        }

        let headers: HTTPHeaders = ["Authorization": "Bearer \(sdmAccessToken)"]
        let url = "https://www.googleapis.com/oauth2/v3/userinfo"

        httpSession.request(url, headers: headers)
            .validate()
            .responseDecodable(of: GoogleUserProfile.self) { response in
            switch response.result {
            case .success(let userInfo):
                let safeEmail = redactedEmail(userInfo.email)
                print("User info fetched successfully for account \(safeEmail)")
                DispatchQueue.main.async {
                    self.cancelGoogleUserProfileRetry()
                    self.userInfoRetryDelay = 5
                    self.userInfo = userInfo
                    self.loadStructures()
                    self.startPubSubSyncIfNeeded()
                }
            case .failure(let error):
                let retryDelay = self.userInfoRetryDelay
                print("Error fetching user info: \(error.localizedDescription) — will retry in \(retryDelay)s")
                let failure = self.handleOAuthBackedFailure(
                    context: "loadSignedInGoogleUser",
                    error: error,
                    statusCode: response.response?.statusCode,
                    responseData: response.data
                )
                DispatchQueue.main.async {
                    if failure != .authentication {
                        self.handleBootstrapFailure()
                    }
                }
            }
        }
    }
}
