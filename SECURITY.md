# Security policy

## Supported versions

Security fixes target the latest stable app versions distributed through the [App Store](https://apps.apple.com/fr/app/es100-control/id6837818492) for iPhone and [GitHub Releases](https://github.com/igorgarbuz/earstudio-mac/releases/latest) for macOS. Older releases are not maintained separately. Device firmware and third-party manufacturer materials are outside this project's control.

## Reporting a vulnerability

Use **Security → Report a vulnerability**, or [start a private vulnerability report](https://github.com/igorgarbuz/earstudio-mac/security/advisories/new). Do not open a public issue for a suspected vulnerability or post sensitive reproduction details in a public PR.

Include:

- The affected app version or source commit and iOS/macOS version.
- The vulnerable behavior and its potential impact.
- Reproduction steps or a minimal proof of concept.
- Any relevant device/firmware details and possible mitigation.

Share only the minimum evidence needed. Remove unrelated authentication keys, Bluetooth addresses, serial numbers, usernames, and personal paths. Never publish `device-keys.json` or device authorization tokens.

The maintainer will assess the report and coordinate remediation and disclosure through the private report. Response times depend on maintainer availability; this community project does not offer a security response SLA.

For ordinary bugs without security impact, use [GitHub Issues](https://github.com/igorgarbuz/earstudio-mac/issues).
