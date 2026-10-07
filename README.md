# EarStudio Companion for macOS

A native SwiftUI controller for the EarStudio ES100 / ES100 MK2, built from the control protocol recovered from the Android 1.9.0 app. The interface adapts its charcoal background, green accents, and EQ controls to a desktop window. This repository contains the standalone Mac project; Android binaries and the original analysis workspace are not included.

**Status:** builds and runs on macOS; protocol/preset tests and demo interactions have been checked. Bluetooth transport and device commands are implemented, but have **not yet been validated against a physical ES100**. This is an independent app, not a Radsone release.

## Install the built app

Open `dist/EarStudio-Companion-1.0.0-macOS-universal.dmg`, then drag **EarStudio Companion.app** onto **Applications**. Quit the earlier preview first, eject the disk image after copying, and launch the app from Applications. No separate audio driver or `.pkg` installer is needed. Requires macOS 14 or newer; the package contains both Apple Silicon and Intel code.

Alternatively, copy `build/Build/Products/Release/EarStudio Companion.app` directly into Applications. The `.app` is already an executable application bundle; you do not need Xcode just to run it.

This package is built locally with **ad-hoc signing**, and is **not notarized by Apple**. The code signature is verified during packaging, but that is different from Developer ID distribution trust. A downloaded copy on another Mac may be blocked by Gatekeeper. See the public-distribution section below before sharing it broadly.

## Build, test, and package

Open `EarStudioCompanion.xcodeproj`, choose **EarStudioCompanion → My Mac**, and press **⌘R** to build/run or **⌘U** to test. Use **Product → Archive** to create a Release archive. No third-party project generator or package download is needed to open and build the checked-in project.

For the same operations from Terminal:

```sh
cd earstudio-mac # Or your local project folder, named EarStudioMac in the original workspace
./Tools/build.sh build    # Universal Release .app
./Tools/build.sh test     # Debug XCTest run on this Mac
./Tools/package.sh        # Universal Release archive + verified DMG + SHA-256
```

The packaging script builds from source every time. It uses the installed Xcode command-line tools, `ditto`, `codesign`, `lipo`, and `hdiutil`. It does not install the app, upload anything, or access account credentials. If only Apple's standalone Command Line Tools are selected, choose the full Xcode app in **Xcode → Settings → Locations → Command Line Tools**.

Outputs:

- App: `build/Build/Products/Release/EarStudio Companion.app` after `build.sh build`.
- Archive and debug symbols: `build/Archives/EarStudioCompanion.xcarchive` after `build.sh archive` or `package.sh`.
- Installation image and checksum: `dist/EarStudio-Companion-<version>-macOS-universal.dmg` and `.dmg.sha256`.
- Build/test/package logs: `build/logs/`.

Version and build numbers come from `Configuration/App.xcconfig` and are reflected in the app, diagnostics, and package filename. Debug builds target the current Mac; Release builds include `arm64` and `x86_64`.

## Direct Xcode command

Requires macOS 14 or newer. Open `EarStudioCompanion.xcodeproj`, choose the **EarStudioCompanion** scheme and **My Mac**, then press Run. The project has no package dependencies and uses local ad-hoc signing; a paid developer account is not required for a local build. Built using Xcode 26.3.

```sh
cd earstudio-mac
xcodebuild -project EarStudioCompanion.xcodeproj \
  -scheme EarStudioCompanion -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY=- build
open "build/Build/Products/Release/EarStudio Companion.app"
```

Use **Explore demo** to try the controls with simulated state. Launch with `--demo` to use a separate demo preset library:

```sh
open "build/Build/Products/Release/EarStudio Companion.app" --args --demo
```

The default launch is disconnected. There is no automatic scan, connection, audio playback, or settings write on startup. Demo mode does not send device commands. This build is for local use; distribution to other Macs would require your own signing/notarization setup.

## Connect the real device

