# Repository instructions

## Commits and pull requests

- After final file additions, removals, or renames, run
  `./Tools/regenerate-projects.sh`. Both projects include all of `Tools/`, so
  tooling-only changes also require regeneration.
- Review and stage both `.xcodeproj` directories, then run
  `./Tools/regenerate-projects.sh --check` before committing. Edit generators or
  `.xcconfig` files instead of generated project files and schemes.
- Run relevant tests from `CONTRIBUTING.md`. Before merging, check CI on the
  current PR commit and follow repository review rules.

## Local development
- For macOS builds/tests, use `./Tools/build.sh build` or `test`;
  use `build --ad-hoc` when Developer ID credentials are unavailable.
- For iOS simulator builds/tests, use `./Tools/build-ios.sh build` or
  `test`; `device` only checks unsigned compilation, not installation.
- For local iPhone installation, run `./Tools/install-ios.sh`
  (add `--launch` to open it). The script increments the build number;
  no marketing-version bump is needed solely for a local install.

## Release preparation

- Compare changes since the target platform's latest release. Before building,
  choose **patch** for compatible fixes, **minor** for compatible new features,
  or **major** for breaking changes. Explain the choice and any migration in the
  release notes. Respect a user-selected version unless it conflicts with a
  published release.
- Update `MARKETING_VERSION` in `Apps/<platform>/Configuration/App.xcconfig`.
  Keep macOS and iOS versions independent. Tooling/docs PRs need no version bump;
  distributed app-code changes do. An unchanged app may retain its version when
  repairing notarization or packaging; disclose asset replacement in the notes.
- Set the `CURRENT_PROJECT_VERSION` floor at least as high as the last distributed
  build. Let the build scripts reserve the next number; coordinate counters across
  release machines. See `Docs/Maintaining.md#build-numbering`.
- Update release notes (macOS: `Docs/Releases/<version>.md`) and affected user docs
  with behavior changes, upgrade instructions, and validation actually performed.
  Follow `Docs/Maintaining.md` for macOS and `Docs/iOS.md` for iOS.

## Public macOS releases

- Before building, run `./Tools/notarize.sh --check-credentials` using the project's
  `earstudio-notary` Keychain profile or `NOTARY_KEYCHAIN_PROFILE`. Keep credentials
  out of Git and logs. Setup: `Docs/Maintaining.md#notarization`.
- Use `Tools/package.sh`: Developer ID signing → Apple **Accepted** → staple and
  validate → Gatekeeper acceptance → SHA-256 checksum. Any failure blocks public
  distribution; `--ad-hoc` is for local/CI builds only.
- For new releases, use `Tools/publish-release.sh --dry-run`, then the publisher
  from a clean, pushed default-branch checkout. Check the version, commit, notes,
  and asset names; verify uploaded digests and sizes before reporting success.

## Public iOS releases

- For an iOS release, after version updates and validation, run `./Tools/archive-ios.sh`.
