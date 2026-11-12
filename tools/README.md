# tools/

Scripts for the engine fetch, gates, lints, traceability and provenance checks. The Python tools (`tools/pyproject.toml`, `tools/tts/pyproject.toml`) need Python 3.12 or later (`requires-python`, set by numpy 2.5).

## Running the gates

`tools/gate.sh [TIER...]` imports the project and runs the tiers; with no argument it runs `ci` (`l0 l1`), the tiers CI runs. It prints the commit and one result per tier for the PR body.

| Tier | What | When | Needs | Time |
|---|---|---|---|---|
| `l0` | formatting, lint, architecture, definitions, traceability, retired words, dialogue, palette, licences, the tools' own tests (`tools/l0.sh`, 15 checks in parallel) | CI and before every PR | `uv`, `git`, Godot (fetched) | about 1 min |
| `l1` | every gdUnit4 suite, `tests/net` included, in `L1_SHARDS` processes (default 3) split by recorded time (`tools/l1_shards.py`, `tools/l1_times.json`); this covers what the spec calls L1 to L3 | CI and before every PR | the above | about 4 min |
| `l2` | the simulation-side suites only (`tests/sim`, `pairs`, `scenarios`, `director`) in one gdUnit4 process: a quick check while changing the sim, a subset of `l1` | while working | the above | 1 to 2 min |
| `l4` | a server and 3 client processes on 2 cores (`tools/l4/run.sh`), then the browser station (`tools/l4/web.sh`) | before a PR that touches the net or the web build | `node`, `npm`, Chromium (via `tools/l6`), export templates (1.3 GB, fetched) | about 6 min |
| `l4load` | 64 connections against a server on 2 cores (`tools/l4/load.sh`) | owner-run, fugaku | at least 8 CPUs | 2 to 3 min |
| `l5` | screenshots diffed against `tests/visual/baselines/` | before a PR that changes a screen | `xvfb`, fugaku's renderer | several min |
| `l6` | builds, inspects and runs the release packages (`tools/l6/run.sh`) | before a release | `wine`, `node`, Chromium | about 10 min |

`all` runs every tier except `l2`. The shell tiers share `tools/lib.sh` (server-ready line, CPU picker, waits that fail loudly); the L4 tiers start the server on `--port 0` and read its `ready ws=... http=...` line, pick two allowed CPUs, and print both; L6 keeps fixed ports, since the release build buffers its output (D389). Set `L4_CPUS` to pin them yourself. Other prerequisites: `python3`, `curl`, `unzip`, `nproc`; `gdb` with passwordless `sudo` for a hang's thread stacks; `systemd-run` for the bot batch. A hung L1 shard is stopped by `tools/run_limited.sh`, which reads `done.txt` written by `tests/thread_guard_hook.gd` to tell a hang at exit from a hang in a test.

## L5 screenshots

`tools/bake_ships.gd` bakes the ships (`content/ships/looks.json` and `tools/ship_builder.gd` into `content/ships/baked/`, D308; the roughness and normal maps are shared by all looks, D317): run `godot --headless --path . -s res://tools/bake_ships.gd` after changing either and commit the result; L0's `ships` check (`-- --check`) fails when a baked ship is stale.

`tools/gate.sh l5` renders the shots in `tests/visual/shots.json` under Xvfb with llvmpipe (`tools/l5.py`, `tools/l5_capture.gd`) and diffs them against `tests/visual/baselines/`; it needs the `xvfb` package and runs on fugaku only (FT-TST-003). A shot names a scene and, optionally, properties to set on its root before it enters the tree and its own `"size": [w, h]` (default the manifest's `size`). `tools/gate.sh l5 --update-baselines` rewrites only the baselines whose new render fails the comparison (a shot within the tolerance stays byte-identical, so unchanged shots don't churn git history), new shots, and `baselines/env.json`. `tools/l5.py --capture-only DIR [--shots FILE]` renders without comparing. The tolerance and the "baseline environment changed" check are described in the docstring of `tools/l5.py`. Any PR may regenerate baselines: say why in the PR body and compare the old and new images by eye (failing shots leave `build/l5/<name>.diff.png`).

## L4 multi-process network test

`tools/gate.sh l4` runs `tools/l4/run.sh`: a server and three headless client processes pinned to 2 cores (`taskset -c 0,1`), driven by intent files, with kills and relaunches (FT-TST-011, FT-TST-014). `tools/l4/repeat.sh N` runs it N times and writes `build/l4/repeat-summary.txt`. The scenarios, the intent format and the logs are in `tools/l4/README.md`.

`tools/l4/web.sh` (run by `tools/gate.sh l4` after the scenarios) is the browser smoke test (FT-TST-021, FT-NET-013, FT-NET-046, FT-AUD-017): it exports the web build (`tools/release/export_web.sh`), serves it from a dedicated server on 2 cores, and drives it with headless Chromium on the same 2 cores, one worker (`tools/l4/web_station.mjs`; needs `npm ci` in `tools/l6` once, which the script does). The page joins by itself, takes Tactical through the `?pick=tactical&ready=1` hooks, unlocks audio after a tap, plays, is woken after a simulated suspension, and one screenshot must not be blank. `tools/l4/web_check.py` then reads the server log (joins, the resumed join, commands, snapshot ages). Logs and `shot.png` in `build/l4web/`.

## HTTP budget

`tools/static_server_profile.gd` times the search for a request head's end over a whole 8 KiB headerless request, the most one `StaticServer` poll searches, against the 400 µs per-frame budget (FT-NET-039, D108). It is wall-clock, so a manual check on an idle host, not a gate test: the L3 test counts the bytes searched instead. Run `taskset -c 0,1 godot --headless --path . -s res://tools/static_server_profile.gd` and record the load average with the result.

`tools/devseat_profile.gd` times each station panel, the all-stations `StationScreen` and the settings menu's Controls tab headless (#30; results in `docs/research/devseat-profile.md`). Wall-clock, so a manual check: run `taskset -c 0,1 godot --headless --path . -s res://tools/devseat_profile.gd` on a quiet host.

## Release packaging and L6

`tools/release/build.sh VERSION OUT_DIR` builds, packages and inspects the Linux, Windows and macOS release packages (`fetch.py`, `prerender.sh`, `web_patch.py`, `package.py`, `inspect_packages.py`, `notes.py`; pins in `piper.json`). `.github/workflows/release.yml` runs it on version tags. `tools/gate.sh l6` runs it on the working tree and then runs the Linux and Windows packages (`tools/l6/run.sh`). See `docs/release.md`.
