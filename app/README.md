# app/

Entry points: the main scene (`main.tscn`, `main.gd`) and the headless server: `godot --headless --path . -- --server --bind ADDR [--port N]`. `server_main.gd` lists every flag; `main.gd` builds the `NetServer` node (net/) and a `ServerLifecycle` node and adds them to the tree. The client comes in #7.

## Server process

- `server_main.gd` (`ServerMain`): the command line and `make_server()`, which also starts the static HTTP server for browser stations (`--http-root DIR`, on the bind address at the WebSocket port - 1, D108) and the LAN beacon (`--name`, `--discovery-port`, `--no-beacon`; only when `--bind` is not a loopback address, `ServerMain.is_loopback`; HTTP port 0 without `--http-root`). `NetServer` polls both after the sim tick each frame.
- `server_lifecycle.gd` (`ServerLifecycle`): writes the pid file (`--pid-file`) once the server listens, keeps its `session_active` flag current (`NetServer.session_active()`, defined there), removes it on a clean exit, and quits after `--idle-exit-min` minutes without connected players (`NetServer.bound_connections()`: connections that never said Hello don't count; FT-NET-003).
- `server_pid_file.gd` (`ServerPidFile`), `idle_exit_timer.gd` (`IdleExitTimer`): the record and the timer they use.

## Hosting (client side, no UI)

- `host_session.gd` (`HostSession`): the Host button's flow and the orphan rejoin (FT-NET-001, FT-NET-003, FT-M1-002, TECH-8). `host(options)` spawns the child with a `HostSession.Options(bind)` (`bind`, required: the LAN address the host picked or 127.0.0.1; `port`, `grace_s`, `idle_exit_min`, `beacon`, `http_root`, one server flag each), waits for its pid file, joins it as the host at the bind address (`join_address()`: loopback for a wildcard bind) and stores the token (`SessionTokenFile`, 0600); `stop()` says Bye, kills the child and removes the pid and token files. `HostSession.check_orphan(choose)` runs on client start: it clears stale pid files and terminates orphans without a session by itself, and asks `choose` (rejoin, terminate or leave) about one with a session. Call `poll()` every frame.
- `host_launcher.gd` (`HostLauncher`): spawns this executable headless as the server child with the options' flags; the host secret (D127) goes through the `FT_HOST_SECRET` environment variable (`--host-secret-env`), since a command line is world-readable.
- `orphan_check.gd` (`OrphanCheck`): the orphan decision table and the process checks. Every kill identifies the process again first (`kill_if_ours`; pid reuse).

## Web build

- `web/keep_awake.gd` (`KeepAwake`): keeps a browser tablet's screen on (FT-NET-046). Owned by the packaging strand.

Tests: `tests/net/test_host_*.gd` (`test_host_flow.gd` spawns real server children), `tests/net/test_lan_*.gd` and `tests/app/web/`.

## Release packages

- `release_bundle.gd` (`ReleaseBundle`): the packed build info (`build: VERSION COMMIT`, printed at start) and the bundled web export's folder, which `HostSession.Options.http_root` defaults to, so the server child serves it (`--http-root`) (FT-ARC-022).
- `release_smoke.gd` (`ReleaseSmoke`): `-- --tts-smoke TEXT --out WAV [--voice NAME]`, the L6 check that the exported build runs its bundled Piper (FT-TST-019).
- `web/shell.html`: the web export's HTML shell without the secure-context check, and `web/keepawake.webm` (`tools/release/make_keepawake.sh`) that `web/keep_awake.gd` plays, all from S3 (D108). `docs/release.md` covers the packages.
