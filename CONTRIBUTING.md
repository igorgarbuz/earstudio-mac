# Contributing to EarStudio Companion

Bug reports, documentation fixes, tests, and focused code changes are welcome. This is an independent community project for discontinued EarStudio hardware; support for every device and firmware version is not established.

## Issues and feature requests

Anyone with a GitHub account can open an [issue](https://github.com/igorgarbuz/earstudio-mac/issues). Search existing issues first, then use the bug report or feature request form when appropriate. Blank issues remain available for other topics.

For bugs, include the app version or source commit, macOS version, Mac architecture, device model and firmware (if known), reproduction steps, expected behavior, and the exact error. State whether you used a physical device or demo mode.

Inspect diagnostics and screenshots before posting. Remove device authentication keys, Bluetooth addresses, serial numbers, usernames, and personal paths. Never attach `device-keys.json`. Report vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## Development setup

To build and test with the project's tested toolchain, use macOS 15.6 or newer and a full Xcode 26.3 installation. The built app supports macOS 14 or newer. Select the installation under **Xcode → Settings → Locations → Command Line Tools**. There are no third-party Swift package dependencies.

1. Fork the repository on GitHub.
2. Clone your fork and create a branch for the change:

   ```sh
   git clone https://github.com/YOUR_USERNAME/earstudio-mac.git
   cd earstudio-mac
   git switch -c fix/describe-your-change
   ```

3. Open `EarStudioCompanion.xcodeproj`, choose the **EarStudioCompanion** scheme and **My Mac**, then run with **⌘R** or test with **⌘U**.

From the repository root, the CI-equivalent commands are:

```sh
swift test
./Tools/build.sh test
./Tools/build.sh build
```

`swift test` runs headless protocol/core tests. The Xcode suite also covers app-specific behavior with simulated transports, and the Release build includes Apple Silicon and Intel architectures. Build scripts use local ad-hoc signing; no developer account, signing certificate, or API credentials are needed. Generated outputs stay in the ignored `.build/`, `build/`, and `dist/` directories.

The checked-in Xcode project is ready to use. If you add or remove source files outside Xcode, run `python3 Tools/generate_project.py` and review the generated project changes. Keep build settings in `Configuration/*.xcconfig` because regeneration replaces manual project/scheme edits.

## Preparing a pull request

- Keep a PR focused on one change. Discuss larger features in an issue first.
- Add meaningful regression tests for behavior changes. Documentation-only changes need no new tests.
- Run the relevant tests and build commands above; explain anything you could not run.
- For device-facing changes, document what comes from protocol evidence, simulated tests, or physical observations. Include hardware/firmware details for any physical testing. Automated tests do not establish compatibility with every device or firmware.
- Preserve write confirmation and queue behavior; do not add automatic retries of device settings writes without discussing their consequences.
- Keep vendor binaries, decompiled code, generated outputs, authentication keys, and personal device data out of the repository. See [Docs/Provenance.md](Docs/Provenance.md) for the evidence boundaries.
- Update user-facing documentation when behavior changes. Preserve the distinction between independently authored MIT-licensed work and third-party reference material described in the [README](README.md#license).

Push your branch to your fork and open a PR targeting `igorgarbuz/earstudio-mac:main`. Use the PR template to explain the problem, resulting behavior, and validation.

## Review and CI

Igor (`@igorgarbuz`) is the maintainer and code owner for all files. Contributions require his approval and he performs merges. Contributors use forks without receiving write access to the upstream repository. Everyone may comment and review publicly; those reviews do not replace the maintainer's required approval.

`main` requires PRs, resolved review conversations, and the **Core tests** and **macOS build and tests** checks. New changes dismiss stale approvals. CI runs on PRs targeting `main` and on pushes to `main`, with read-only token permissions and no repository secrets. Workflows from outside contributors wait for maintainer approval; this workflow approval is separate from code review.

Maintainer-authored PRs still go through CI and a PR. GitHub does not allow authors to approve their own PRs, so the maintainer has a PR-only bypass of the review ruleset. See [Docs/Maintaining.md](Docs/Maintaining.md) for the settings and release process.

Please follow the [Code of Conduct](CODE_OF_CONDUCT.md).
