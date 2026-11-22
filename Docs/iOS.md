# iPhone companion implementation

The iPhone app is an independent target using the same shared protocol, session,
EQ, preset, and resource modules as macOS. It requires iOS 17 or later. This is a
local development build; physical ES100/MK2 compatibility is not yet verified.

## Implementation plan and boundaries

1. Add a separate iPhone target, application identity, icon, permissions and build settings.
2. Adapt navigation to Device / Equalizer / Settings tabs, with scrolling lists,
   full-width EQ sliders, native file dialogs and system sharing.
3. Bind those controls to the existing session and firmware gates. Preserve explicit
   demo mode, no startup writes, serialized commands, and readback confirmation.
4. Implement Core Bluetooth discovery and the documented GAIA BLE profile, translating
   its ATT values into the packet format consumed by the shared session.
5. Store device authorization in this iPhone's Keychain; disconnect on backgrounding
   so queued work does not resume unexpectedly after suspension.
6. Verify wire conversion, app builds, and iPhone UI at compact widths, landscape,
   and accessibility text sizes. Physical-device validation remains a separate gate.

## Open, build, and test

Open `EarStudioiOS.xcodeproj` at the repository root and select **EarStudioiOS**.
Choose an iPhone simulator and run. For a physical iPhone, select your development
team under Signing & Capabilities; no developer identity is embedded in the repository.
The Mac app remains in `EarStudioCompanion.xcodeproj` with its existing scheme.

### Install from Terminal

With full Xcode selected, connect and unlock the iPhone, trust this Mac, and enable
Developer Mode on the phone. Sign into the appropriate Apple Account in Xcode's
Accounts settings once; opening the project in the editor is not necessary.

```sh
./Tools/install-ios.sh --list             # Devices and available certificate teams
./Tools/install-ios.sh --dry-run          # Show selections and commands; no build/install
./Tools/install-ios.sh --check            # Check device readiness; no build/install
./Tools/install-ios.sh                    # Incremental signed build, then install
./Tools/install-ios.sh --launch           # Also launch after installation
./Tools/install-ios.sh --device 'My iPhone' --team ABCDE12345
```

The installer prefers a single connected physical iPhone and requires an explicit
choice when several are available. `--device` accepts the name, hardware UDID or
CoreDevice identifier; `IOS_DEVICE_ID` is the equivalent environment override.
The hardware UDID goes to Xcode, while CoreDevice's identifier goes to `devicectl`.
Paired but offline phones are reported without attempting a build or installation.

The signing team is detected from the **OU field of valid signing certificates**
in the Keychain. The suffix in an Apple Development certificate's display name
can identify a person instead of the team. Multiple certificates for one team are
fine; multiple teams require `--team` or `APPLE_TEAM_ID`. No private keys are
exported, and no account identifiers or credentials are stored in source files.
Detection identifies an existing certificate's team, not its membership type;
use an explicit team if an older Personal Team certificate remains installed.

Xcode automatic provisioning may register the selected iPhone and create/update
development signing assets. An explicit team also works when Xcode needs to
provision its first development certificate. Missing account access or unsupported
iPhone OS versions stop the build with an error. The app signature/team is
verified before installation. Every run invokes Xcode's incremental build, so an
old `.app` is never installed merely because it exists. A failed build never
falls through to installation.

Signed outputs use ignored `build/iOS-signed`; the build log is
`build/logs/ios-install-build.log`. `--configuration Release` is available;
both configurations use development provisioning for direct device installation.
The existing `build-ios.sh device` remains an unsigned compilation check.

On 19 November 2026, detection and dry-run were verified with the local certificate
and paired iPhone metadata. Physical signing/installation was not verified because
the phone was disconnected. Tooling regression tests cover selection ambiguity,
offline devices, certificate OU extraction, and failure before installation.

```sh
python3 Tools/generate_ios_project.py
./Tools/build-ios.sh build       # Simulator app
./Tools/build-ios.sh device      # Unsigned physical-device compilation, not installation
./Tools/build-ios.sh test        # First available iPhone simulator
# Select a particular simulator for compact/large screen verification:
IOS_SIMULATOR_ID=<UUID> ./Tools/build-ios.sh test
```

Install an iOS simulator runtime under Xcode Settings → Components if needed.
Outputs and logs are under ignored `build/iOS`, `build/iOS-device` and `build/logs`. Xcode test results
retain screenshots from the UI suite. In Debug builds only, `--demo` opens sample
device state without Bluetooth; Release builds ignore it. `--screenshot-tab=device|equalizer|settings` selects the initial tab.
`--ui-testing` isolates preset storage and bypasses the device authorization store.
Normal launch is disconnected and does not request Bluetooth permission.

`Tools/generate_icon.swift --ios` generates the opaque iPhone icon from the same
vector artwork as the Mac icon. Each platform retains its own icon catalog.
The product photo still comes from the single shared resource bundle.

## iPhone behavior

- **Device:** discovery, authorization progress, volume/mute, and device details.
  The connected device card shows battery percentage beside the connection status,
  with a three-bar battery icon (orange at 33% or below). Battery moves below the
  status when larger text needs more space; an unread level displays a dash.
  Bluetooth permission is requested only after choosing Connect or Change device.
  Connect reuses the last successful device (remembered across launches). First-use
  discovery waits three seconds after the first result before selecting a sole
  device; multiple results open the picker. Change device always requires selection.
  Discovery offers retry after 15 seconds without a result; a late first result
  still gets its full three-second selection window.
