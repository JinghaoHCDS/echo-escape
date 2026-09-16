#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-/Users/jinghao/Applications/Godot-4.6.1-stable/Godot.app/Contents/MacOS/Godot}"
if [[ ! -x "$GODOT_BIN" ]]; then GODOT_BIN="$(command -v godot || command -v godot4)"; fi
exec "$GODOT_BIN" --path . "$@"
