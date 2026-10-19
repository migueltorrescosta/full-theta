# tools/l4/

The L4 tier (T048, FT-TST-011, FT-TST-014): the server and three headless clients as separate Godot processes, all under `taskset -c 0,1` like the 2-vCPU CI runner, driven by intent files.

```bash
tools/gate.sh l4                       # every scenario once (imports first)
tools/l4/run.sh [--out DIR] [s1_session ...]   # the same without the import
tools/l4/repeat.sh 10                  # 10 runs in a row; build/l4/repeat-summary.txt
```

| File | Role |
|---|---|
| `run.sh` | Runs each scenario in its own subshell: starts the processes, kills and relaunches them, waits, runs `check.py`, kills what it started and fails on anything left behind. One line per scenario; logs in `build/l4/<run>/<scenario>/`. |
| `l4_client.gd` | The client runner: a `NetClient` executing an intent file step by step. |
| `check.py` | Per scenario: every final client launch passed, no bad snapshots, every client saw the same KIN at the same tick (convergence, with at least one tick seen by two clients), time from SIGKILL to the relaunched client's Welcome. |
| `repeat.sh N` | N runs in a row, with load average, result and per-scenario seconds per run. |
| `scenarios/<name>.sh` | The orchestration, sourced by `run.sh`; its intent files are in `scenarios/<name>/`. |

