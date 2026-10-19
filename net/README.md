# net/

Protocol, server session and client transport over WebSocket (FT-NET-004). The wire format is in `docs/protocol.md`. `net/` may name `sim/`, `sim/api/`, `director/`, `shared/` and content; clients (#7) name only `net/`.

## Files

| File | Role |
|---|---|
| `net_protocol.gd` | Message types, schemas, control-message codec, `PROTOCOL_VERSION`. |
| `net_codec.gd` | Fixed point, integer dead reckoning, wrap-aware residuals, quaternions (from S9). |
| `net_block.gd` | Schema-driven field blocks for the station field sets. |
| `station_views.gd`, `station_def.gd` | **The one data-driven place**: the tables every `StationDef` is built from (catalogue entries and load tags, sections per station, block field sets and their getters, command kinds, claimable items and ship-wide controls, which sim events each station gets), view keys and difficulty-toggle sets. |
| `sections/` | One class per snapshot section, each extending `SnapshotSection` (`snapshot_section.gd`): `kin_section.gd` (`KinSection`), `block_section.gd` (`BlockSection`), `contacts_section.gd` (`ContactsSection`), `near_section.gd` (`NearSection`) with the faction's `orient_model.gd` (`OrientModel`), `projectiles_section.gd` (`ProjectilesSection`), `ownership_section.gd` (`OwnershipSection`). |
| `snapshot_builder.gd` | Advances the sections a snapshot needs; assembles, chunks and caches one message per view key. |
| `sim_copy.gd` | Detached copy of a `SimWorld` for the net thread. |
| `net_chunker.gd`, `net_send_queue.gd` | Chunks, bundles, two lanes (from S4). |
| `net_resync.gd`, `net_event_outbox.gd`, `net_event_inbox.gd` | Stall policy; per-session reliable events, server and client side. |
| `net_sessions.gd`, `net_session.gd`, `net_token_bucket.gd` | Tokens, the session record, the rate limit for commands and requests. |
| `session_token_file.gd` | `SessionTokenFile`: the client's stored token (and host secret), saved 0600, for a rejoin after a relaunch. |
| `net_transport.gd` | The net thread: sockets, queues, encoder. |
| `server_session.gd` | Main-thread session logic: handshake, lobby and Start, picks, claims, grace, pause, abandon, takeover. |
| `net_coverage.gd`, `net_claims.gd`, `net_abandon_vote.gd` | The pure rules: coverage check, claims, abandon vote. |
| `command_gate.gd` | Command validation. |
| `net_server.gd` | The server `Node`: sim loop and composition. |
| `load_probe.gd` | The load gate's probe (`--probe-out`, dev and test only, D161): tick-frame timings and the measured window; `NetTransport.probe` records the net thread's side. |
| `net_client.gd`, `net_view_state.gd` | Headless client library and the client-side view state. |
| `lan_beacon.gd`, `lan_browser.gd` | LAN discovery: `LanBeacon` (server side) and `LanBrowser` (the client's host list, and `parse_address()` for a typed address). Wire layout in `docs/protocol.md` ("Discovery"). |
| `static_server.gd` | `StaticServer`: the static HTTP server for the web export (`docs/protocol.md`, "Static HTTP"). |
| `voice/` | The host voice service (E10): `VoiceService`, the synth interface `VoiceSynth`, the Piper adapters (`PiperProcessSynth`, the shared process half; `PiperStreamSynth`, `PiperBinarySynth`), `PcmStitch`, `DialogueLines`; contracts in `audio/README.md`. |

## Threads

The server has two threads (FT-NET-040, D111).

**Main thread** (`NetServer._process`): `ServerSession.process()` handles the inbound messages and lapses sessions whose grace ended, then, while `ServerSession.sim_running()` (a ship started, no pause), `SimWorld.advance()` steps the sim at 60 Hz from its own accumulator, `ServerSession.after_ticks()` turns sim rejections into `CommandRejected`, records last writers and routes the tick's events, and every second tick `NetTransport.post_state(SimCopy.capture(world))` hands over the state. In the lobby and during a pause the sim doesn't step: while a session holds a pick, a snapshot goes out every 33 ms of wall clock, encoded from the one copy captured when the sim stopped (`NetTransport.repost_state()`); with no pick, none. The capture is the only snapshot work on the sim thread: it duplicates each table variable (packed arrays copy on write), and the net thread rebuilds a detached `SimWorld` from it with `SimCopy.restore` (about 0.2 ms capture for M1 on fugaku, 0.6 ms at 100 ships).

**Net thread** (`NetTransport._run`, a loop with a 1 ms sleep) owns every socket: accept, poll, read, unbundle, decode, acks, the per-connection send queues and `NetResync`, the per-session `NetEventOutbox`, the `SnapshotBuilder`, and the pump. It never touches the live world.

They talk through two mutex-protected queues in `NetTransport`:

- main to net (`_ops`): `send(conn, bytes)`, `close(conn, code, reason)`, `bind(conn, session, welcome, view_key)`, `set_view(session, view_key)`, `post_event(sessions, tick, type, payload)` (the net thread finds each session's connection in its session → `Conn` map), `post_state(copy)` (the newest wins), `post_ownership(ship, table)` (claims and last writers for the OWNERSHIP section), `repost_state()` (re-encode the last state), `post_voice(session, bytes)`;
- net to main (`take_inbound()`): `[conn, message]`, with `NetTransport.CLOSED` when a connection closes. Acks never reach the main thread.

`stats()` publishes counters every 20 ms: snapshots, sends, delta and full messages, and per connection bytes, WebSocket messages, fulls, deltas, skipped, stalls, malformed messages (errors), and `close_code` while closing. `open_connections()` and `bound_connections()` (connections with a session) read the published stats under the mutex without copying them.

Client limits (net thread): stream 0 only, 64 KiB messages, Hello within 5 s, 16 connections without a session, close past 256 KiB queued without a view key (`docs/protocol.md`, "Transport" and "Rates and limits").

Who owns what: the main thread owns sessions (`NetSession`, `NetSessions`), picks, claims, the pause, validation and the sim; the net thread owns connections (`conn` ids), event sequence numbers and acks, snapshot sequence numbers and the view-key cache. Sessions and connections meet only through `bind` and `set_view`.

## Session rules

`ServerSession` keeps every rule in one place; the lobby, claims, pause and rejoin semantics are in `docs/protocol.md` ("Lobby, claims and the pause"):

- **Stations** (T042): `StationViews.def(entry)` (`StationDef`), `stations_of(entry)` (the def's own array: read-only), `is_crew(entry)`, `event_audience()` with `StationViews.EVENT_STATIONS`, difficulty toggles in `NetSession.toggles` (part of the view key; no M1 field depends on them).
- **Lobby** (T043): `pick_rule()` (one Captain per ship, no mid-run change that breaks coverage), `_on_ready` (Start), `NetCoverage`, `lobby_state()` (the `lobby` event), `launch()`. `_publish()` recomputes lobby states only when `_lobby_dirty` is set (picks, pause changes, Start, Hello, sim events); `crew_ships()` is cached (read-only).
- **Claims** (T044): `claim_rule(session, command)`, which `CommandGate.check` calls for every command; `_on_claim`; `NetClaims` (`settle()`: alone on a station holds its claims); `StationViews.item_of()`; `_wrote()` (last writers); `_publish()` posts the OWNERSHIP tables.
- **Grace, pause, abandon, takeover** (T045): `NetSessions.expire()` lapses sessions on the wall clock; `_lapse()`, `_restore()` (rejoin), `_refresh_pause()`, `sim_running()` (which `NetServer` checks before stepping), `_on_abandon`, `_on_abandon_vote` (`NetAbandonVote`), `_on_takeover`, `_abandon()` (submits the logged `AbandonShipCommand`).
- **Session cap** (T046): `admit_rule()` caps at 64. `by_id` holds live sessions (connected or within grace); a lapsed session leaves it and comes back on rejoin.
- **T046/T047** (host process, LAN): `NetServer.start_http()` and `start_beacon()` poll the static HTTP server and the LAN beacon after the tick; `app/ServerLifecycle` owns the pid file and idle exit (it idles on `NetServer.bound_connections()`, so connections without a session don't keep the server up); `app/HostSession` is the Host flow and orphan rejoin.

## How to add …

- **A message**: add the type to `NetProtocol.Type`, its schema to `SCHEMAS`, add it to `FROM_CLIENT` if clients send it, add a sample to `tests/net/test_net_protocol.gd`, a handler to `ServerSession._handlers`, an intent method to `NetClient`, and a row to `docs/protocol.md`. Bump `PROTOCOL_VERSION` if old peers would misread it.
- **A field of a block section** (status, Helm, Engineering, mounts): one `[name, type]` entry in `StationViews.BLOCKS[kind]` and one line in the matching getter (`_status`, `_helm`, …). Encoding, change detection and the client decode follow; `test_net_codec.gd` round-trips every block.
- **A section**: a value in `StationViews.Section`, a class under `sections/` (extend `SnapshotSection`: `update()` returns the delta, `full()` the model; a static `apply()` for the client), a case in `SnapshotBuilder._make()` and `NetViewState._apply_section()`, and the kind in `STATION_SECTIONS` for the stations that see it. Faction-owned sections also need `SnapshotBuilder._owner()`.
- **A station or catalogue entry**: `StationViews.STATIONS` (or `ENTRIES` for a joint view or seat, with its load tag and stations), `STATION_SECTIONS`, `STATION_COMMANDS`, `STATION_CLAIMS`, `STATION_CONTROLS`; the `StationDef` follows (joint views take the union of their stations).
- **A claimable item or ship-wide control**: its kind under its station in `STATION_CLAIMS` or `STATION_CONTROLS`, its commands in `COMMAND_ITEMS` (with the index field), and its items in `claim_items()`.
- **A crew command**: the sim class in `SimCommands`, then its kind under its station in `STATION_COMMANDS`; a command missing there is server-only.

## Client library

`NetClient` is poll-driven (call `poll()` every frame; no thread):

- `connect_to(url)` sends Hello (with `token` and `host_secret` if set) once the socket opens; `state` goes `CONNECTING` → `WELCOMED`, or `REJECTED` with `reject_reason`, or `CLOSED`.
- `welcome`, `catalogue`, `token`, `session_id`; `view` (`NetViewState`: `kin`, `blocks[kind]`, `contacts`, `near`, `projectiles`; helpers `own_position()`, `contact_position(id)`, `callsign(id)`).
- Intents: `pick(ship, entry)`, `release_pick()`, `set_ready(bool)` (Start), `claim(item)`, `release_claim(item)`, `abandon(ship)`, `vote_abandon(ship, bool)`, `takeover(ship, entry)`, `command(dict) -> seq`, `helm(throttle, rotation)`, `fire(mount)`, `set_pips(kind, pips)`, `bye()`.
- `view.ownership` holds the OWNERSHIP section (claimers and last writers of the view's stations); lobby, claim, pause and vote state arrive as events (`docs/protocol.md`).
- Rejoin after a relaunch: save `token` with `SessionTokenFile` after Welcome, and set `token` from it before `connect_to()`.
- `take_events()` returns the delivered events in order (`CommandRejected` is `type == "command_rejected"`).
- Acks are automatic: a snapshot that fails to apply sets `view.need_full`, and the next Ack carries snap −1 so the server sends a full one. `drop()` and `resume()` reconnect with the token. Test hooks: `paused` (a stalled reader), `keep_raw`, `arrivals`, `send_raw()`.

## Tests

`tests/net/`: codec, protocol, chunking and resync units, the rule units (`test_net_*_rules.gd`, `test_net_stations_defs.gd`), the snapshot pipeline on the real M1 sim, and the L3 suites (server and clients over loopback in one process, port 0): `test_net_server.gd` (transport), `test_net_stations_filter.gd`, `test_net_lobby_l3.gd`, `test_net_claims_l3.gd`, `test_net_reconnect_l3.gd`, `test_net_pause_l3.gd`. `net_harness.gd` (`NetHarness`) is their shared helper: servers, clients, event logs and polling waits with generous timeouts (no fixed sleeps that assume speed), for reuse by the L4 bots. `tools/gate.sh l3` runs only `tests/net`, pinned to 2 cores; `l1` runs them with everything else (one gdUnit invocation serves both).
