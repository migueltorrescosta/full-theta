# Launching Full Theta

How to start a game in milestone 1 (FT-M1-016): host one from the client, join one, run a dedicated server, and get back into a game after a crash. Every player runs the same executable.

## Builds

`tools/gate.sh l6` exports `build/linux/full-theta.x86_64` and `build/windows/full-theta.exe` (presets in `export_presets.cfg`) and smoke-runs the Linux server. Start the executable from a terminal to see its log. An export without a voice pack (`BundledPiper`, see `app/voice_setup.gd`) plays no voices: ship-computer lines show as subtitles only.

Ports: WebSocket 47801 (TCP), the web-station HTTP server on 47800 (TCP, only with `--http-root`) and discovery 47790 (UDP broadcast). On a LAN, allow these through the host's firewall.

## Host a game

Start the client, type a name, pick where to serve (**This computer only**, or one of this machine's LAN addresses so others can join), pick the session language and press **Host**. The client starts a headless server as a child process (`HostSession`, `app/host_session.gd`), joins it as the host and shows the lobby. When the host leaves or quits, the server stops.

**Dev: one client holds all stations** adds a lobby entry holding every station, so one person can play alone (FT-NET-029). A dedicated server gets it with `--dev-all-stations`.

## Join a game

Servers bound to a LAN address announce themselves, and **Games on this network** lists them live; double-click one to join. Only the first client on a computer can listen for them, so a second client on the same computer, or a server on another network, is joined by typing its address (`192.168.1.20` or `192.168.1.20:47801`) and pressing **Join**.

## Dedicated server

```bash
build/linux/full-theta.x86_64 --headless -- --server --bind 192.168.1.20 --name "Bridge night"
```

`--bind` is required: the one address to listen on, never every interface. The header of `app/server_main.gd` (`ServerMain`) lists every flag, among them `--port`, `--dev-all-stations`, `--language`, `--idle-exit-min`, `--http-root` (serve the web build for browser stations) and `--no-beacon`. The server prints `server: listening on ADDR:PORT` once it is ready; stop it with Ctrl+C.

## Rejoin after a crash

If the host's client dies, its server keeps running. On the next start the client asks about it (FT-NET-003): **Rejoin** reconnects as host to the same ship and pick, **End it** stops it, **Leave it running** keeps it. An abandoned server exits by itself after 10 minutes without players (`--idle-exit-min`). A joined player whose client dies presses **Rejoin last game** on the next start.

## Test flags

`app/client_autopilot.gd` (`ClientAutopilot`) drives the menu without a mouse: `--auto-host BIND` or `--auto-join ADDR`, then `--screenshot PATH` and `--quit-after S`. Clients on one computer share their settings, token and pid files, so give each extra client its own `XDG_DATA_HOME`. A client with no display runs under Xvfb:

```bash
xvfb-run -a -s "-screen 0 1280x720x24" build/linux/full-theta.x86_64 \
  -- --auto-join 127.0.0.1 --screenshot /tmp/lobby.png --quit-after 15
```
