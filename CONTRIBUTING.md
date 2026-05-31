# Contributing

## Tests

Run the macOS XCTest suite before opening a pull request:

```sh
xcodebuild -project 'Menu Bar Thermostat.xcodeproj' -scheme 'Menu Bar Thermostat' -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/menu-bar-thermostat-test-audit CODE_SIGNING_ALLOWED=NO test
```

The test target currently compiles selected app source files directly instead of importing the app target as a separate module. It also uses local stubs for `WorkloadIdentityTokenProvider` and `MenuBarStatusItemController` so tests can run without real Google credentials, Pub/Sub tokens, or a live menu bar item.
