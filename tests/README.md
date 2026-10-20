# tests/

gdUnit4 tests; each names the FT ids it verifies (FT-TST-016).

## Naming FT ids

Put a `# FT:` comment line directly above each test function, listing the ids it verifies, comma-separated:

```gdscript
# FT: FT-TST-001
func test_runner_works() -> void:
```

A `# FT:` line at the top of a file tags the whole file. The same convention applies to the Python tool tests in `tools/tests/`. FT ids elsewhere in comments or names don't count.

`tools/traceability.py` reads these tags and writes `docs/traceability.md`; `gate.sh l0` runs it with `--check`, which fails on a stale map or a tag naming an unknown or removed id. Rerun `uv run --project tools python tools/traceability.py` after changing tags. Ids verified by a playtest or owner step go in `docs/traceability-manual.md` with an issue link.

## Definitions in tests

Definitions are read-only (FT-ARC-020), in tests too: `load()` hands every test the same cached resource while anything holds it, so a change leaks into later tests. To vary one, copy what you change: `def.duplicate()` for the ship's own numbers, and copy a sub-resource from its own file (each subsystem, mount and weapon is one) before changing it, since `duplicate(true)` shares those. `TestDefs.all_defs()` and `TestDefs.hashes()` check that a run leaves every definition as it was.

## Golden replays

`tests/golden/` holds the golden replay of the M1 encounter (FT-TST-009): `m1_encounter.cmdlog` is a `CommandLog` text (`sim/core/command_log.gd`) and `m1_encounter.expected.cfg` the final tick, state hash, platform and readable values it must reach. `tests/sim/replay/test_golden_replay.gd` replays the log and compares; it never writes in a normal run. The state hash must match exactly only on the platform the golden was recorded on (same engine version, OS, CPU architecture and, on Linux, glibc version, since libm results differ between glibc versions); elsewhere the readable values are compared within tolerance. After an intended sim change, regenerate both files and commit them with that change:

```bash
FT_UPDATE_GOLDEN=1 /path/to/godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  --add res://tests/sim/replay/test_golden_replay.gd --ignoreHeadlessMode
```

## L4 network scenarios

The multi-process network tests are not gdUnit4 suites: `tools/gate.sh l4` runs the scenarios in `tools/l4/scenarios/`, each a shell script and one intent file per client (`tools/l4/README.md`). They verify FT-TST-011 and FT-TST-014 by a gate run rather than `# FT:` tags; record the passing commit in the PR body.
