#!/bin/bash
# Archive and export locally for App Store Connect; does not upload or submit.
set -euo pipefail
[[ $# -eq 0 ]] || { printf 'Usage: APPLE_TEAM_ID=TEAM_ID %s\n' "$0" >&2; exit 2; }
project_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$project_root"
team=$(python3 - <<'PY'
import os, sys
sys.path.insert(0, 'Tools')
from apple_signing import identities, select_team
print(select_team(identities(), os.environ.get('APPLE_TEAM_ID')))
PY
)
mkdir -p build/logs build/Archives dist/iOS
metadata=()
while IFS= read -r setting; do metadata+=("$setting"); done < <(python3 Tools/build_metadata.py iOS --reserve)
[[ ${#metadata[@]} -eq 3 ]] || { printf 'Unable to reserve build metadata.\n' >&2; exit 1; }
archive="$project_root/build/Archives/EarStudioiOS.xcarchive"
options="$project_root/build/iOS-ExportOptions.plist"
python3 - "$team" "$options" <<'PY'
import plistlib,sys
with open(sys.argv[2], 'wb') as output:
    plistlib.dump(dict(method='app-store-connect', destination='export', signingStyle='automatic',
                      teamID=sys.argv[1], manageAppVersionAndBuildNumber=False, uploadSymbols=True), output)
PY
printf 'Archiving iPhone app for team %s…\n' "$team"
if ! xcodebuild -project EarStudioiOS.xcodeproj -scheme EarStudioiOS \
    -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath build/iOS-store -archivePath "$archive" \
    -allowProvisioningUpdates "DEVELOPMENT_TEAM=$team" CODE_SIGN_STYLE=Automatic \
    "${metadata[@]}" archive >build/logs/ios-archive.log 2>&1; then
    tail -n 70 build/logs/ios-archive.log >&2
    exit 1
fi
printf 'Exporting App Store Connect package…\n'
if ! xcodebuild -exportArchive -archivePath "$archive" -exportPath "$project_root/dist/iOS" \
    -exportOptionsPlist "$options" -allowProvisioningUpdates >build/logs/ios-export.log 2>&1; then
    tail -n 70 build/logs/ios-export.log >&2
    printf 'Archive retained at: %s\n' "$archive" >&2
    exit 1
fi
printf 'Archive: %s\nExport: %s/dist/iOS\nNo upload or App Review submission was performed.\n' "$archive" "$project_root"
