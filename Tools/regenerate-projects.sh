#!/bin/bash
# Refresh both checked-in projects; --check fails on unstaged generated changes.
set -euo pipefail
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != --check ) ]]; then
    printf 'Usage: %s [--check]\n' "$0" >&2
    exit 2
fi
project_root=$(cd "$(dirname "$0")/.." && pwd)
cd "$project_root"
python3 Tools/generate_project.py
python3 Tools/generate_ios_project.py
if [[ "${1:-}" == --check ]]; then
    if ! git diff --exit-code -- EarStudioCompanion.xcodeproj EarStudioiOS.xcodeproj; then
        printf '\nGenerated projects changed. Review and stage both .xcodeproj directories with your changes, then rerun this check.\n' >&2
        exit 1
    fi
fi
