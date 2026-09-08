# Contributing

## Tests

Run the macOS XCTest suite before opening a pull request:

```sh
xcodebuild -project 'Menu Bar Thermostat.xcodeproj' -scheme 'Menu Bar Thermostat' -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/codex-macos -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

The test target currently compiles selected app source files directly instead of importing the app target as a separate module. Google session requests are injected and HTTP calls use `MockURLProtocol`; the real `WorkloadIdentityTokenProvider` is compiled into the tests. Only the menu bar controller is stubbed. Tests do not require Google credentials or a live thermostat. See [AUTHENTICATION.md](AUTHENTICATION.md) for recovery behavior, diagnostics, and runtime checks.
