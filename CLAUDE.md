# Instructions for agents

- The spec in `docs/spec/` is the source of truth. Requirements have stable IDs (`FT-NET-012`); cite them in code comments for non-obvious rules, in tests, and in PR bodies.
- `docs/decisions.md` records the owner's decisions. Don't contradict one silently: ask the owner, then record the new decision and update the spec in the same PR.
- `docs/plan/task-breakdown.md` holds the fine-grained tasks (T001…, E01…) that each GitHub issue absorbs. Use its verification criteria; the issue body is the checklist that counts.
- One issue, one PR. Large issues are split across sub-agents by absorbed task ID, still landing as one PR.
- Never copy EmptyEpsilon code or assets: EmptyEpsilon is GPL-2.0-only, which is incompatible with this GPL-3.0 project. Record the source and licence of every third-party asset in the provenance manifest (FT-LIC).
- The simulation (`sim/`) stays free of rendering, networking and scene-tree dependencies.

## Gate conventions

- All GDScript is typed; untyped declarations are errors (`project.godot`), and code passes `gdlint` and `gdformat` (`.gdlintrc`).
- `sim/`, `director/`, `scenarios/` and `shared/` stay pure: no `extends Node`, SceneTree, I/O, `load()`, `preload()` or `ResourceLoader`, and `shared/` names no other module. `tools/lint_arch.py` enforces the rules (spec §2.2).
- Tests name the FT ids they verify with `# FT:` tags (`tests/README.md`); rerun `tools/traceability.py` after changing tags or spec ids.
- New files under `assets/` or `addons/` need an entry in `content/provenance.json` (`docs/provenance.md`).
- Run `tools/gate.sh` before marking a PR ready and put its output in the PR body (`.github/pull_request_template.md`).