Environment: `L4_CPUS` (`0,1`), `L4_GRACE` (server `--grace-s`, 8: a relaunched client needs up to about 5 s to boot on two loaded cores), `L4_SCENARIO_S` (90, a scenario's time limit).

## Scenarios

- `s1_session`: a dedicated server. c1 picks Tactical first and holds its items (its name is in the snapshot's ownership), c2 joins Tactical, c3 picks Systems. Ready is refused (`coverage`) while Relay and Comms are uncovered. c2's command on mount 0 is rejected (`claimed`) and c2 sees c1's name; c1 releases mount 0, c2 claims it, and now c1's command is rejected. c2 moves to Ops, the lobby reports nothing uncovered, Ready starts the run and the tick moves. c1 is SIGKILLed and relaunched with its token file within the grace: same ship, pick, decoupled setting and flight claim, no pause, the other clients' snapshots never stop, and KIN converges. c3 writes pips (last writer named), then is SIGKILLed: no pause during the grace, then every client gets a pause naming Engineering and Science while snapshots keep flowing at a frozen tick; c3 relaunches, its session gets ship and pick back and the universe resumes.
- `s2_host_crash` (TECH-8): the host client hosts through `HostSession` (a server child with the secret in its environment, pid file in the run folder; Welcome `host` true) and plays Tactical with c2 (Systems) and c3 (Ops). It is SIGKILLed mid-run and relaunched: `OrphanCheck` says `offer_rejoin`, `HostSession.check_orphan` rejoins on the same ship and pick as the host, and c2 and c3 never miss a snapshot or see a pause. At the end the host stops its server (`HostSession.stop`).

## Client runner

```bash
godot --headless --path . -s res://tools/l4/l4_client.gd -- --url ws://HOST:PORT --name c1 \
  --intent FILE --log FILE.jsonl [--token-file FILE] [--run-dir DIR] [--max-s 120] [--set K=V]
```

It polls the client every frame and runs one step at a time; a waiting step fails after its `timeout` (15 s by default), a rejection or closed connection at once. Exit codes: 0 every step passed, 1 a step failed (or `--max-s` passed), 2 a bad command line or intent file. The token file is a `SessionTokenFile` (token, host, port, host secret), written on every Welcome (by `HostSession` in host mode) and read by `connect`.

The log has one JSON object per line, each with `ms` since the start and `ev`: `start` (with `unix_ms`), `step` (`n`, `line`, `ok`, `ms_taken`, `why`), `welcome`, `catalogue`, `event` (`type`, `seq`, `tick`, `payload`), `snap` (one per frame that applied snapshots: `tick`, `k` a hash of the KIN section, `gap_ms`), `note`, and `end` (`ok`, `why`, `stats`, `max_gap_ms`).

## Intent files

One step per line: `verb key=value ...`; `#` starts a comment. `$RUN` is the run folder, `$NAME` the client name, and `--set K=V` defines `$K` (`run.sh` sets `$GRACE` and `$PORT`). Values are ints, floats (`1.0`: commands need the decimal point), `true`/`false`/`null`, `"quoted strings"`, JSON arrays and objects, `Vector3(x, y, z)`, or bare strings.

Matchers are `path<op>value` on a dictionary. A path is dotted keys, array indices and `size`; a name applied to an array of dictionaries maps over it (`entries.id` is every entry's id). Operators: `=` (numbers compare as numbers), `!=`, `~=` contains (array element, dictionary key, substring), `!~` does not contain, `>`, `>=`, `<`, `<=`. Every waiting step takes `timeout=S`.

| Step | Does |
|---|---|
| `connect [url=] [resume=false] [expect=rejected]` | Hello with the stored token and host secret (unless `resume=false`); waits for Welcome. |
| `reconnect`, `drop`, `bye`, `forget_token` | `NetClient.resume()`, drop without Bye, Bye, remove the token file. |
| `pick ship= entry= [expect=ok\|REASON\|none]`, `release [expect=]` | Sends and waits for the answer: `picked`, `command_rejected` or `request_rejected`, compared by reason. |
| `ready [value=true]`, `claim item=`, `release_claim item=`, `abandon ship=`, `vote_abandon ship= vote=`, `takeover ship= entry=` | Sends the message; check the outcome with `expect_event`. |
| `command id=NAME kind=K field=value ...` | Sends a crew command; `id` names its seq for the next two. |
| `expect_rejected id= [reason=]`, `expect_accepted id= [for=1]` | Its CommandRejected arrives (with that reason); none arrives within `for` seconds. |
| `expect_welcome`, `expect_catalogue`, `expect_view` + matchers | Waits until the Welcome, Catalogue or snapshot view matches. The view has every `NetViewState` variable (`kin`, `blocks`, `contacts`, `tick`, ...), blocks also by name (`blocks.helm.decoupled`, `blocks.mounts.mounts.0.aim_set`), `stats` and `state`. |
| `expect_event type=T [keep=true]` + matchers on `{seq, tick, type, payload}` | Waits for a matching event after the cursor and moves the cursor past it. |
| `expect_no_event type=T for=S` + matchers | No matching event after the cursor for S seconds. |
| `expect_flowing [max_gap_ms=1000] [min_snapshots=1]` | Snapshots came since `mark`, none more than `max_gap_ms` apart. |
| `expect_tick_still for=S`, `expect_tick_moving [ticks=30]` | Snapshots arrive but the tick doesn't pass the view's or the last matched event's tick (run it after `expect_event type=pause`: the pause carries the tick the sim stopped at and may overtake that tick's snapshot); the tick advances. |
| `mark` | Moves the event cursor to now and restarts the gap watch. |
| `wait s=S`, `note msg=`, `exit` | Polls for S seconds; a log line; stop here as passed. |
| `signal name=X`, `await name=X`, `barrier name=X n=N` | Through files in the run folder: create `sig.X`; wait for it (from `run.sh` or another client); arrive at X and wait for N clients. |
| `host_spawn pid_file= [port=0] [grace=S] [publish=X]` | `HostSession.host()`: spawn the server child (with `--no-beacon` and the grace), wait until it joined as the host; `publish` writes the URL to `sig.X`. |
| `orphan_rejoin pid_file= [expect=offer_rejoin]` | A relaunched host's start: `OrphanCheck.inspect` must say `expect`; then `HostSession.check_orphan` answers REJOIN and waits until rejoined. |
| `host_stop` | `HostSession.stop()` (Bye, kill the server, remove pid and token files); waits until the process is gone. |

## Adding a scenario

Add `scenarios/<name>.sh` and `scenarios/<name>/*.intent`. The script runs inside `run.sh` with: `server [flags]` (dedicated server on a free port, sets `$URL`), `client NAME INTENT [flags]` (launches NAME again each call; logs `NAME.<launch>.jsonl`), `await X [S]`, `signal X`, `kill9 NAME`, `$out` (the scenario's log folder). `run.sh` then waits for every client to exit 0 and runs `check.py`.
