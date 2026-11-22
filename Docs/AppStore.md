# iPhone App Store preparation

The maintainer reports successful physical iPhone testing. Supported hardware
and firmware coverage should match the devices actually tested.

## Build and export

Sign into the paid developer account in Xcode Settings → Accounts, then run:

```sh
./Tools/archive-ios.sh
```

If multiple teams are installed, set `APPLE_TEAM_ID` explicitly. The script
reserves an increasing iOS build number, archives Release for physical iPhones,
and exports an App Store Connect IPA using automatic signing/provisioning.
It does not upload or submit for review. It never substitutes ad-hoc signing.
Logs are in `build/logs/ios-archive.log` and `ios-export.log`.

Archive: `build/Archives/EarStudioiOS.xcarchive`.
Export: `dist/iOS`. Open the archive in Xcode and choose Distribute App →
TestFlight & App Store to validate and upload. Ensure the App Store Connect
record uses bundle ID `com.igor.earstudio-companion.ios`.

## Listing draft

- Name: ES100 Control (subject to availability)
- Subtitle: Bluetooth DAC controller
- Category: Music
- Support: https://github.com/igorgarbuz/earstudio-mac/blob/main/Docs/Support.md
- Privacy policy: publish `Docs/Privacy.md`, then use its public URL.
- Privacy disclosures: Data Not Collected, matching the current app behavior.
- Description: ES100 Control is an independent companion for EarStudio ES100 and ES100 MK2.
  Adjust your device's equalizer, output, DAC processing,
  input and battery settings from your iPhone. Save and import equalizer presets,
  inspect device status and share connection diagnostics when you need help.
  Requires compatible EarStudio hardware. This independent community app is
  not affiliated with Radsone. Firmware flashing and factory reset are not included.

## Review notes draft

ES100 Control controls physical EarStudio ES100 hardware through Bluetooth Low Energy.
Turn on the accessory, allow Bluetooth access, scan and select the device. If
requested, authorize using the accessory's power button. Close other EarStudio
controller apps before connecting. No login is required. Please contact us if
hardware or a demonstration is needed to evaluate the app.

## Before submission

- Publish and verify the privacy-policy and support URLs.
- Supply screenshots from the release UI, review contact details, age-rating
  answers, territories and pricing in App Store Connect.
- Use screenshots showing the current ES100 Control name and owner-provided product photo.
- Confirm the export-compliance answer matches the app's implemented encryption.
- Install the processed TestFlight build and repeat the real-device smoke test.
- Validate in Xcode/App Store Connect; resolve any server-side issues before review.

Apple references: [distribution](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases),
[privacy manifests](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest).
