# Google Device Access Setup

Last checked against official Google documentation: May 30, 2026.

Menu Bar Thermostat is a developer-focused app. A clone of this repository does not include working Google credentials. Each developer needs to configure their own Google Cloud, OAuth, Device Access, Pub/Sub, and Workload Identity resources.

Official references:

- Google Device Access get started: https://developers.google.com/nest/device-access/get-started
- Google Device Access events: https://developers.google.com/nest/device-access/api/events
- Google Device Access Pub/Sub setup: https://developers.google.com/nest/device-access/subscribe-to-events
- Google Sign-In for iOS and macOS: https://developers.google.com/identity/sign-in/ios/
- Google Cloud Pub/Sub pull subscriptions: https://cloud.google.com/pubsub/docs/pull
- Google Cloud Pub/Sub create subscriptions: https://cloud.google.com/pubsub/docs/create-subscription
- Google Cloud Workload Identity Federation: https://cloud.google.com/iam/docs/workload-identity-federation

## 1. Device Access Requirements

You need:

- A consumer Google Account with a supported Google Nest thermostat activated on that account.
- A Google Device Access registration.
- A Google Cloud project with the Smart Device Management API enabled.
- A Device Access project connected to your OAuth client.

The Device Access project ID is not the same thing as your Google Cloud project ID. The Device Access project ID is usually a UUID and is used in Smart Device Management API paths.

## 2. Google OAuth Configuration

Menu Bar Thermostat uses Google Sign-In for macOS. Google Sign-In requires:

- An OAuth client ID.
- A reversed client ID / URL scheme configured in the app.

In this repo:

- `GOOGLE_OAUTH_CLIENT_ID` is read by `Menu Bar Thermostat/Resources/Menu-Bar-Thermostat-Info.plist`.
- `GOOGLE_OAUTH_REVERSED_CLIENT_ID` is used as the custom URL scheme in the same plist.

Create your local build settings file:

```sh
cp "Menu Bar Thermostat/Configuration/BuildSettings.example.xcconfig" \
   "Menu Bar Thermostat/Configuration/BuildSettings.local.xcconfig"
```

Then set:

```xcconfig
GOOGLE_OAUTH_CLIENT_ID = your-client-id
GOOGLE_OAUTH_REVERSED_CLIENT_ID = your-reversed-client-id
```

Do not commit `BuildSettings.local.xcconfig`.

## 3. Device Access Project

In the Device Access Console:

1. Create or open your Device Access project.
2. Connect it to the OAuth client ID you created for this app.
3. Enable events if you want Pub/Sub device updates.
4. Save the Device Access project ID.

Put the Device Access project ID in:

```plist
DEVICE_ACCESS_ENTERPRISE_ID
```

The app uses that value when calling Smart Device Management endpoints.

## 4. Pub/Sub Events

Device Access events are delivered through Google Cloud Pub/Sub. For this app, use a pull subscription so the macOS app can request queued messages and acknowledge them after processing.

You need:

- A Google Cloud project ID.
- A Pub/Sub topic ID configured for the Device Access project.
- A pull subscription attached to that topic.
- Permissions that allow the app's service account path to get/create/use the subscription.

Create your local runtime config:

```sh
cp "Menu Bar Thermostat/Configuration/AppConfig.example.plist" \
   "Menu Bar Thermostat/Configuration/AppConfig.local.plist"
```

Set:

```plist
PUBSUB_GOOGLE_CLOUD_PROJECT_ID
PUBSUB_TOPIC_ID
```

Do not commit `AppConfig.local.plist`.

## 5. Workload Identity And Service Account Access

This app avoids checking in service account keys. Instead, it uses Workload Identity Federation to exchange the Google Sign-In ID token for short-lived Google Cloud access, then uses service account impersonation for Pub/Sub calls.

You need to configure:

- A Workload Identity pool and provider that trusts the Google identity token shape you use.
- A service account for Pub/Sub access.
- IAM permissions that allow the federated principal to impersonate the service account.
- Pub/Sub permissions for the service account.

Set:

```plist
WORKLOAD_IDENTITY_AUDIENCE
PUBSUB_SERVICE_ACCOUNT_EMAIL
```

The Workload Identity audience should match the provider resource expected by Google's Security Token Service.

## 6. Local Config Checklist

Your private local files should contain all project-specific values:

- `Menu Bar Thermostat/Configuration/BuildSettings.local.xcconfig`
- `Menu Bar Thermostat/Configuration/AppConfig.local.plist`

Your public Git status should not show either file. Confirm with:

```sh
git check-ignore -v \
  "Menu Bar Thermostat/Configuration/BuildSettings.local.xcconfig" \
  "Menu Bar Thermostat/Configuration/AppConfig.local.plist"
```

## 7. Before Sharing A Build

Before sharing a built `.app`, inspect the app bundle and confirm it does not contain:

- `AppConfig.local.plist`
- `BuildSettings.local.xcconfig`
- `GoogleService-Info.plist`
- local logs or generated output

The public repository intentionally contains only examples and placeholders. Real Google project values belong only in your local ignored files.
