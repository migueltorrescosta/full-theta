# app/

Launch instructions for players are in `docs/launch.md`. Entry points: the main scene (`main.tscn`, `main.gd`) and the headless server: `godot --headless --path . -- --server --bind ADDR [--port N]`. `server_main.gd` lists every flag; `main.gd` builds the `NetServer` node (net/) and a `ServerLifecycle` node and adds them to the tree. Without `--server`, `main.gd` starts the client's `MainMenu`.

## Server process

- `server_main.gd` (`ServerMain`): the command line and `make_server()`, which also starts the static HTTP server for browser stations (`--http-root DIR`, on the bind address at the WebSocket port - 1, D108) and the LAN beacon (`--name`, `--discovery-port`, `--no-beacon`; only when `--bind` is not a loopback address, `ServerMain.is_loopback`; HTTP port 0 without `--http-root`). `NetServer` polls both after the sim tick each frame.
- `server_lifecycle.gd` (`ServerLifecycle`): writes the pid file (`--pid-file`) once the server listens, keeps its `session_active` flag current (`NetServer.session_active()`, defined there), removes it on a clean exit, and quits after `--idle-exit-min` minutes without connected players (`NetServer.bound_connections()`: connections that never said Hello don't count; FT-NET-003).
- `server_pid_file.gd` (`ServerPidFile`), `idle_exit_timer.gd` (`IdleExitTimer`): the record and the timer they use.

## Hosting (client side, no UI)

- `host_session.gd` (`HostSession`): the Host button's flow and the orphan rejoin (FT-NET-001, FT-NET-003, FT-M1-002, TECH-8). `host(options)` spawns the child with a `HostSession.Options(bind)` (`bind`, required: the LAN address the host picked or 127.0.0.1; `port`, `grace_s`, `idle_exit_min`, `beacon`, `http_root`, `language`, `dev_all`, one server flag each), waits for its pid file, joins it as the host at the bind address (`join_address()`: loopback for a wildcard bind) and stores the token (`SessionTokenFile`, 0600); `stop()` says Bye, kills the child and removes the pid and token files. `HostSession.check_orphan(choose)` runs on client start: it clears stale pid files and terminates orphans without a session by itself, and asks `choose` (rejoin, terminate or leave) about one with a session. Call `poll()` every frame.
- `host_launcher.gd` (`HostLauncher`): spawns this executable headless as the server child with the options' flags; the host secret (D127) goes through the `FT_HOST_SECRET` environment variable (`--host-secret-env`), since a command line is world-readable.
- `orphan_check.gd` (`OrphanCheck`): the orphan decision table and the process checks. Every kill identifies the process again first (`kill_if_ours`; pid reuse).

## Client menu

- `main_menu.gd` (`MainMenu`, T049): Name (persisted in `ClientSettings`), Host (bind "This computer only" or a LAN address from `bind_addresses()`, session language, and "Dev: one client holds all stations", which sets `HostSession.Options.dev_all` and so `--dev-all-stations`), Join (the live `LanBrowser` list, or a typed address through `LanBrowser.parse_address`), Rejoin (a stored `SessionTokenFile` without a host secret), Settings, Quit. On start it runs `HostSession.check_orphan` twice (`_check_orphan`): first answering "leave" to learn whether there is a question, then with the player's answer from a dialog (rejoin, end it, leave it running). A welcomed client goes to `ClientShell` (stations/); when the player leaves, a host stops its server and a joined client removes its token.
- `client_autopilot.gd` (`ClientAutopilot`): test flags that drive the menu without a mouse (`--auto-host`, `--auto-join`, `--screenshot`, `--quit-after`); `main.gd` adds it when one is given. `docs/launch.md` uses them.

## Web build

- `web/keep_awake.gd` (`KeepAwake`): keeps a browser tablet's screen on (FT-NET-046). Owned by the packaging strand.

Tests: `tests/net/test_host_*.gd` (`test_host_flow.gd` spawns real server children), `tests/net/test_lan_*.gd` and `tests/app/web/`.
