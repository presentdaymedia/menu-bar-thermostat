# Privacy

Menu Bar Thermostat is a local macOS app for controlling thermostats through a Google Device Access project that you configure.

## Data The App Uses

Depending on your Google project and connected devices, the app may display or process:

- Google account sign-in state
- Thermostat device names and identifiers
- Thermostat mode, current temperature, setpoints, Eco state, fan state, and connectivity state
- Google Smart Device Management API responses
- Pub/Sub event payloads for device state changes

## Local Token Storage

After sign-in, the app stores Google OAuth token data in the macOS login Keychain so it can restore your session after relaunch. The Keychain item is local to your Mac and protected by macOS.

macOS may show a prompt saying "Menu Bar Thermostat wants to use your confidential information stored in 'auth' in your keychain." This is expected when the app reads the stored token. Choose "Always Allow" if you want relaunches to reconnect without repeated prompts.

## Local Configuration

Your Google OAuth and Device Access configuration should be stored in ignored local files:

- `Menu Bar Thermostat/Configuration/BuildSettings.local.xcconfig`
- `Menu Bar Thermostat/Configuration/AppConfig.local.plist`

Do not commit or share these files. They identify your own Google OAuth client, Device Access project, Google Cloud project, Pub/Sub topic, Workload Identity configuration, and service account email.

## Network Requests

The app communicates with Google APIs for sign-in, Smart Device Management, Pub/Sub, Workload Identity token exchange, and service account access tokens. It does not require a separate app-operated backend server.

## Logs

Development builds may print diagnostic messages to the local console. Avoid sharing logs publicly unless you have checked that they do not include project IDs, device identifiers, account details, tokens, or other private data.

## Unofficial Project

Menu Bar Thermostat is not affiliated with, endorsed by, or sponsored by Google, Nest, or Alphabet. Your use of Google APIs is governed by Google's terms and by the configuration of your own Google projects.
