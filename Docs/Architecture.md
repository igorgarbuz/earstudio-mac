# Repository architecture

ES100 Control is one repository with independently integrated platform apps.
The macOS app is the only shipping app; the iPhone app is a local development target. Shared code is built as local Swift package
modules; it is not compiled a second time as app source. No remote package or
third-party library is required. The Mac app and its hosted tests link the single
`EarStudioKit` product, which contains all four shipping modules. Individual layer
products are also available to consumers that need only part of the package.

```text
EarStudioCompanion.xcodeproj    macOS entry point, generated deterministically
EarStudioiOS.xcodeproj          iPhone entry point, generated deterministically
Apps/
  macOS/
    Sources/App/               composition, discovery, RFCOMM, token store, dialogs
    Sources/UI/                desktop screens, navigation, platform controls
    Resources/                 macOS Info.plist and app icon catalog
    Configuration/             macOS build, version and signing settings
    Tests/                     native lifecycle, adapter and persistence tests
  iOS/                         iPhone app, Core Bluetooth, phone UI and tests
Packages/EarStudioKit/
  Sources/EarStudioCore/        wire protocol, state, presets, EQ response math
  Sources/EarStudioSession/     live device behavior and transport contracts
  Sources/EarStudioUI/          SwiftUI bindings, theme, image and EQ chart
  Sources/EarStudioAssets/      one canonical shared resource catalog
  Tests/                       core/session tests and independent firmware fixtures
Tools/                         repository entry points for builds and releases
Docs/                          protocol evidence, architecture and release notes
```

## Dependency rules

- `EarStudioCore` uses Foundation and owns protocol/state/preset types. It has no
  UI, Bluetooth framework, bundle lookup or app-global persistence dependencies.
- `EarStudioSession` depends on Core and Combine. It owns authentication, firmware
  gates, command coalescing, readback confirmation, rollback, presets and demo
  state. It receives a preset store and token operations from its host.
- `EarStudioAssets` owns its SwiftPM resource bundle and stable asset names. It
  does not depend on the other modules.
- `EarStudioUI` depends on Core, Session and Assets. It supplies reusable SwiftUI
  pieces without depending on the Mac model, windows, file dialogs or discovery.
- Apps compose these modules with their own transport, persistence and UI. Shared
  modules must never import an app target, AppKit, UIKit or IOBluetooth.

The `CommandQueue` API is package-scoped. Public domain values are intentionally
available to app controls and adapters; parsing internals remain private. Tests
use independent wire fixtures from the non-product `EarStudioTestSupport` target.

## Connection and observation boundary

`DeviceConnection` holds an opaque ID, display name, a factory for a fresh
`SessionTransport` per attempt, and an optional link-reset operation. Its closures
may capture native device objects, but none escape into the shared session API.
`SessionTransport` exchanges encoded GAIA bytes. A future transport must adapt its
framing to this contract; it must not assume that macOS RFCOMM framing is directly
usable on another transport.

Invoke session methods and deliver all transport/reset callbacks on the main
thread. The existing timers, delayed writes and observable state rely on this
contract. A transport must finish `close` only after it releases the old connection.
The session retains the closing transport, suppresses stale callbacks and waits
before reconnecting. Opening recovery never replays setting writes. Hosts must
call `disconnect` when ending a session; the macOS termination path already does.

The Mac `StudioModel` owns discovery, sheet state and file dialogs. It forwards
shared state changes through Combine and delegates setting operations to
`DeviceSession`. `MacSessionTransport` binds the existing native transport to its
`IOBluetoothDevice`. The Mac adapter supplies link reset and macOS error messages.
The shared session still implements the existing bounded recovery policy; a host
without a reset operation fails cleanly after the control-channel retry.

Authorization storage remains the existing Mac implementation and location.
Preset persistence retains the existing key and file format. The iPhone stores
authorization tokens in its device-only Keychain and owns Core Bluetooth discovery
and transport. Shared code does not imply cross-device sync.

## Asset ownership

The ES100 photo lives only in
`Packages/EarStudioKit/Sources/EarStudioAssets/Resources/SharedAssets.xcassets`.
The README references that same file; app views use the package bundle through
`EarStudioAssets`, never `Bundle.main` or an unqualified image name. The photo's
third-party provenance and license exclusion remain in [Provenance](Provenance.md).

The macOS icon set remains under `Apps/macOS/Resources/Assets.xcassets` because
app-icon slots and sizes are platform-specific. `Tools/generate_icon.swift` owns
the vector drawing recipe and writes the macOS icon set; its `--ios` option writes
the opaque iPhone icon under `Apps/iOS/Resources/Assets.xcassets`. Both platforms
reuse the artwork without duplicating runtime resources. Reference PDFs remain
documentation and are not shipped in the app.

## Building and checking

Run from the repository root:

```sh
swift test --package-path Packages/EarStudioKit
./Tools/check-ios-package.sh
./Tools/build.sh test
./Tools/build.sh build
./Tools/build-ios.sh test
./Tools/build-ios.sh device
```

The iOS check compiles `EarStudioUI` and all its shipping dependencies for the
Simulator without an iOS app or signing. It validates source compatibility, not
hardware communication. The full check requires the iOS platform component in
Xcode Settings → Components. If only the SDK is installed, run
`./Tools/check-ios-package.sh --source-only` to cross-compile the Swift modules;
this narrower check does not compile the iOS asset catalog. CI compiles those
resources as part of the complete iPhone app build and simulator tests.
The package currently targets macOS 14 and iOS 17.

Open the root Xcode project to work on macOS. After adding or removing app files,
run `python3 Tools/generate_project.py`. SwiftPM discovers package sources without
project regeneration. Run `python3 Tools/generate_ios_project.py` after adding or
removing iPhone app/test files. CI checks package tests, both generated projects,
native Mac tests, iPhone unit/UI tests and the universal Mac build.

`EarStudioiOS.xcodeproj` and `Tools/build-ios.sh` build the iPhone app. See
[iPhone development](iOS.md) for Bluetooth evidence and validation limits.

`Tools/build.sh`, `Tools/package.sh` and `Tools/publish-release.sh` remain macOS
entry points, with unchanged output paths and release tags. macOS version settings
live in `Apps/macOS/Configuration/App.xcconfig`. iOS signing and versions
are separate under `Apps/iOS/Configuration`; distribution is not configured. The repository name,
remote URL, existing release links and installed app identity are unchanged.
