#!/usr/bin/env bash
# L0 static checks (FT-TST-001): formatting and lint, architecture lint,
# definitions, traceability, dialogue and translations, licences, and the tools' own fixture tests.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
godot=$(tools/get-godot.sh)
run() { uv run --quiet --project tools "$@"; }

# Our GDScript: everything tracked except vendored addons and lint fixtures.
mapfile -t scripts < <(git ls-files --cached --others --exclude-standard '*.gd' \
  | grep -vE '^(addons/|tools/tests/fixtures/)')

echo "l0: gdlint"; run gdlint "${scripts[@]}"
echo "l0: gdformat"; run gdformat --check "${scripts[@]}"
echo "l0: check-only"
for s in "${scripts[@]}"; do
  "$godot" --headless --path . --check-only --script "res://$s" >/dev/null 2>"$root/.godot/check.log" \
    || { cat "$root/.godot/check.log" >&2; echo "l0: check-only failed: $s" >&2; exit 1; }
done
echo "l0: definitions"  # FT-DAT-002: every .tres under content/ loads and validates
"$godot" --headless --path . -s res://tools/check_defs.gd 2>"$root/.godot/defs.log" \
  || { echo "l0: definitions failed (engine log: .godot/defs.log)" >&2; exit 1; }
# --- strand A ---
echo "l0: scenarios"  # FT-DAT-008: every scenario's ScenarioMeta is complete (FT-MIS-041)
"$godot" --headless --path . -s res://tools/check_scenarios.gd 2>"$root/.godot/scenarios.log" \
  || { cat "$root/.godot/scenarios.log" >&2; echo "l0: scenarios failed" >&2; exit 1; }
# --- end strand A ---
echo "l0: architecture"; run python tools/lint_arch.py
echo "l0: traceability"; run python tools/traceability.py --check
echo "l0: dialogue"; run python tools/check_dialogue.py  # FT-DAT-003, FT-DAT-004, FT-DAT-011
echo "l0: palette"; run python tools/check_palette.py  # FT-STN-006
echo "l0: licences"; run python tools/check_licences.py
echo "l0: tool tests"; run pytest -q tools/tests
