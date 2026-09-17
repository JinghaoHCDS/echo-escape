#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="$(bash tools/find_godot.sh)"
check_log="$(mktemp -t echo-escape-check.XXXXXX)"
trap 'rm -f "$check_log"' EXIT
run_checked() {
  "$GODOT_BIN" "$@" 2>&1 | tee "$check_log"
  # Godot can exit zero despite a runtime/script error. Reject either signal.
  if grep -Eq 'SCRIPT ERROR:|^ERROR:|^FAIL ' "$check_log"; then return 1; fi
}
run_checked --headless --path . --editor --import --quit
for test in phase_a acoustic_field sound hiding cabinet_sound monster hiding_monster gameplay hiding_integration playthrough audio occlusion input wave_visual; do
  if [[ -f "tests/${test}_test.gd" ]]; then
    run_checked --headless --path . --script "tests/${test}_test.gd"
  fi
done
if [[ "${1:-}" == "--graphics" ]]; then
  for test in sound cabinet_sound audio occlusion input wave_visual hiding_integration playthrough; do
    run_checked --path . --script "tests/${test}_test.gd"
  done
fi
git diff --check
