# tools/

Scripts for the engine fetch, gates, lints, traceability and provenance checks.

## L5 screenshots

`tools/gate.sh l5` renders the shots in `tests/visual/shots.json` under Xvfb with llvmpipe (`tools/l5.py`, `tools/l5_capture.gd`) and diffs them against `tests/visual/baselines/`; it needs the `xvfb` package and runs on fugaku only (FT-TST-003). A shot names a scene and, optionally, properties to set on its root before it enters the tree. `tools/gate.sh l5 --update-baselines` regenerates every baseline and `baselines/env.json`. `tools/l5.py --capture-only DIR [--shots FILE]` renders without comparing. The tolerance and the "baseline environment changed" check are described in the docstring of `tools/l5.py`. Any PR may regenerate baselines: say why in the PR body and compare the old and new images by eye (failing shots leave `build/l5/<name>.diff.png`).
