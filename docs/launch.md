# Launching Full Theta

How to start a game in milestone 1 (FT-M1-016): host one from the client, join one, run a dedicated server, and get back into a game after a crash. Every player runs the same executable.

## Builds

`tools/gate.sh l6` exports `build/linux/full-theta.x86_64` and `build/windows/full-theta.exe` (presets in `export_presets.cfg`) and smoke-runs the Linux server. Start the executable from a terminal to see its log. An export without a voice pack (`BundledPiper`, see `app/voice_setup.gd`) plays no voices: ship-computer lines show as subtitles only.

Ports: WebSocket 47801 (TCP), the web-station HTTP server on 47800 (TCP, only with `--http-root`) and discovery 47790 (UDP broadcast). On a LAN, allow these through the host's firewall.

## Host a game

Start the client, type a name, pick where to serve (one of this machine's LAN addresses so others can join, the first one by default, or **This computer only**), pick the session language and press **Host**. The client starts a headless server as a child process (`HostSession`, `app/host_session.gd`), joins it as the host and shows the lobby. When the host leaves or quits, the server stops.

**Dev: one client holds all stations** adds a lobby seat holding every station, so one person can play alone (FT-NET-029). The checkbox and the lobby's **All (dev)** seat show only in a client started with `--dev` (after `--`, e.g. `godot --path . -- --dev`). A dedicated server gets the seat with `--dev-all-stations`.

## Join a game

Servers bound to a LAN address announce themselves, and **Games on this network** lists them live; click one to join. When the list stays empty the menu says so: ask the host for the address, or scan their QR code. Only the first client on a computer can listen for them, so a second client on the same computer, or a server on another network, is joined by typing its address (`192.168.1.20` or `192.168.1.20:47801`) and pressing **Join**. A browser can't listen for games, so the browser menu has no list: it joins the host that served the page.

The host's **Network** list names each address with its interface (for example `192.168.1.20 (wlp2s0)`): pick the Wi-Fi or Ethernet one your friends share. Docker, VPN and tailnet addresses only reach people on those networks.

### Join from a phone

1. The host starts a game on a network address (not **This computer only**) and opens **How to join** in the lobby, or looks at the QR code under the lobby's title.
2. On the phone, join the same Wi-Fi, open the camera and scan the QR code, or type the address shown beside it into the browser.
3. The page joins by itself. Type your name when asked and tap **Done**.
4. Tap a station. The host presses **Start** once the crew covers every station.
5. If the page reloads or the phone sleeps, open the same link again: you return to your seat. If the game says it is open in another window, tap **Take back** there; if it says it can't reach the host, check the Wi-Fi and tap **Try again**, or **Leave**.

## Dedicated server

```bash
build/linux/full-theta.x86_64 --headless -- --server --bind 192.168.1.20 --name "Bridge night"
```

`--bind` is required: the one address to listen on, never every interface. The header of `app/server_main.gd` (`ServerMain`) lists every flag, among them `--port`, `--dev-all-stations`, `--language`, `--idle-exit-min`, `--http-root` (serve the web build for browser stations) and `--no-beacon`. The server prints `server: listening on ADDR:PORT, protocol N` and then `ready ws=ADDR:PORT http=ADDR:PORT` (http 0 when it serves no web build) once it is ready; stop it with Ctrl+C.

### HTTPS on a tailnet

Browser stations load faster over HTTPS: browsers accept brotli only there, which saves about 2 MB of the download (D294). Give the server a certificate and key with `--tls-cert` and `--tls-key` (absolute paths, PEM); it then serves HTTPS and WSS on the same ports, and the page connects over `wss://` because it was loaded over `https://`. Without the flags it serves plain HTTP as before; a game hosted from the client menu is always plain. On a Tailscale tailnet with HTTPS certificates turned on (admin console, DNS), the machine's own certificate works on every device of the tailnet:

```bash
name=$(tailscale status --json | jq -r '.Self.DNSName | rtrimstr(".")')   # host.tailnet.ts.net
sudo tailscale cert --cert-file ~/ft-tls/cert.pem --key-file ~/ft-tls/key.pem "$name"
sudo chown "$USER" ~/ft-tls/*.pem
# from the unpacked release package's folder:
./full-theta.x86_64 --headless -- --server --bind "$(tailscale ip -4)" \
  --http-root "$PWD/web" --tls-cert ~/ft-tls/cert.pem --tls-key ~/ft-tls/key.pem
```

Players open `https://host.tailnet.ts.net:47800/` (the certificate's name, not the IP address). The certificate lasts 90 days; run `tailscale cert` again to renew it, then restart the server. A self-signed certificate works for tests, but each browser must accept it first.

## Room hardware (OSC)

**Send the ship's hits, jumps and alerts to the room's lights.** Start the server, or the client you host from, with `--osc` and the addresses of your QLC+, Node-RED or Arduino:

```bash
build/linux/full-theta.x86_64 -- --osc 192.168.1.30:7700,192.168.1.31:9000
```

The game sends OSC 1.0 over UDP to each address and never listens. It accepts only addresses on your own network (`10.x`, `172.16-31.x`, `192.168.x`, `169.254.x`, `127.x`), up to 8. Without `--osc` it sends nothing. `<id>` is the crewed ship's id: `0` in a one-ship game.

| Address | Arguments | When |
|---|---|---|
| `/ft/ship/<id>/hit` | `1.0`, damage | the ship is hit; at most 10 a second |
| `/ft/ship/<id>/jump` | `1.0` | the jump drive spools |
| `/ft/ship/<id>/jump` | `0.0` | the ship arrives |
| `/ft/ship/<id>/destroyed` | `1.0` | the ship is destroyed |
| `/ft/ship/<id>/alert` | level / 2, level (int) | the crew changes the alert: 0 Normal, 1 Yellow, 2 Red |

The first argument is always between 0 and 1, so QLC+ can map each address to a channel. Node-RED and Arduino sketches can read the rest. The rules are `OscEmitter` in `net/osc_emitter.gd` (D470, D471).

> **Good to know:** a game hosted from the menu passes the client's `--osc` and `--packs` to its server, so start the client with the flags.

## Content packs

**Add ships and encounters from a JSON file.** Put pack files in a folder and start the server, or the client you host from, with `--packs` and that folder's absolute path. The format is in [packs.md](packs.md).

## Rejoin after a crash

If the host's client dies, its server keeps running. On the next start the client asks about it (FT-NET-003): **Rejoin** reconnects as host to the same ship and pick, **End it** stops it, **Leave it running** keeps it. An abandoned server exits by itself after 10 minutes without players (`--idle-exit-min`). A joined player whose client dies presses **Rejoin last game** on the next start.

## Test flags

`app/client_autopilot.gd` (`ClientAutopilot`) drives the menu without a mouse: `--auto-host BIND` or `--auto-join ADDR`, then `--screenshot PATH` and `--quit-after S`. Clients on one computer share their settings, token and pid files, so give each extra client its own `XDG_DATA_HOME`. A client with no display runs under Xvfb:

```bash
xvfb-run -a -s "-screen 0 1280x720x24" build/linux/full-theta.x86_64 \
  -- --auto-join 127.0.0.1 --screenshot /tmp/lobby.png --quit-after 15
```

## Troubleshooting

**Helm stops steering while you thrust (Linux laptop).** Linux pauses a laptop touchpad while a key is held ("Disable touchpad while typing"). Turn it off (GNOME: Settings > Mouse & Touchpad, or `gsettings set org.gnome.desktop.peripherals.touchpad disable-while-typing false`; KDE: System Settings > Touchpad) or use a mouse. The Controls page says so on Helm.
