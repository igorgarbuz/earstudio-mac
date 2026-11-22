#!/bin/bash
# Notarize a signed DMG, staple its ticket, then regenerate its checksum.
set -euo pipefail
project_root=$(cd "$(dirname "$0")/.." && pwd)
profile=${NOTARY_KEYCHAIN_PROFILE:-earstudio-notary}
fail() { printf 'Notarization stopped: %s\n' "$*" >&2; exit 1; }
if [[ $# == 1 && "$1" == --check-credentials ]]; then
    xcrun notarytool history --keychain-profile "$profile" --output-format json >/dev/null
    exit 0
fi
[[ $# == 1 && "$1" == *.dmg && -f "$1" ]] || fail "Usage: $0 DMG | --check-credentials"
image_path=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
image_name=$(basename "$image_path")
# A failed attempt must not leave a stale checksum looking publishable.
rm -f "$image_path.sha256"
codesign --verify --strict "$image_path"
mkdir -p "$project_root/build/logs"
log_dir=$(mktemp -d "$project_root/build/logs/notarization.XXXXXX")
printf 'Submitting %s; logs: %s\n' "$image_name" "$log_dir"
xcrun notarytool submit "$image_path" --keychain-profile "$profile" \
    --wait --output-format json >"$log_dir/submission.json"
cat "$log_dir/submission.json"
submission_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$log_dir/submission.json")
xcrun notarytool log "$submission_id" --keychain-profile "$profile" "$log_dir/notarization.json"
python3 - "$log_dir/submission.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    sys.exit('Apple did not accept this submission; inspect the notarization log. Do not publish.')
PY
xcrun stapler staple "$image_path"
xcrun stapler validate "$image_path"
codesign --verify --strict "$image_path"
spctl --assess --type open --context context:primary-signature --verbose=2 "$image_path"
(
    cd "$(dirname "$image_path")"
    shasum -a 256 "$image_name" >"$image_name.sha256"
)
printf 'Notarized and verified: %s\n' "$image_path"
