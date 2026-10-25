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

- `web/shell.html`: the page. Besides loading the engine (loading screen with scrolling tips), its `window.ft` object does what must happen inside a real tap handler: opens an HTML `<input>` over a registered text field (iOS only raises the keyboard that way), resumes the audio context and retries the keep-awake video on the first tap, and counts the times the page came back from a suspension.
- `web/web_session.gd` (`WebSession`): added by `MainMenu` to its `ClientShell` in a browser build: starts `KeepAwake` when welcomed, reconnects with the token (`NetClient.resume()`) when the page calls back a wake (`WebPage.on_wake`), publishes the shown panel (`window.ftPanel`), and runs the `?pick=ENTRY&ready=1` test hooks (`WebAutoplay`).
- `web/web_text_field.gd` (`WebTextField.attach(line_edit)`): backs a `LineEdit` with the shell's overlay input (D196; the page calls back with what was typed, `ft.listen`). `web/web_page.gd` (`WebPage`): user agent, wake callback, audio state. `web/join_helpers.gd` (`JoinHelpers`): the page's host as the join address; a browser joins at once unless the URL has `?join=0`.
- `web/keep_awake.gd` (`KeepAwake`): keeps a browser tablet's screen on (FT-NET-046).
- Export: `tools/release/export_web.sh DIR` (Web preset, slim template when built, then `web_patch.py`: audio guard, content-hashed names, videos, gzip). The slim engine template: `tools/release/build_web_template.sh` (D197; sizes and times in `docs/release.md`).

Tests: `tests/net/test_host_*.gd` (`test_host_flow.gd` spawns real server children), `tests/net/test_lan_*.gd` and `tests/app/web/`.

## Release packages

- `release_bundle.gd` (`ReleaseBundle`): the packed build info (`build: VERSION COMMIT`, printed at start) and the bundled web export's folder, which `HostSession.Options.http_root` defaults to, so the server child serves it (`--http-root`) (FT-ARC-022).
- `release_smoke.gd` (`ReleaseSmoke`): `-- --tts-smoke TEXT --out WAV [--voice NAME]`, the L6 check that the exported build runs its bundled Piper (FT-TST-019).
- `web/shell.html`: the web export's HTML shell without the secure-context check, and `web/keepawake.webm` (`tools/release/make_keepawake.sh`) that `web/keep_awake.gd` plays, all from S3 (D108). `docs/release.md` covers the packages.
