#!/bin/bash
# Full check builds the resource catalog. --source-only needs only the iOS SDK.
set -euo pipefail
project_root=$(cd "$(dirname "$0")/.." && pwd)
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --source-only ) ]]; then
    printf 'Usage: %s [--source-only]\n' "$0" >&2
    exit 2
fi
mkdir -p "$project_root/build/logs"
if [[ ${1:-} == --source-only ]]; then
    sdk_path=$(xcrun --sdk iphonesimulator --show-sdk-path)
    log_path="$project_root/build/logs/ios-source.log"
    if ! swift build --package-path "$project_root/Packages/EarStudioKit" \
        --scratch-path "$project_root/build/ios-source-check" \
        --triple arm64-apple-ios17.0-simulator --sdk "$sdk_path" \
        --target EarStudioUI >"$log_path" 2>&1; then
        tail -n 80 "$log_path" >&2
        exit 1
    fi
    printf 'iOS source compilation passed; asset-catalog compilation was not checked. Log: %s\n' "$log_path"
else
    cd "$project_root/Packages/EarStudioKit"
    log_path="$project_root/build/logs/ios-package.log"
    if ! xcodebuild -scheme EarStudioUI -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$project_root/build/ios-package" CODE_SIGNING_ALLOWED=NO build >"$log_path" 2>&1; then
        tail -n 80 "$log_path" >&2
        printf '\nFull iOS check requires the iOS platform component in Xcode Settings > Components.\n' >&2
        exit 1
    fi
    printf 'Shared modules and resources compiled for iOS Simulator. Log: %s\n' "$log_path"
fi
