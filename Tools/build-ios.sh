#!/bin/bash
# Compile/test only. Use install-ios.sh to detect, sign and install on an iPhone.
set -euo pipefail
project_root=$(cd "$(dirname "$0")/.." && pwd)
action=${1:-build}
[[ $# -le 1 ]] || { printf 'Usage: %s [build|test|device]\n' "$0" >&2; exit 2; }
case "$action" in
    build) destination='generic/platform=iOS Simulator'; configuration=Debug; action_args=(build) ;;
    device) destination='generic/platform=iOS'; configuration=Release; action_args=(build) ;;
    test)
        configuration=Debug
        simulator_id=${IOS_SIMULATOR_ID:-}
        if [[ -z "$simulator_id" ]]; then
            simulator_id=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; print(next((d["udid"] for group in json.load(sys.stdin)["devices"].values() for d in group if "iPhone" in d["name"]), ""))')
        fi
        [[ -n "$simulator_id" ]] || { printf 'Create an iPhone simulator in Xcode, or set IOS_SIMULATOR_ID.\n' >&2; exit 1; }
        destination="platform=iOS Simulator,id=$simulator_id"
        action_args=(test -parallel-testing-enabled NO)
        ;;
    *) printf 'Usage: %s [build|test|device]\n' "$0" >&2; exit 2 ;;
esac
mkdir -p "$project_root/build/logs"
log_path="$project_root/build/logs/ios-$action.log"
derived_data="$project_root/build/iOS"
if [[ "$action" == device ]]; then derived_data="$project_root/build/iOS-device"; fi
if ! xcodebuild -project "$project_root/EarStudioiOS.xcodeproj" -scheme EarStudioiOS \
    -configuration "$configuration" -destination "$destination" \
    -derivedDataPath "$derived_data" CODE_SIGNING_ALLOWED=NO \
    "${action_args[@]}" >"$log_path" 2>&1; then
    tail -n 90 "$log_path" >&2
    printf '\nFull log: %s\n' "$log_path" >&2
    exit 1
fi
printf 'iOS %s succeeded. Log: %s\n' "$action" "$log_path"
