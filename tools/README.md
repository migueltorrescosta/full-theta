# tools/

Scripts for the engine fetch, gates, lints, traceability and provenance checks.

## L5 screenshots

`tools/gate.sh l5` renders the shots in `tests/visual/shots.json` under Xvfb with llvmpipe (`tools/l5.py`, `tools/l5_capture.gd`) and diffs them against `tests/visual/baselines/`; it needs the `xvfb` package and runs on fugaku only (FT-TST-003). A shot names a scene and, optionally, properties to set on its root before it enters the tree. `tools/gate.sh l5 --update-baselines` regenerates every baseline and `baselines/env.json`. `tools/l5.py --capture-only DIR [--shots FILE]` renders without comparing. The tolerance and the "baseline environment changed" check are described in the docstring of `tools/l5.py`. Any PR may regenerate baselines: say why in the PR body and compare the old and new images by eye (failing shots leave `build/l5/<name>.diff.png`).

## L4 multi-process network test

`tools/gate.sh l4` runs `tools/l4/run.sh`: a server and three headless client processes pinned to 2 cores (`taskset -c 0,1`), driven by intent files, with kills and relaunches (FT-TST-011, FT-TST-014). `tools/l4/repeat.sh N` runs it N times and writes `build/l4/repeat-summary.txt`. The scenarios, the intent format and the logs are in `tools/l4/README.md`.
