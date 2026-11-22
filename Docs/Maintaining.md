# Maintaining ES100 Control

Igor (`@igorgarbuz`) owns and maintains this public repository. External contributors open issues and submit PRs from forks; keep upstream write access exclusive to the maintainer. `CODEOWNERS` selects required reviewers but does not restrict who can merge an already-approved PR, so adding write collaborators would change this policy.

## Branch protection

Two active branch rulesets target `refs/heads/main` under **Settings → Rules → Rulesets**:

| Setting | `main-protection` | `maintainer-review` |
| --- | --- | --- |
| Bypass actors | None | Repository admin, for pull requests only |
| Require PR | Yes, zero approvals in this ruleset | Yes, one approval |
| Require code owner review | No | Yes |
| Dismiss stale approvals | No | Yes |
| Resolve review conversations | Yes | No |
| Block branch deletion and force pushes | Yes | No |
| Required checks | `Core tests`, `macOS build and tests` from GitHub Actions | None |

The protections layer together. `main-protection` keeps PRs and CI mandatory even for the maintainer. `.github/CODEOWNERS` assigns every file to `@igorgarbuz`, including ownership and automation files. Code owner enforcement uses the file on the PR's base branch.

GitHub does not allow authors to approve their own PRs. After reviewing a maintainer-authored PR and its passing checks, the maintainer can use GitHub's bypass option to merge it without an approving review. The bypass covers only `maintainer-review`; it does not bypass `main-protection`. It is available for any PR, so use it for the self-approval limitation rather than as the normal contribution review path. The owner can edit repository settings, but everyday changes still use PRs.

When first introducing these files, verify the CI jobs on the setup PR before making them required. Code owner enforcement becomes effective when `CODEOWNERS` reaches `main`. Do not merge the setup PR until its checks pass and the documentation has been reviewed.

## Repository settings

- Keep the repository public and Issues enabled. Leave repository interaction limits unset so GitHub users can open issues; blank issues are also enabled.
- Enable squash merging and automatic deletion of merged branches. Disable merge-commit/rebase merging and auto-merge so the maintainer performs explicit squash merges.
- Enable Dependabot alerts and security updates, secret scanning, push protection, and private vulnerability reporting. The Swift package currently has no third-party dependencies; `.github/dependabot.yml` checks pinned Actions dependencies weekly.
- Under **Settings → Actions → General**, keep default workflow permissions read-only and **Allow GitHub Actions to create and approve pull requests** disabled. Require workflow approval from all outside contributors.
- Keep CI on GitHub-hosted runners using `pull_request`, with pinned Actions, no persisted checkout credentials, and no repository secrets. Do not run contributor code through `pull_request_target` with elevated permissions.

CI selects Xcode 26.3 on `macos-15` and runs the same commands documented in [CONTRIBUTING.md](../CONTRIBUTING.md). Review runner/toolchain changes when upgrading Xcode. CI explicitly passes `--ad-hoc` for its macOS build and does not publish releases.

## Signing local builds

`Tools/build.sh build`, `Tools/build.sh archive` and `Tools/package.sh` require a
valid **Developer ID Application** signing identity including its private key.
An Apple Developer subscription enables obtaining that certificate; an existing
**Apple Development** identity alone is not sufficient for Mac distribution.
Create it using Xcode → Settings → Accounts → Manage Certificates → Developer ID
Application, or import an existing certificate with its private key. Do not revoke
existing certificates merely to make this build work.

The helper chooses a unique valid Developer ID identity from the Keychain.
Set `APPLE_TEAM_ID` to select a team or `MACOS_SIGN_IDENTITY` to select a certificate
by its exact name or SHA-1 fingerprint when needed. Team IDs are read from the
certificate subject's OU field. No private keys are exported or stored in Git.
Builds verify the resulting team, Developer ID authority, hardened runtime and
secure timestamp. Packaging signs the DMG with the same identity before computing
its checksum. Missing/ambiguous identities stop before the build.

Use `--ad-hoc` explicitly for local contributor/CI builds or test DMGs. Native tests
always use ad-hoc signing. The release publisher calls packaging without that
override, so it cannot silently publish an ad-hoc build. The currently published
releases retain their historical signing status until a new release is made.

## Notarization