1. Turn on ES100 and pair it in **System Settings → Bluetooth**. Close other EarStudio controllers while testing.
2. Click **Connect device**. Select a paired ES100, or use **Search nearby** to discover it. Device discovery filters names containing `EarStudio` or `ES100`.
3. Allow Bluetooth access when macOS asks. If connection authorization is requested, briefly press the ES100 power button within three minutes. The returned device key is kept in macOS Keychain.
4. The app reads settings before enabling controls. Select ES100 as your audio output separately in macOS Sound settings if you want the Mac to play through it.

The control connection uses Bluetooth Classic RFCOMM, including while ES100 plays USB audio. It does not install an audio driver or route Mac audio itself. SDP resolves the advertised serial-port channel; the implementation tries the Android SPP service and the GAIA service UUID.

## Implemented controls

| Area | Controls |
| --- | --- |
| Equalizer | 10 bands at 31.5–16,000 Hz, ±12 dB in 0.1 dB steps, enable/bypass, preamp, two Q options, −6/−12 dB headroom, analog compensation |
| Presets | Named local presets, flat reset, JSON import/export, Android SharedPreferences XML import |
| Output | Volume/mute, four balanced/unbalanced amplifier modes, output lock, left/right attenuation, maximum volume |
| Sound | Four DAC filters, 1×/2×/4× oversampling, crossfeed, DCT level |
| Input | Codec/rate/bit-depth readback, AAC/aptX/aptX HD enablement, Bluetooth buffer, USB format, USB/Bluetooth jitter processing |
| Ambient/calls | Ambient enable/mix/shortcut, microphone gain and +21 dB preamp, call mute, microphone loopback, hands-free profile |
| Device | Battery percentage/voltage/charging, battery care, charging enablement, auto power, LED mode, second-device reconnect, notification volume |
| Connection | Discovery, physical-button authorization, Keychain storage, readback, disconnect/error handling, refresh, diagnostics export |

Firmware-dependent controls are gated where a minimum version was recovered. A device rejection disables an unsupported command for the session. USB format and HFP changes require restarting the ES100; the app does not reboot it automatically.

The EQ is the Android app’s **graphic EQ**, not a general parametric EQ: band centers are fixed, and the device offers wide/narrow Q. The plotted curve is a peaking-filter estimate and excludes digital headroom and analog compensation; firmware performs the actual processing.

Not implemented: firmware flashing, factory reset, native Android factory preset tables, output-voltage/SPL calculator, device renaming, playback transport controls, automatic extraction of a phone’s private app storage, or an iOS build. No Android binary or native library is linked into the Mac executable.

## Preset compatibility

Connecting reads the device’s **currently active EQ**, including settings previously applied from Android. The Android app’s four saved library slots are separate phone-local data. If you already have a SharedPreferences XML export containing `radsone_eq_pre1`–`radsone_eq_pre4`, import it from **Presets → Import presets**. Each slot stores eleven comma-separated gains: preamp, then ten bands; `Preset_name_1`–`Preset_name_4` supply names.

Android slots do not store Q/headroom, so imported slots use narrow Q, −6 dB headroom, and analog compensation enabled. Review those choices before applying. Mac JSON presets include all of these settings. Import adds to the library without writing to the device; select a preset to apply it.

## Verification

```sh
swift test
xcodebuild -project EarStudioCompanion.xcodeproj \
  -scheme EarStudioCompanion -destination 'platform=macOS' \
  -derivedDataPath build CODE_SIGN_IDENTITY=- test
```

Tests cover GAIA wire fixtures, all stream split positions, coalesced packets, corrupt frames/checksums, signed units, packed state bits, firmware-specific reply lengths, EQ readback, command coalescing, preset formats/validation, and microphone gain mapping. They do not substitute for a Bluetooth device integration test.

For first hardware validation, confirm readback values against the ES100 before changing settings. Check a small downward volume adjustment, mute/unmute, one EQ band, then refresh and reconnect to check persistence. Diagnostics records command IDs, status, and message lengths; it omits authorization keys and payload contents.