- **Equalizer:** ten vertically stacked bands, preamp, EQ curve, processing options,
  reset, factory presets and saved presets. Import uses Files with security-scoped
  access; export uses a native document exporter. Presets retain the Mac JSON format.
- **Settings:** output/DAC, input/codecs, ambient/calls, power/device settings and
  diagnostics. Controls remain disabled until their required state and firmware
  support are known. Enabling an ES100 codec does not add that codec to iPhone.
- **Background:** disconnect and stop scanning. There is no background Bluetooth
  mode, audio playback engine, automatic write retry, or automatic reconnect.
- **Storage:** local preset defaults and device-only, unlocked-only Keychain tokens.
  No accounts, cloud synchronization, analytics, or network API credentials.

Portrait and landscape use the same scrolling hierarchy. Controls have 44-point
minimum interaction heights. Slider labels stack when they cannot fit side by
side; system text styles support Dynamic Type. The EQ uses full-width rows instead
of squeezing ten desktop faders onto a phone. VoiceOver sliders expose names and
values. Demo is available only through the Debug launch flag, with no public entry
buttons or banner.

## Automated coverage

The iPhone target has six wire-adapter tests and five UI scenarios. The UI suite
checks every EQ band, preset saving, disconnected controls, Debug demo launch without public demo controls, tab navigation, landscape, and the largest accessibility text category.
It retains screenshots for visual review; passing geometry checks alone is not
a substitute for inspecting those images. The shared package and Mac tests cover
the device commands, firmware gates, queue and readback behavior used by both apps.

Files-provider import/export, real Bluetooth permission transitions and Keychain
authorization still need physical-iPhone exercise. No simulator scenario claims
to validate ES100 connectivity.

### Local verification - 2 November 2026

Verified with Xcode 26.3 and the iOS 26.3.1 simulator runtime:

| Check | Result |
| --- | --- |
| iPhone SE (3rd generation), 375 × 667 points | 6 adapter tests + 4 UI scenarios passed |
| iPhone 17 Pro Max, 440 × 956 points | 6 adapter tests + 4 UI scenarios passed |
| Portrait, landscape, largest accessibility text | Screenshots reviewed on both sizes |
| Simulator Debug / unsigned iPhone Release | Both builds passed |
| Shared package / macOS integration | 49 / 53 tests passed |
| Generated projects | Both match their generators |

Visual review caught and fixed the expanding demo banner overlapping navigation
at accessibility sizes. The banner now reserves its own space and uses a shorter
label at those sizes. Test gestures use the actual list gutter to avoid slider
thumbs and landscape notch margins; landscape screenshots use full-screen capture.
Local review images are under ignored `build/iOS-screenshots/review/compact` and
`build/iOS-screenshots/review/large`. The `.xcresult` bundles retain the originals.
This verifies the current runtime; the iOS 17 deployment minimum has not been
exercised on an iOS 17 device in this pass.

## Bluetooth evidence and limitations

The Mac protocol research establishes ES100 commands over RFCOMM. iOS uses a
separate Core Bluetooth adapter. The generic GAIA BLE v1 profile is established by
Qualcomm-authored source in the following reference mirror, pinned at commit
`fb9a492e783172041cc53eeb41143a7ad00eb212`:

- [GaiaPacketBLE.java](https://github.com/qiu-yongheng/GAIAControl/blob/fb9a492e783172041cc53eeb41143a7ad00eb212/gaialibrary/src/main/java/com/qualcomm/libraries/gaia/packets/GaiaPacketBLE.java): two-byte vendor and command fields, up to sixteen outbound payload bytes, and no RFCOMM header or checksum. Incoming values may carry longer firmware replies; the adapter preserves them within the shared decoder’s 254-byte payload limit.
- [Reference repository](https://github.com/qiu-yongheng/GAIAControl/tree/fb9a492e783172041cc53eeb41143a7ad00eb212): `Services.java`, `Characteristics.java`, and `GattServiceGaia.java` identify the service and required properties.
- [Apple notifications API](https://developer.apple.com/documentation/corebluetooth/cbperipheral/setnotifyvalue(_:for:)): subscription completion precedes response delivery.
- [Apple cancellation API](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/cancelperipheralconnection(_:)): cancellation is asynchronous and finishes through the delegate.

The supported UUID prefix is `00001100` for the service, `00001101` for command,
`00001102` for response and `00001103` for data, all with suffix
`-D102-11E1-9B23-00025B00A5A5`. The adapter validates the profile and waits for
response notifications before authentication. ATT writes use responses and a
bounded queue; an ATT completion never substitutes for firmware readback.
Unknown services, unsupported properties, malformed replies and timed-out writes
fail explicitly. It never sends settings to arbitrary writable characteristics.

These references establish **generic GAIA BLE**. The maintainer has confirmed
successful operation on a physical iPhone with EarStudio hardware. This does not
establish compatibility with every ES100/MK2 firmware version. Record iPhone,
iOS and firmware versions when extending hardware coverage; verify discovery,
authorization, saved-token reconnect, settings readback, EQ changes and recovery.
Simulator tests complement physical testing. No vendor source code is bundled
in this implementation.

See [App Store preparation](AppStore.md) for signed archive and export commands.
