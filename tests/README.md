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
