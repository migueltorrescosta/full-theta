# app/

Entry points: the main scene (`main.tscn`, `main.gd`) and the headless server: `godot --headless --path . -- --server --bind ADDR [--port N]`. `server_main.gd` lists every flag; `main.gd` builds the `NetServer` node (net/) and a `ServerLifecycle` node and adds them to the tree. The client comes in #7.

## Server process

- `server_main.gd` (`ServerMain`): the command line and `make_server()`, which also starts the static HTTP server for browser stations (`--http-root DIR`, on the bind address at the WebSocket port - 1, D108) and the LAN beacon (`--name`, `--discovery-port`, `--no-beacon`). `NetServer` polls both after the sim tick each frame.
- `server_lifecycle.gd` (`ServerLifecycle`): writes the pid file (`--pid-file`) once the server listens, keeps its `session_active` flag current, removes it on a clean exit, and quits after `--idle-exit-min` minutes without connections (FT-NET-003).
- `server_pid_file.gd` (`ServerPidFile`), `idle_exit_timer.gd` (`IdleExitTimer`): the record and the timer they use.

## Hosting (client side, no UI)

- `host_session.gd` (`HostSession`): the Host button's flow and the orphan rejoin (FT-NET-001, FT-NET-003, FT-M1-002, TECH-8). `host()` spawns the child, waits for its pid file, joins it as the host and stores the token (`SessionTokenFile`); `stop()` says Bye, kills the child and removes the pid and token files. `HostSession.check_orphan(choose)` runs on client start: it clears stale pid files and terminates orphans without a session by itself, and asks `choose` (rejoin, terminate or leave) about one with a session. Call `poll()` every frame.
- `host_launcher.gd` (`HostLauncher`): spawns this executable headless as the server child, bound to 127.0.0.1; the host secret (D127) goes through the `FT_HOST_SECRET` environment variable, since a command line is world-readable.
- `orphan_check.gd` (`OrphanCheck`): the orphan decision table and the process checks.

Tests: `tests/net/test_host_*.gd` (`test_host_flow.gd` spawns real server children) and `tests/net/test_lan_*.gd`.
