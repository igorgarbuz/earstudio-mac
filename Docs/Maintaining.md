# Maintaining EarStudio Companion

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

CI selects Xcode 26.3 on `macos-15` and runs the same commands documented in [CONTRIBUTING.md](../CONTRIBUTING.md). Review runner/toolchain changes when upgrading Xcode. CI uses ad-hoc signing through the existing build script and does not publish releases.

## Releases

1. Prepare a PR updating `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Configuration/App.xcconfig`, with release notes in `Docs/Releases/`.
2. Review the PR, wait for both CI checks, resolve conversations, and squash merge it.
3. In a clean local checkout, switch to `main` and run `git pull --ff-only`.
4. Run `./Tools/publish-release.sh --dry-run`, inspect its target/version, then run `./Tools/publish-release.sh` when ready to publish.

The publishing script requires a clean checkout matching the remote default branch, runs both test suites, packages a fresh universal DMG and checksum, and verifies draft uploads before publication. Publishing remains a deliberate maintainer operation using locally authenticated GitHub CLI credentials. Never put release credentials or device authentication keys into contributor CI.

See [SECURITY.md](../SECURITY.md) for vulnerability reporting and [CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md) for conduct expectations.
