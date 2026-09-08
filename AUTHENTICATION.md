# Google connection recovery

Temporary network, server, and Keychain failures keep the saved Google session and thermostat selection. The app displays “Reconnecting” and retries after 5, 10, 20, 40, then 60 seconds (capped at 60). Wake and API failures share the same in-flight refresh and respect the retry backoff. “Retry Connection Now” requests an immediate attempt. Controls are disabled while authentication is recovering.

An explicit OAuth `invalid_grant` ends the local session and asks for sign-in. This requirement survives relaunch. A missing saved session on first launch shows normal sign-in; an unavailable Keychain for a previously authorized session is retried. The app does not revoke the user's Google grant during transient recovery.

GoogleSignIn 7.1 refreshes a current user's access/ID token when less than 60 seconds remain. The app schedules at 45 seconds before access-token expiration and schedules from the returned expiration even when the token is unchanged. Startup uses SDK restoration; an existing SDK user uses `refreshTokensIfNeeded`. The SDK owns refresh-token storage. The app's additional access-token cache is updated without deleting the old item first.

Workload Identity / IAM credentials serve Pub/Sub only. Their refresh requests pass through the same Google session path. Failed exchanges retry and never sign the user out. HTTP 403 permission failures do not trigger Google sign-in recovery; check Nest device permissions or the Pub/Sub service-account permissions as appropriate.

## Connection log

Use **Show Connection Log** in the signed-out popover or Settings. The app writes `Library/Logs/Menu Bar Thermostat/authentication.log` within its own user Library (inside its container for sandboxed builds). One previous file is retained; each file is approximately capped at 512 KiB. This works for normal launches from Applications and Start at Login, even when stdout is discarded.

Events include app start, sleep/wake, Google refresh attempts, success/failure, scheduled retry delays, sign-in/sign-out, Keychain OSStatus values, and STS/IAM HTTP status codes. Errors include only recognized domains, numeric codes and allowlisted OAuth reasons. Tokens, raw response bodies, account identifiers, and error descriptions are excluded from this history. Events also appear in macOS unified logging under category `Authentication` and the app's bundle identifier. Other existing debug prints are not redirected into this file.

## Google-side expiration

Google issues seven-day refresh tokens when an external OAuth app is in **Testing** and requests scopes beyond basic identity, including Nest SDM. Check the OAuth project's publishing status in Google Auth Platform / Audience. Publishing status is separate from Device Access Sandbox/Commercial status, and changing it does not guarantee an already-issued token will be extended. A fresh authorization may be necessary. No app code can silently restore a revoked or expired refresh grant.

References:

- [Nest authorization and refresh tokens](https://developers.google.com/nest/device-access/authorize)
- [Google refresh-token expiration rules](https://developers.google.com/identity/protocols/oauth2#expiration)
- [GoogleSignIn token refresh API](https://developers.google.com/identity/sign-in/ios/reference/Classes/GIDGoogleUser)
- [Nest permission errors](https://developers.google.com/nest/device-access/reference/errors/api)

## Validation

The unit suite injects Google session results and uses mocked STS/IAM responses. It covers temporary failure followed by recovery, absent/unavailable credentials, explicit invalid grants, concurrent requests, late callbacks after sign-out or a newer sign-in, unchanged token scheduling, permission errors, log redaction, and real WIF exchange success/failure.

Signed runtime checks still require the configured application: relaunch and sleep/wake with temporary network loss, confirm recovery without sign-in, then verify live thermostat reads and Pub/Sub recovery. Do not change thermostat settings merely to test authentication. An unsigned developer build is not evidence of signed-app Keychain persistence. Use the project's canonical signed build/install workflow when validating persistence.