## Source map

The Xcode navigator mirrors the on-disk folders:

```text
EarStudioMac/
├── EarStudioCompanion.xcodeproj/  # Native app + hosted XCTest target; shared scheme
├── Configuration/               # Base, Debug, Release, App, Tests xcconfig files
├── Sources/
│   ├── App/                     # Lifecycle, Bluetooth transport, Keychain, model
│   ├── Core/                    # Protocol, wire formats, state, preset serialization
│   └── UI/                      # SwiftUI screens and reusable controls
├── Resources/                   # Info.plist and AppIcon asset catalog
├── Tests/                       # Protocol and preset XCTest suite
├── Tools/                       # Build, archive, DMG, project/icon generation
└── Package.swift                # Headless core library/test entry point
```

- `Sources/Core`: framing/stream decoder, commands, state decoding, EQ/preset serialization. Also usable as the local `EarStudioCore` Swift package.
- `Sources/App`: Bluetooth transport, connection/command lifecycle, Keychain, app entry point.
- `Sources/UI`: six SwiftUI screens and reusable controls; keyboard and accessibility support for EQ bands.
- `Tests`: the same XCTest suite is available through Xcode and Swift Package Manager.
- `Tools/generate_project.py`: regenerates the checked-in Xcode project after adding source files.
- `Tools/generate_icon.swift`: draws the app icon from vector shapes.

The main scheme is shared, so command-line builds and another developer's Xcode use the same target/run/test/archive definitions. No `.xcworkspace` is needed for this single-project app. The local Swift package provides an additional headless test entry point; it is not an external package dependency.

`generate_project.py` is an optional maintenance helper, not a build prerequisite. If you add/remove files outside Xcode, run `python3 Tools/generate_project.py`. It preserves the folder hierarchy and is deterministic. Put build-setting changes in the `.xcconfig` files: regenerating replaces manual edits to the `.pbxproj` and shared scheme. You can also maintain the native project directly in Xcode and stop using the helper.

## What remains before a public release

The project is structured for native Xcode development and local installation. It is still an early device-controller implementation. These are the remaining release tasks, rather than missing files needed to open the project:

- **Hardware integration:** verify authorization, command acknowledgements, state readback, reconnect behavior, and settings persistence on actual ES100/MK2 firmware. Protocol fixtures and demo tests cannot establish hardware compatibility.
- **Automated UI/connection tests:** the current XCTest suite covers the protocol core; UI interactions were checked manually. Connection lifecycle tests using an injectable mock transport and an XCUITest target would improve regression coverage.
- **Distribution identity:** select your Apple Developer team and Developer ID Application identity, distribute/sign the Release archive, submit the distribution container for notarization, and staple the accepted ticket. This repository contains no team ID, signing certificate, account credential, or notarization profile, and the packaging script intentionally produces only a local ad-hoc build.
- **Release operations:** CI, a public distribution license, and an update mechanism have not been configured. They are not requirements for using the app locally.

Apple references: [build configuration files](https://developer.apple.com/documentation/xcode/adding-a-build-configuration-file-to-your-project), [packaging Mac software](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution), and [distribution signing](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac).

In the original reverse-engineering workspace, wire evidence is in `../analysis/decompiled/com_radsone_a_a_a_b.java` and its companion enums/helpers; Android UI limits and labels are in the activity files. Those analysis files are outside this repository and are not needed to build the app. `../analysis/protocol.json` is an earlier extraction and is not a complete specification. In particular, `0x0301` is **cancel authentication**, not an authentication-status query.

Only one command is in flight. Unsent slider updates are coalesced per control. Acknowledged settings are followed by readback queries; rejected or timed-out edits revert to confirmed state, with no automatic write retries. Initial connection/authentication/synchronization all have bounded timeouts.
