#!/bin/bash
# Publish the tested source commit with a freshly built DMG and checksum.
# Requires macOS, full Xcode, Git, and an authenticated GitHub CLI.
set -euo pipefail

usage() {
    printf 'Usage: %s [--dry-run] [--notes-file FILE]\n' "$0"
}
fail() { printf 'Release stopped: %s\n' "$*" >&2; exit 1; }
project_root=$(cd "$(dirname "$0")/.." && pwd)
notes_file=''
dry_run=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) dry_run=true; shift ;;
        --notes-file)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            notes_file=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done
for tool in git gh swift xcodebuild shasum; do
    command -v "$tool" >/dev/null || fail "Missing required tool: $tool"
done
cd "$project_root"
[[ "$(git rev-parse --show-toplevel)" == "$project_root" ]] || fail 'Run from the standalone Mac Git repository.'
assert_clean() {
    [[ -z "$(git status --porcelain --untracked-files=normal)" ]] || fail 'Commit or remove pending changes before releasing.'
}
assert_clean
version=$(awk '$1 == "MARKETING_VERSION" && $2 == "=" { print $3 }' Configuration/App.xcconfig)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'MARKETING_VERSION must have three numeric components.'
tag="v$version"
commit=$(git rev-parse HEAD)
branch=$(git symbolic-ref --quiet --short HEAD) || fail 'Check out the default branch before releasing.'
origin_url=$(git remote get-url origin)
# Resolve origin explicitly; GH_REPO must not redirect publication elsewhere.
repository=$(gh repo view "$origin_url" --json nameWithOwner --jq '.nameWithOwner')
default_branch=$(gh repo view "$repository" --json defaultBranchRef --jq '.defaultBranchRef.name')
[[ "$branch" == "$default_branch" ]] || fail "Check out the default branch ($default_branch)."
assert_pushed() {
    local remote_commit
    remote_commit=$(git ls-remote --exit-code origin "refs/heads/$branch" | awk '{print $1}')
    [[ "$remote_commit" == "$commit" ]] || fail 'Push the release commit to origin before releasing.'
}
assert_pushed
remote_tags=$(git ls-remote origin "refs/tags/$tag" "refs/tags/$tag^{}")
[[ -z "$remote_tags" ]] || fail "Tag $tag already exists; use a new version."
# Listing releases makes API/network failures fatal instead of mistaking them
# for a release that does not exist. Include drafts, including failed uploads.
existing_release=$(gh api --paginate "repos/$repository/releases?per_page=100" \
    --jq ".[] | select(.tag_name == \"$tag\") | .html_url")
[[ -z "$existing_release" ]] || fail "Release $tag already exists; inspect it before retrying."
if [[ -z "$notes_file" ]]; then notes_file="$project_root/Docs/Releases/$version.md"; fi
[[ -s "$notes_file" ]] || fail "Missing release notes: $notes_file"
# Capture the reviewed text before the build; notes cannot change mid-upload.
mkdir -p "$project_root/build/logs"
prepared_notes=$(mktemp "$project_root/build/release-notes.XXXXXX")
trap 'rm -f "$prepared_notes"' EXIT
cp "$notes_file" "$prepared_notes"
image_name="EarStudio-Companion-$version-macOS-universal.dmg"
image_path="$project_root/dist/$image_name"
checksum_path="$image_path.sha256"
printf 'Repository: %s\nVersion: %s\nCommit: %s\nAssets: %s and its SHA-256 file\n' "$repository" "$tag" "$commit" "$image_name"
if $dry_run; then
    printf 'Dry run: would run both test suites, package, upload a draft, verify assets, then publish.\n'
    exit 0
fi
[[ "$(gh repo view "$repository" --json isPrivate --jq '.isPrivate')" == false ]] \
    || fail 'The repository must be public before publishing this public release.'
printf 'Running core tests…\n'
if ! swift test --package-path "$project_root" >"$project_root/build/logs/core-test.log" 2>&1; then
    tail -n 80 "$project_root/build/logs/core-test.log" >&2
    fail 'Core tests failed.'
fi
"$project_root/Tools/build.sh" test
"$project_root/Tools/package.sh"
assert_clean
[[ "$(git rev-parse HEAD)" == "$commit" ]] || fail 'HEAD changed while preparing the release.'
assert_pushed
(
    cd "$project_root/dist"
    shasum -a 256 -c "$image_name.sha256"
)
# Draft first: no published release can be left without its installation files.
gh release create "$tag" "$image_path" "$checksum_path" --repo "$repository" \
    --target "$commit" --title "EarStudio Companion $version" \
    --notes-file "$prepared_notes" --draft
# GitHub stores the uploaded SHA-256 digest. Match bytes and size before publish.
local_digest=$(shasum -a 256 "$image_path" | awk '{print $1}')
local_size=$(stat -f '%z' "$image_path")
remote_digest=$(gh release view "$tag" --repo "$repository" --json assets \
    --jq ".assets[] | select(.name == \"$image_name\") | .digest")
remote_size=$(gh release view "$tag" --repo "$repository" --json assets \
    --jq ".assets[] | select(.name == \"$image_name\") | .size")
checksum_digest=$(shasum -a 256 "$checksum_path" | awk '{print $1}')
remote_checksum_digest=$(gh release view "$tag" --repo "$repository" --json assets \
    --jq ".assets[] | select(.name == \"$image_name.sha256\") | .digest")
[[ "$remote_digest" == "sha256:$local_digest" && "$remote_size" == "$local_size" \
    && "$remote_checksum_digest" == "sha256:$checksum_digest" ]] \
    || fail "Asset verification failed; $tag remains a draft."
gh release edit "$tag" --repo "$repository" --draft=false --latest
printf 'Published: %s\n' "$(gh release view "$tag" --repo "$repository" --json url --jq '.url')"
