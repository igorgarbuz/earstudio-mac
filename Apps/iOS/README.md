# ES100 Control for iPhone

[Download ES100 Control on the App Store](https://apps.apple.com/fr/app/es100-control/id6837818492). Requires iOS 17 or newer.

## Build from source

Open the repository-root `EarStudioiOS.xcodeproj`, choose **EarStudioiOS**, and run
on an iPhone simulator. Requires iOS 17+. For UI development without Bluetooth,
add `--demo` to the scheme’s launch arguments in a Debug build. Release builds
ignore this flag. To build, sign and install on a physical iPhone from Terminal, run
`./Tools/install-ios.sh` at the repository root; `--dry-run` previews device/team
detection. The iPhone companion has been tested successfully on physical hardware by the
maintainer. Unsupported Bluetooth services fail explicitly.

From the repository root:

```sh
./Tools/build-ios.sh build
./Tools/build-ios.sh test
./Tools/install-ios.sh --check
./Tools/install-ios.sh
```

See [iPhone implementation and validation](../../Docs/iOS.md) for the plan,
architecture, transport evidence, test commands and hardware validation checklist.

For App Store Connect archives and distribution, see [App Store preparation](../../Docs/AppStore.md).
