#!/bin/bash
# Create a signed, notarized universal DMG and checksum; does not upload to GitHub.
set -euo pipefail

ad_hoc=false
if [[ "${1:-}" == --ad-hoc ]]; then ad_hoc=true; shift; fi
if [[ $# -ne 0 ]]; then
    printf 'Usage: %s [--ad-hoc]\n' "$0" >&2
    exit 2
fi
project_root=$(cd "$(dirname "$0")/.." && pwd)
archive_args=(archive)
if $ad_hoc; then
    archive_args+=(--ad-hoc)
else
    "$project_root/Tools/notarize.sh" --check-credentials
    signing_info=$(python3 "$project_root/Tools/apple_signing.py" mac)
    signing_identity=${signing_info%%$'\n'*}
    signing_team=${signing_info##*$'\n'}
    # Keep app and DMG identity selection identical throughout packaging.
    export MACOS_SIGN_IDENTITY="$signing_identity" APPLE_TEAM_ID="$signing_team"
fi
"$project_root/Tools/build.sh" "${archive_args[@]}"

archived_app="$project_root/build/Archives/EarStudioCompanion.xcarchive/Products/Applications/ES100 Control.app"
test -d "$archived_app"
codesign --verify --deep --strict "$archived_app"
xcrun lipo "$archived_app/Contents/MacOS/ES100 Control" -verify_arch arm64 x86_64
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$archived_app/Contents/Info.plist")
if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    printf 'Unexpected app version: %s\n' "$version" >&2
    exit 1
fi

mkdir -p "$project_root/dist" "$project_root/build/logs"
staging=$(mktemp -d "$project_root/build/dmg-staging.XXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto "$archived_app" "$staging/ES100 Control.app"
ln -s /Applications "$staging/Applications"
cp "$project_root/LICENSE" "$staging/LICENSE.txt"
cat >"$staging/Install.txt" <<'INSTALL'
ES100 Control - macOS 14 or newer
An independent companion for EarStudio ES100 and ES100 MK2.

1. Quit an earlier version of ES100 Control before replacing it.
2. Drag ES100 Control.app onto the Applications folder beside it.
3. Eject this disk image and open ES100 Control from Applications.
4. Pair your ES100 in System Settings → Bluetooth
   and choose Connect in the app.

Upgrading from EarStudio Companion? Quit the old app before installing, then
remove EarStudio Companion.app from Applications. Settings and device
authorization remain in the same storage locations.

No audio driver or separate installer is required. The app includes Apple
Silicon and Intel code. It starts disconnected and does not change device
settings until you connect and use its controls.
Connect also handles Bluetooth recovery when necessary; audio may briefly pause.

Hardware coverage is limited. Read the release notes for validation scope.
The independent app code is MIT licensed; see LICENSE.txt.
INSTALL
if $ad_hoc; then
    printf '\nSignature: ad-hoc, for local development/CI only.\n' >>"$staging/Install.txt"
else
    printf '\nSignature: Developer ID Application. Public releases are notarized by Apple; open the app normally from Applications.\n' >>"$staging/Install.txt"
fi

image_name="ES100-Control-$version-macOS-universal.dmg"
image_path="$project_root/dist/$image_name"
log_path="$project_root/build/logs/package.log"
printf 'Creating %s…\n' "$image_name"
if ! hdiutil create -srcfolder "$staging" -volname 'ES100 Control' \
    -fs HFS+ -format UDZO -ov "$image_path" >"$log_path" 2>&1; then
    cat "$log_path" >&2
    exit 1
fi
hdiutil verify "$image_path" >>"$log_path" 2>&1
if ! $ad_hoc; then
    codesign --force --sign "$signing_identity" --timestamp "$image_path"
    codesign --verify --strict "$image_path"
    "$project_root/Tools/notarize.sh" "$image_path"
fi
(
    cd "$project_root/dist"
    shasum -a 256 "$image_name" >"$image_name.sha256"
)
printf 'Verified DMG: %s\n' "$image_path"
printf 'Install: open the DMG and drag ES100 Control into Applications.\n'
