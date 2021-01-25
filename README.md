# OpenTrace iOS App with HERALD instrumentation

![alt text](./OpenTrace.png "OpenTrace Logo")

This is a fork of the OpenTrace iOS App with HERALD instrumentation to enable evaluation using the [Fair Efficacy Formula](https://vmware.github.io/herald/efficacy/).

Changes to the OpenTrace app are:

- Full offline operation without any dependency on Firebase
- Bypass phone registration and one-time-passcode (OTP) checks
- HERALD instrumentation to log phone discovery, payload read, and RSSI measurements
- Log files are compatible with HERALD analysis scripts for evaluation
- Fixed payload, rather than rotating payload, to enable automated analysis

## Building the code

1. Install the latest [Xcode developer tools](https://developer.apple.com/xcode/downloads/) from Apple
2. Install [CocoaPods](https://github.com/CocoaPods/CocoaPods)
3. Clone the repository
4. Run `pod install` at root of project
5. Open `OpenTrace.xcworkspace`
6. Set credential at `OpenTrace project > Signing & Capabilities > Team`
7. Build and deploy `opentrace-staging` to test device

## App configuration

1. Start app
2. The `Set up app permissions` screen will be shown on first use, press `Proceed`
3. Select `Allow` for `Notification permission`
4. Select `OK` for `Bluetooth permission`
5. On `Turn on your Bluetooth` screen, press `I turned on Bluetooth`
6. On `App permissions are fully set up` screen, press `Continue`
7. On `iPhone users, take note!` screen, press `I'll keep this in mind`
8. Initial setup is complete, app is ready for test

## Testing

Please refer to [herald-for-ios](https://github.com/vmware/herald-for-ios) for details on test procedure and log file access.

HERALD instrumentation uses fixed device specific payload by default to enable analysis. This can be disabled by setting `FairEfficacyInstrumentation.testMode = false`.
