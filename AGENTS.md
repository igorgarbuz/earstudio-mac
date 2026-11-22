# Repository instructions

## Before committing or updating a pull request

- Run `./Tools/regenerate-projects.sh` after the final file additions, removals,
  or renames. Always regenerate **both** Xcode projects, even for tooling-only
  changes: both generators include the entire `Tools/` directory, including tests.
- Review and stage generated changes in `EarStudioCompanion.xcodeproj` and
  `EarStudioiOS.xcodeproj` alongside the source changes. Do not hand-edit generated
  project files or schemes; edit the generators or `.xcconfig` files instead.
- Run `./Tools/regenerate-projects.sh --check` after staging and before committing.
  It regenerates both projects and fails if either differs from the index.
- Run the relevant tests described in `CONTRIBUTING.md`. Passing tooling tests
  alone does not cover CI's generated-project consistency checks.

## Preparing a release

- Inspect the latest published release/tag for the target platform and review all
  changes since it. Decide the version **before** building release artifacts;
  explain the selected bump in the release notes or PR description. Use
  `MAJOR.MINOR.PATCH`, choosing the highest-impact change in the release:
  - **Patch** (`1.0.13` → `1.0.14`): compatible bug fixes, small UI corrections,
    packaging fixes, or maintenance without new user-facing functionality.
  - **Minor** (`1.0.13` → `1.1.0`): new backward-compatible user-facing features.
  - **Major** (`1.0.13` → `2.0.0`): intentional breaking changes to supported
    workflows, persisted data, public interfaces, or platform/device support.
    Document migration steps and compatibility impact.
- Keep macOS and iOS versions independent. Update `MARKETING_VERSION` in the
  affected `Apps/<platform>/Configuration/App.xcconfig`; do not bump the other
  platform just to match. Respect a version explicitly chosen by the user;
  explain any conflict with published versions before releasing.
- Do not bump app versions for every tooling/docs PR. Choose a version when
  preparing an app release. Notarizing or repackaging an unchanged published app
  can retain its version; disclose replaced assets in its release notes. Changed
  app code intended for distribution needs a new version, not a silent replacement.
- Check the last distributed build number. `CURRENT_PROJECT_VERSION` is a floor;
  set it at least as high as that build and let the existing build scripts reserve
  the next number through `Tools/build_metadata.py`. Never reset/reuse distributed
  build numbers or manually reserve an extra number before invoking those scripts.
  Coordinate counters across release machines/checkouts.
- Write release notes (macOS: `Docs/Releases/<version>.md`) describing behavior,
  upgrade/migration instructions, signing status, and actual validation. Update
  affected installation/support docs; do not claim physical-device testing unless
  it was performed. Follow the platform release guidance in `Docs/Maintaining.md`
  and `Docs/iOS.md`.

## Public macOS distribution

- Use `Tools/package.sh` for public packaging and `Tools/publish-release.sh` for
  new GitHub releases. They require a Developer ID Application certificate/private
  key, hardened runtime, a secure timestamp, and project notarization credentials.
- Check credentials with `./Tools/notarize.sh --check-credentials` before a release
  build. Use the project's `earstudio-notary` Keychain profile (or an explicitly
  configured project profile via `NOTARY_KEYCHAIN_PROFILE`). Never export secrets
  into source files, logs, PRs, or contributor CI.
- Public releases must receive Apple's **Accepted** status, have their ticket
  stapled and validated, and pass Gatekeeper assessment. Signing alone is not
  notarization. Missing credentials, rejection, or verification failure blocks
  publication; never silently fall back to unsigned/ad-hoc distribution. Without
  the required developer credentials, local/CI builds may use `--ad-hoc` only.
- Generate the SHA-256 checksum **after** stapling. Verify final uploaded asset
  digests and sizes, and keep the DMG, checksum, and release notes consistent.
- For a user-requested repair of an existing release, preserve original assets,
  verify the app signature and version, use `Tools/notarize.sh`, then replace the
  DMG and checksum only after acceptance and validation. Do not rebuild or change
  app code unnecessarily. Update bundled text before signing/notarizing the DMG.

## Before publication and reporting completion

- Verify the generated projects are current and run relevant tests. Check the
  current PR commit's CI results, resolve failures, and follow repository review
  rules before merging. Local tests do not establish that remote CI passed.
- Publish new releases from a clean checkout of the pushed default branch using
  the publisher's dry run first. Confirm version, source commit, release notes,
  and asset names match. Do not include unrelated working-tree changes.
- Creating a PR does not authorize merging or publishing an app release. Proceed
  when the user's request already authorizes that action; do not ask again solely
  because this checklist exists.
- Report the release/PR link, version, validation actually completed, and any
  remaining failures or local uncommitted changes. Never describe pending CI or
  notarization as successful.
