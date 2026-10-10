#!/bin/bash
# Uses only Xcode's installed command-line tools; no XcodeGen or network access.
set -euo pipefail

project_root=$(cd "$(dirname "$0")/.." && pwd)
action=${1:-build}
if [[ $# -gt 1 ]]; then
    printf 'Usage: %s [build|test|archive]\n' "$0" >&2
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
        printf 'Usage: %s [build|test|archive]\n' "$0" >&2
        exit 2
        ;;
esac

if ! xcrun --find swift >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
    printf 'A full Xcode installation must be selected in Xcode → Settings → Locations → Command Line Tools.\n' >&2
    exit 1
fi

mkdir -p "$project_root/build/logs"
log_path="$project_root/build/logs/$action.log"
printf 'Xcode %s (%s)…\n' "$action" "$configuration"
if ! xcodebuild -project "$project_root/EarStudioCompanion.xcodeproj" \
    -scheme EarStudioCompanion -configuration "$configuration" \
    -destination "$destination" -derivedDataPath "$project_root/build" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual "${action_args[@]}" >"$log_path" 2>&1; then
    tail -n 80 "$log_path" >&2
    printf '\nFull log: %s\n' "$log_path" >&2
    exit 1
fi
printf 'Succeeded. Log: %s\n' "$log_path"
case "$action" in
    build)
        built_app="$project_root/build/Build/Products/Release/EarStudio Companion.app"
        version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$built_app/Contents/Info.plist")
        build_number=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$built_app/Contents/Info.plist")
        printf 'App: %s\nVersion: %s (%s)\n' "$built_app" "$version" "$build_number"
        printf 'To create a DMG: "%s/Tools/package.sh"\n' "$project_root"
        ;;
    archive) printf 'Archive: %s\n' "$project_root/build/Archives/EarStudioCompanion.xcarchive" ;;
esac
