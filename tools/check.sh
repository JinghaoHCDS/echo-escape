#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT_BIN:-/Users/jinghao/Applications/Godot-4.6.1-stable/Godot.app/Contents/MacOS/Godot}"
if [[ ! -x "$GODOT_BIN" ]]; then GODOT_BIN="$(command -v godot || command -v godot4)"; fi
check_log="$(mktemp -t echo-escape-check.XXXXXX)"
trap 'rm -f "$check_log"' EXIT
run_checked() {
  "$GODOT_BIN" "$@" 2>&1 | tee "$check_log"
  # Godot can exit zero despite a runtime/script error. Reject either signal.
  if grep -Eq 'SCRIPT ERROR:|^ERROR:|^FAIL ' "$check_log"; then return 1; fi
}
run_checked --headless --path . --editor --import --quit
for test in phase_a sound monster gameplay playthrough audio occlusion; do
  if [[ -f "tests/${test}_test.gd" ]]; then
    run_checked --headless --path . --script "tests/${test}_test.gd"
  fi
done
if [[ "${1:-}" == "--graphics" ]]; then
  for test in sound audio occlusion playthrough; do
    run_checked --path . --script "tests/${test}_test.gd"
  done
fi
git diff --check
