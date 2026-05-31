# Security Policy

## Supported Versions

Security fixes are handled on the `main` branch until the project begins publishing versioned releases.

## Reporting A Vulnerability

Please do not open a public issue for suspected credential exposure, token handling bugs, or vulnerabilities that could affect Google accounts or thermostat control.

Use the repository's **Report a vulnerability** link on GitHub if private vulnerability reporting is enabled. If that link is not available, please wait for a private reporting channel to be added rather than opening a public issue with sensitive details.

Include:

- A concise description of the issue
- Steps to reproduce
- The affected commit or version, if known
- Whether credentials, tokens, or device control may be exposed

Do not include real OAuth tokens, service account tokens, private keys, or Google project secrets in a report.

## Local Configuration Safety

This repository is designed so local Google project configuration lives in ignored files:

- `Menu Bar Thermostat/Configuration/BuildSettings.local.xcconfig`
- `Menu Bar Thermostat/Configuration/AppConfig.local.plist`

Before publishing a release or sharing a build artifact, inspect the built `.app` bundle and confirm those local files, `GoogleService-Info.plist`, logs, and generated outputs are not present.
