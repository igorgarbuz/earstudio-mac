# ES100 Control - Support

ES100 Control is an independent iPhone companion for EarStudio ES100 and ES100 MK2 hardware. It lets you adjust device audio settings and manage equalizer presets. Compatible physical hardware is required.

## Contact

For help, bug reports, or privacy questions, email **[ig@rbuz.me](mailto:ig@rbuz.me)**.
You do not need a GitHub account to request support by email.

You can also [report an issue on GitHub](https://github.com/igorgarbuz/earstudio-mac/issues).
Please avoid posting personal information or private diagnostics in public issues.

When reporting a problem, include:

- Your iPhone model and iOS version.
- The app version and build number from **Settings → Diagnostics & about**.
- Your EarStudio model and firmware version, if available.
- What you expected, what happened, and the steps to reproduce it.

## Cannot find or connect to the device

1. Turn on your ES100, keep it near your iPhone, and make sure it has sufficient battery charge.
2. Turn on Bluetooth in iPhone Settings.
3. In **Settings → Privacy & Security → Bluetooth**, allow access for **ES100 Control**. If the app is not listed, open it and choose **Connect** to request permission.
4. Close other EarStudio controller apps, including controllers on nearby computers or phones that may be connected to the device.
5. In ES100 Control, choose **Connect**. The app reconnects to your last successfully connected device. On first use, it connects automatically if only one device is found after a short discovery window; if several are found, choose one from the list.
6. If authorization is requested, briefly press the accessory's power button as instructed in the app.

**Change device** opens the picker without automatic selection, including while connected. Devices with the same name show a short app identifier, and the previously used device is marked **Last used**. If the remembered device is unavailable, the app does not silently connect to another one; use Change device to choose a replacement.

Audio pairing and the app's settings connection are separate. A working audio connection does not necessarily mean the settings connection is open.

If it still fails, disconnect in the app, restart the accessory, reopen the app, and scan again. Contact support with the exact error message if the problem persists.

## Settings are unavailable or changes do not apply

Wait for connection and settings loading to finish. Controls remain unavailable when disconnected or when the device firmware does not support a setting.

If a change fails, reconnect and use **Refresh device settings** in **Diagnostics & about** before trying again. Some settings, including USB format and hands-free profile changes, require restarting the accessory.

## EQ changes are not audible

Check that equalization is enabled and that audio is actually playing through the ES100. The accessory processes the sound; ES100 Control does not process other apps' audio on the iPhone. Try a modest adjustment at a comfortable listening volume.

## Authorization or reconnect problems

First try reconnecting with other controller apps closed. If authorization continues to fail, use **Forget device authorization** in the bottom **Troubleshooting** section of **Diagnostics & about**, then reconnect and authorize again when prompted.

## Diagnostics

**Refresh device settings** is a troubleshooting action in the **Diagnostics** section of **Settings → Diagnostics & about**. Read settings again from your EarStudio if the displayed values seem outdated; normal use does not require a manual refresh. The button shows progress while reading and confirms when settings have been updated; a failed read is reported instead of showing success.

To end the control connection, use **Disconnect** at the bottom of the **Device** page, below Signal & battery.

Open **Settings → Diagnostics & about → View connection log** to inspect recent activity on a separate screen, newest first. The app keeps up to 300 entries in memory so the About page stays compact.

Choose **Share diagnostics** on the Diagnostics & about page to export the log. Review the text and email it to support if useful. Device authorization keys are excluded from the exported diagnostics. Sending diagnostics is optional.

## Scope and privacy

Firmware flashing and factory reset are not included. Device and firmware compatibility can vary; please include those details when reporting an issue.

The app does not send analytics or automatically upload diagnostics to the developer. Presets and preferences are stored locally, and device authorization is kept in the iOS Keychain. Information you choose to email is used to respond to your support request.

ES100 Control is not affiliated with, endorsed by, or sponsored by Radsone or EarStudio. Product names belong to their respective owners.
