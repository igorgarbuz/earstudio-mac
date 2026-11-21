#!/bin/bash
set -euo pipefail
tools_dir=$(cd "$(dirname "$0")" && pwd)
exec python3 "$tools_dir/install_ios.py" "$@"
