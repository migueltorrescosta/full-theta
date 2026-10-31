# Dev seat build time (#30)

The all-stations dev screen ("All stations (dev)", `--dev-all-stations`) was measured at 10-14 s to build headless (#27). This note says where that time went and what it costs now.

## Method

`tools/devseat_profile.gd` builds the dev seat's `StationScreen` from `StationFixture.context("all")` and times, in microseconds: each panel's script load and construction (`StationRegistry.make`), the whole `StationScreen.setup`, entering the tree, the first three frames, and then the settings menu's Controls tab (`ControlsPane.build`, then the keyboard diagram) for the six stations. The Controls tab is the only heavy child that the bare screen leaves out: the shell opens the menu on a first visit, and the real path (`ClientShell`, the shell tests) pays for it.

```
systemd-run --user --scope -p MemoryMax=4G -p MemorySwapMax=0 -E PATH="$PATH" -- \
  taskset -c 0,1,8,9 godot --headless --path . -s res://tools/devseat_profile.gd
```

"Before" is commit `2c659dd~1` (the parent of "Controls diagrams built lazily", #28), in a throwaway worktree; "after" is this branch. `DEVSEAT_ENTRY=helm` times a single station. The format errors the script prints are script mode lacking translations; they do not affect timing.

Timings were taken on fugaku with other strands running (load average 5-11), pinned to cores 0, 1, 8 and 9, so they are upper bounds; the lead remeasures on an idle machine.

## Where the time went (ms, headless, two runs per row)

| Part | Before | After |
|---|---|---|
| Panel scripts load and construct: helm / weapons / engineering / science / relay / comms | 138 / 73 / 54 / 74 / 78 / 56 (about 470) | about 60-90 each (about 350; the lobby preloads them in a session) |
| `StationScreen.setup`, all six panels | 513-622 | 349-541 |
| First frame (the shared ship model, built whole) | 697-988 | 79-86 (built in slices after the frame, D298) |
| `ControlsPane.build` (all six stations, eager) | 8345-8855 | 73-79 (diagrams built when shown, cached, D294) |
| Keyboard diagram shown, two frames | 25-48 (already built) | 78-92 (built here) |
| **Screen total (setup + frame 1)** | **1210-1328** | **424-624** |
| **Screen plus Controls tab** | **about 9600-10200** | **about 650-800** |

So the 10-14 s was almost all the Controls tab: six stations' keyboard and gamepad diagrams laid out eagerly (about 8.5 s), plus the ship model (about 0.7-1 s) in the first frame. Panel construction was never the problem (about 0.5 s together, about 60-100 ms a panel, mostly script loading).

## Tests

The same seven files (every one that builds the dev seat: `test_outcome_card`, `test_client_shell_l3`, `test_joint_views`, `test_station_screen`, `test_phone_frame`, `test_controls_diagram`, `test_lobby_and_overlays`), one gdUnit4 process, cores 0, 1, 8, 9:

| | Before (`2c659dd~1`, 58 tests) | After (76 tests) |
|---|---|---|
| Suite total | 90 s (36 s of tests) | 24.7 s |
| `test_shell_runs_again_after_a_win` | 19.6-35.6 s | 0.73-0.81 s |
| `test_shell_runs_lobby_to_station_with_the_dev_entry` | 7.3-15.4 s | 0.29 s |
| `test_the_dev_seat_has_numbered_station_tabs_and_a_hint` | 2.3 s | below 0.2 s |
| slowest of the rest | 6.1 s (`test_all_fifteen_views_are_modal_two_panel_screens`) | 0.71 s (same test) |

The range in "before" is two runs under different load. The after set has 18 more tests than the before set because #28 added them.

## Result

The fix was already in the branch's base: D294 (lazy, cached controls diagrams with an incremental layout, never built on phones) and D298 (the shared ship model fills in after the first frame). No further code change was needed for the dev screen, which builds in 0.4-0.6 s headless here (criterion: under 2 s). The remaining cost is the six panels' script loading (about 0.35 s), which the lobby already warms in a session (D296).

This strand changes only: the profiler, this note, and `test_outcome_card.gd`'s now-stale "10-14 s" comment with its wait lowered from 30 s to 15 s (no assertion touched).

Full gates on commit 9ad7a3f (cores 0, 1, 8, 9, other strands running): `gate.sh l0 l1` passed, L0 85 s, L1 403 s (467 + 471 + 650 tests in three shards). A first L1 attempt hung for 30 minutes in shard 1, in `test_layout_mode.gd > test_screen_arranges_for_orientation_and_phone` (101 % CPU, an `await` that never returned); that file passes in 0.4 s alone and the rerun passed, so it is a rare load-dependent hang unrelated to the dev seat. L1 before this work was not rerun for the whole suite (the old tree needs the same 400 s plus the 20-35 s of dev-seat waiting measured above).