Public packaging (`./Tools/package.sh`) requires notarization and an accessible
Keychain profile. It validates credentials before building, signs the app and
DMG, submits the DMG to Apple, requires `Accepted`, staples and validates the
ticket, checks Gatekeeper acceptance, then generates the final SHA-256 checksum.
`--ad-hoc` remains available for local/CI packaging without Apple credentials;
it must never be used for public releases.

One-time setup on the release Mac:

```sh
xcrun notarytool store-credentials "earstudio-notary" \
  --apple-id "YOUR_APPLE_ACCOUNT_EMAIL" --team-id "YOUR_TEAM_ID"
```

Enter an app-specific password at the prompt. Generate it at
[Apple Account](https://account.apple.com/) → Sign-In and Security → App-Specific
Passwords. Find the Team ID in your Apple Developer account's Membership details.
Individuals also have a Team ID. The password label is organizational, not an
Apple-enforced restriction to this app. Keep a dedicated credential for this
project; never put passwords in the repository or contributor CI.

The default profile is `earstudio-notary`. Set `NOTARY_KEYCHAIN_PROFILE` to use
another profile explicitly configured for this project. Validate it with:

```sh
./Tools/notarize.sh --check-credentials
```

To repair an existing signed release without rebuilding the app:

```sh
./Tools/notarize.sh dist/ES100-Control-1.0.13-macOS-universal.dmg
```

This changes the DMG by stapling its ticket and regenerates the adjacent `.sha256`
file. It does not publish. Replace both assets on the existing GitHub release and
update its notes only after success; no version increment is needed when the app
is unchanged. If changing files inside the DMG (such as installation text), recreate
and sign the DMG before notarizing. Never modify its contents afterward.

Submission results and Apple's detailed logs are saved under
`build/logs/notarization.*`. A rejection, network error, missing credential,
stapling error, or Gatekeeper rejection stops the command and leaves no checksum.
For a pending/interrupted submission, inspect its ID with `xcrun notarytool info`
using the same Keychain profile before deciding whether to resubmit. Do not publish
until acceptance and stapling succeed. Revoking the app-specific password or
changing the main Apple Account password requires storing new credentials.

Reference: [Apple's notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

For iPhone development signing and direct installation, use
`Tools/install-ios.sh`; see [iPhone instructions](iOS.md#install-from-terminal).

References: [Apple code-signing certificates](https://developer.apple.com/documentation/technotes/tn3161-inside-code-signing-certificates),
[Mac distribution signing](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac).

## Releases

1. Prepare a PR updating `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Apps/macOS/Configuration/App.xcconfig`, with release notes in `Docs/Releases/`.
2. Review the PR, wait for both CI checks, resolve conversations, and squash merge it.
3. In a clean local checkout, switch to `main` and run `git pull --ff-only`.
4. Run `./Tools/publish-release.sh --dry-run`, inspect its target/version, then run `./Tools/publish-release.sh` when ready to publish.

The publishing script requires a clean checkout matching the remote default branch, runs both test suites, packages and notarizes a fresh universal DMG, validates its stapled ticket and Gatekeeper acceptance, generates its final checksum, and verifies draft uploads before publication. Publishing remains a deliberate maintainer operation using locally authenticated GitHub CLI credentials. Never put release credentials or device authentication keys into contributor CI.

See [SECURITY.md](../SECURITY.md) for vulnerability reporting and [CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md) for conduct expectations.

## Build numbering

`Tools/build_metadata.py` shares build numbering and Git provenance across both apps.
`install-ios.sh` reserves an iOS number after device checks; `build.sh build` and
`build.sh archive` reserve macOS numbers after signing checks. Packaging calls
archive once, so it does not reserve a second number. Failed attempts consume
numbers; gaps are intentional. Checks, dry runs and tests do not reserve numbers.

Counters are locked and saved in ignored `.build-metadata/`, independently per
platform. They survive deleting `build/` and do not dirty release checkouts.
`CURRENT_PROJECT_VERSION` in each app’s xcconfig is a checked-in floor. On a new
checkout or CI runner, set that floor at least as high as the last distributed
build, or restore the counter from the previous release runner. Independent
checkouts must coordinate their counters before distributing; these local
counters are not an App Store-wide allocator.

The revision is captured before compilation. Tracked changes and untracked,
non-ignored files set the modified marker. The shared About footer and support
email include this provenance. Direct Xcode builds do not reserve numbers or
capture provenance; use the scripts for installed/distributed builds.
