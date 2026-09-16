#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p builds
# Export only after the matching official export templates are installed.
exec bash tools/run.sh --headless --export-release "${1:-macOS}"
