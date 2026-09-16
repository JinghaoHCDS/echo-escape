#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="$(bash tools/find_godot.sh)"
exec "$GODOT_BIN" --path . "$@"
