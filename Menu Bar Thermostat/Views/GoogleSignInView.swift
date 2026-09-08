import SwiftUI
import GoogleSignIn
import AppKit

struct GoogleSignInView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var workloadIdentityProvider: WorkloadIdentityTokenProvider
    @State private var showScopeWarning = false
    @State private var missingScopeMessage = ""
    @State private var signInErrorMessage: String?

    var body: some View {
        VStack {
            Button(action: signIn) {
                Text("Sign In with Google")
            }

            if let signInErrorMessage {
                statusMessageView(signInErrorMessage)
            } else if showScopeWarning {
                statusMessageView(missingScopeMessage)
            }
        }
    }

    private func signIn() {
        signInErrorMessage = nil
        showScopeWarning = false
        appState.configureGoogleSignInIfNeeded()

        guard GIDSignIn.sharedInstance.configuration != nil else {
            let message = "Google Sign-In is not configured. Set GOOGLE_OAUTH_CLIENT_ID and GOOGLE_OAUTH_REVERSED_CLIENT_ID for this build."
            signInErrorMessage = message
            print(message)
            return
        }

        guard let presentingWindow = bestPresentingWindow() else {
            let message = "Could not locate a window to present Google Sign-In. Reopen the app window and try again."
            signInErrorMessage = message
            print("Google Sign-In aborted: no presenting window available")
            return
        }

        NSApplication.shared.activate(ignoringOtherApps: true)

        appState.cancelAuthenticationRecovery()
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingWindow, hint: nil, additionalScopes: [
            "openid",
            "https://www.googleapis.com/auth/userinfo.profile",
            "https://www.googleapis.com/auth/userinfo.email",
            "https://www.googleapis.com/auth/sdm.service"
        ]) { signInResult, error in
            if let error {
                print("Error during Google Sign-In: \(error.localizedDescription)")
                self.signInErrorMessage = "Sign-in failed: \(error.localizedDescription)"
                if appState.hasRestorableGoogleSession { appState.retryAuthenticationNow() }
                return
            }
            guard let user = signInResult?.user else {
                print("No user found after Google Sign-In")
                self.signInErrorMessage = "Sign-in failed: No user information returned."
                return
            }

            DispatchQueue.main.async {
                self.signInErrorMessage = nil
                if !hasRequiredScopes(for: user) {
                    self.missingScopeMessage = "Some permissions were not granted. Real-time updates may not work properly."
                    self.showScopeWarning = true
                    print("WARNING: Not all required scopes were granted. Pub/Sub functionality may not work.")
                } else {
                    self.showScopeWarning = false
                }

                appState.cancelAuthenticationRecovery()
                appState.isRestoringSession = false
                appState.beginAuthenticatedSession(sdmAccessToken: user.accessToken.tokenString,
                                                   idToken: user.idToken?.tokenString,
                                                   expiration: user.accessToken.expirationDate)
                AuthenticationDiagnostics.record("interactive_sign_in_succeeded")
            }
        }
    }

    private func hasRequiredScopes(for user: GIDGoogleUser) -> Bool {
        let granted = Set(user.grantedScopes ?? [])
        let required: Set<String> = [
            "openid",
            "https://www.googleapis.com/auth/userinfo.profile",
            "https://www.googleapis.com/auth/userinfo.email",
            "https://www.googleapis.com/auth/sdm.service"
        ]
        return required.isSubset(of: granted)
    }

    private func bestPresentingWindow() -> NSWindow? {
        if let keyWindow = NSApplication.shared.keyWindow {
            return keyWindow
        }
        if let mainWindow = NSApplication.shared.mainWindow {
            return mainWindow
        }
        return NSApplication.shared.orderedWindows.first(where: { $0.isVisible })
    }

    private func statusMessageView(_ text: String) -> some View {
        Text(text)
            .foregroundColor(.red)
            .font(.caption)
            .multilineTextAlignment(.center)
            .lineLimit(4)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 6)
    }
}
