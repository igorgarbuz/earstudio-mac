#!/bin/bash
# Release builds require Developer ID; tests and explicit CI builds use ad-hoc signing.
set -euo pipefail

project_root=$(cd "$(dirname "$0")/.." && pwd)
action=build
ad_hoc=false
if [[ $# -gt 0 && "$1" != --* ]]; then action=$1; shift; fi
if [[ "${1:-}" == --ad-hoc ]]; then ad_hoc=true; shift; fi
if [[ $# -gt 0 ]]; then
    printf 'Usage: %s [build|test|archive] [--ad-hoc]\n' "$0" >&2
    exit 2
fi

case "$action" in
    build)
        configuration=Release
        destination='generic/platform=macOS'
        action_args=(build)
        ;;
    test)
        configuration=Debug
        destination="platform=macOS,arch=$(uname -m)"
        action_args=(test)
        ;;
    archive)
        configuration=Release
        destination='generic/platform=macOS'
        action_args=(-archivePath "$project_root/build/Archives/EarStudioCompanion.xcarchive" archive)
        ;;
    *)
        printf 'Usage: %s [build|test|archive] [--ad-hoc]\n' "$0" >&2
        exit 2
        ;;
esac

if ! xcrun --find swift >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
    printf 'A full Xcode installation must be selected in Xcode → Settings → Locations → Command Line Tools.\n' >&2
    exit 1
fi

signing_args=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual OTHER_CODE_SIGN_FLAGS=)
if [[ "$action" != test ]] && ! $ad_hoc; then
    signing_info=$(python3 "$project_root/Tools/apple_signing.py" mac)
    signing_identity=${signing_info%%$'\n'*}
    signing_team=${signing_info##*$'\n'}
    signing_args=("CODE_SIGN_IDENTITY=$signing_identity" "DEVELOPMENT_TEAM=$signing_team"
        CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=YES 'OTHER_CODE_SIGN_FLAGS=--timestamp')
    printf 'Developer ID signing team: %s\n' "$signing_team"
else
    printf 'Ad-hoc signing (local/CI use only).\n'
fi

metadata_args=()
if [[ "$action" != test ]]; then
    metadata=$(python3 "$project_root/Tools/build_metadata.py" macOS --reserve)
    while IFS= read -r setting; do metadata_args+=("$setting"); done <<< "$metadata"
    printf 'Build metadata:\n%s\n' "$metadata"
fi

mkdir -p "$project_root/build/logs"
log_path="$project_root/build/logs/$action.log"
printf 'Xcode %s (%s)…\n' "$action" "$configuration"
if ! xcodebuild -project "$project_root/EarStudioCompanion.xcodeproj" \
    -scheme EarStudioCompanion -configuration "$configuration" \
    -destination "$destination" -derivedDataPath "$project_root/build" \
    "${signing_args[@]}" ${metadata_args[@]+"${metadata_args[@]}"} "${action_args[@]}" >"$log_path" 2>&1; then
    tail -n 80 "$log_path" >&2
    printf '\nFull log: %s\n' "$log_path" >&2
    exit 1
fi
printf 'Succeeded. Log: %s\n' "$log_path"
if [[ "$action" != test ]]; then
    if [[ "$action" == archive ]]; then
        signed_app="$project_root/build/Archives/EarStudioCompanion.xcarchive/Products/Applications/ES100 Control.app"
    else
        signed_app="$project_root/build/Build/Products/Release/ES100 Control.app"
    fi
    if $ad_hoc; then
        codesign --verify --deep --strict "$signed_app"
    else
        python3 "$project_root/Tools/apple_signing.py" verify-mac "$signed_app" --team "$signing_team"
        printf 'Developer ID signature verified. Notarization is a separate distribution step.\n'
    fi
fi
case "$action" in
    build)
        built_app="$project_root/build/Build/Products/Release/ES100 Control.app"
        version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$built_app/Contents/Info.plist")
        build_number=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$built_app/Contents/Info.plist")
        printf 'App: %s\nVersion: %s (%s)\n' "$built_app" "$version" "$build_number"
        printf 'To create a DMG: "%s/Tools/package.sh"\n' "$project_root"
        ;;
    archive) printf 'Archive: %s\n' "$project_root/build/Archives/EarStudioCompanion.xcarchive" ;;
esac
