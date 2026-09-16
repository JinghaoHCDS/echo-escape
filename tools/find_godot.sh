#!/usr/bin/env bash
# Shared resolver: explicit override, PATH, then common macOS locations.
set -euo pipefail
if [[ -n "${GODOT_BIN:-}" && -x "$GODOT_BIN" ]]; then
  printf '%s\n' "$GODOT_BIN"
  exit 0
fi
for engine_name in godot godot4; do
  if command -v "$engine_name" >/dev/null 2>&1; then
    command -v "$engine_name"
    exit 0
  fi
done
for engine_path in "$HOME/Applications/Godot-4.6.1-stable/Godot.app/Contents/MacOS/Godot" /Applications/Godot.app/Contents/MacOS/Godot; do
  if [[ -x "$engine_path" ]]; then
    printf '%s\n' "$engine_path"
    exit 0
  fi
done
printf '%s\n' 'Godot 4.6.1 not found. Set GODOT_BIN to the executable path.' >&2
exit 1
