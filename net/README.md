# net/

Protocol, server session and client transport over WebSocket (FT-NET-004). The wire format is in `docs/protocol.md`. `net/` may name `sim/`, `sim/api/`, `director/`, `shared/` and content; clients (#7) name only `net/`.

## Files

| File | Role |
|---|---|
| `net_protocol.gd` | Message types, schemas, control-message codec, `PROTOCOL_VERSION`. |
| `net_codec.gd` | Fixed point, integer dead reckoning, wrap-aware residuals, quaternions (from S9). |
| `net_block.gd` | Schema-driven field blocks for the station field sets. |
| `station_views.gd` | **The one data-driven place**: catalogue entries, joint views, sections per station, block field sets and their getters, command kinds per station, view keys. |
| `sections/` | One class per snapshot section (`KinSection`, `BlockSection`, `ContactsSection`, `NearSection` with the faction's `OrientModel`, `ProjectilesSection`). |
| `snapshot_builder.gd` | Advances the sections a snapshot needs; assembles, chunks and caches one message per view key. |
| `sim_copy.gd` | Detached copy of a `SimWorld` for the net thread. |
| `net_chunker.gd`, `net_send_queue.gd` | Chunks, bundles, two lanes (from S4). |
| `net_resync.gd`, `net_event_outbox.gd`, `net_event_inbox.gd` | Stall policy; per-session reliable events, server and client side. |
| `net_sessions.gd`, `net_session.gd`, `net_token_bucket.gd` | Tokens, the session record, the command rate limit. |
| `net_transport.gd` | The net thread: sockets, queues, encoder. |
| `server_session.gd` | Main-thread session logic and its hooks. |
| `command_gate.gd` | Command validation. |
| `net_server.gd` | The server `Node`: sim loop and composition. |
| `net_client.gd`, `net_view_state.gd` | Headless client library and the client-side view state. |
| `voice/` | The host voice service (E10): `VoiceService`, the Piper adapters (`PiperStreamSynth`, `PiperBinarySynth`), `PcmStitch`, `DialogueLines`; contracts in `audio/README.md`. |

## Threads

The server has two threads (FT-NET-040, D111).

**Main thread** (`NetServer._process`): `ServerSession.process()` handles the inbound messages, `SimWorld.advance()` steps the sim at 60 Hz from its own accumulator, `ServerSession.after_ticks()` turns sim rejections into `CommandRejected` and routes the tick's events, and every second tick `NetTransport.post_state(SimCopy.capture(world))` hands over the state. The capture is the only snapshot work on the sim thread: it duplicates each table variable (packed arrays copy on write), and the net thread rebuilds a detached `SimWorld` from it with `SimCopy.restore` (about 0.2 ms capture for M1 on fugaku, 0.6 ms at 100 ships).

**Net thread** (`NetTransport._run`, a loop with a 1 ms sleep) owns every socket: accept, poll, read, unbundle, decode, acks, the per-connection send queues and `NetResync`, the per-session `NetEventOutbox`, the `SnapshotBuilder`, and the pump. It never touches the live world.

They talk through two mutex-protected queues in `NetTransport`:

- main to net (`_ops`): `send(conn, bytes)`, `close(conn)`, `bind(conn, session, welcome, view_key)`, `set_view(session, view_key)`, `post_event(sessions, tick, type, payload)`, `post_state(copy)` (the newest wins), `post_voice(session, bytes)`, `forget(session)`;
- net to main (`take_inbound()`): `[conn, message]`, with `NetTransport.CLOSED` when a connection closes. Acks never reach the main thread.

`stats()` publishes counters every 20 ms: snapshots, sends, delta and full messages, and per connection bytes, WebSocket messages, stalls.

Who owns what: the main thread owns sessions (`NetSession`, `NetSessions`), picks, validation and the sim; the net thread owns connections (`conn` ids), event sequence numbers and acks, snapshot sequence numbers and the view-key cache. Sessions and connections meet only through `bind` and `set_view`.

## Seams for the next tasks

`ServerSession` keeps every rule as a hook or a handler:

- **T042** (StationDef, per-station filter): `StationViews` (sections per entry, block field sets, command kinds), `ServerSession.event_audience()`, and difficulty toggles in `NetSession.toggles` (part of the view key).
- **T043** (lobby): `pick_rule()`, `_on_pick`, `_on_release`, `_on_ready`, `StationViews.catalogue()`; coverage and Start go there.
- **T044** (claims): `claim_rule(session, command)`, which `CommandGate.check` calls for every command; `_on_claim` handles Claim and ReleaseClaim.
- **T045** (grace, pause, abandon, takeover): `on_disconnect()`, the `NetSessions` grace and `expire()`, `_on_pause_request` (Abandon, AbandonVote, Takeover), `NetServer` (a pause is not calling `world.advance`). Event type names are in `NetProtocol`.
- **T046** (session cap): `admit_rule()`.
- **T047** (LAN discovery, host process): `ServerMain` flags (`--idle-exit-min` and `--pid-file` are parsed and waiting), `NetServer`.

## How to add …

- **A message**: add the type to `NetProtocol.Type`, its schema to `SCHEMAS`, add it to `FROM_CLIENT` if clients send it, add a sample to `tests/net/test_net_protocol.gd`, a handler to `ServerSession._handlers`, an intent method to `NetClient`, and a row to `docs/protocol.md`. Bump `PROTOCOL_VERSION` if old peers would misread it.
- **A field of a block section** (status, Helm, Engineering, mounts): one `[name, type]` entry in `StationViews.BLOCKS[kind]` and one line in the matching getter (`_status`, `_helm`, …). Encoding, change detection and the client decode follow; `test_net_codec.gd` round-trips every block.
- **A section**: a value in `StationViews.Section`, a class under `sections/` (extend `SnapshotSection`: `update()` returns the delta, `full()` the model; a static `apply()` for the client), a case in `SnapshotBuilder._make()` and `NetViewState._apply_section()`, and the kind in `STATION_SECTIONS` for the stations that see it. Faction-owned sections also need `SnapshotBuilder._owner()`.
- **A station or catalogue entry**: `StationViews.CREW`, `STATION_SECTIONS`, `STATION_COMMANDS` (or `JOINT` for a joint view; joint views take the union of their stations).
- **A crew command**: the sim class in `SimCommands`, then its kind under its station in `STATION_COMMANDS`; a command missing there is server-only.

## Client library

`NetClient` is poll-driven (call `poll()` every frame; no thread):

- `connect_to(url)` sends Hello (with `token` and `host_secret` if set) once the socket opens; `state` goes `CONNECTING` → `WELCOMED`, or `REJECTED` with `reject_reason`, or `CLOSED`.
- `welcome`, `catalogue`, `token`, `session_id`; `view` (`NetViewState`: `kin`, `blocks[kind]`, `contacts`, `near`, `projectiles`; helpers `own_position()`, `contact_position(id)`, `callsign(id)`).
- Intents: `pick(ship, entry)`, `release_pick()`, `set_ready(bool)`, `claim(item)`, `release_claim(item)`, `abandon(ship)`, `vote_abandon(ship, bool)`, `takeover(ship, entry)`, `command(dict) -> seq`, `helm(throttle, rotation)`, `fire(mount)`, `set_pips(kind, pips)`, `bye()`.
- `take_events()` returns the delivered events in order (`CommandRejected` is `type == "command_rejected"`).
- Acks are automatic. `drop()` and `resume()` reconnect with the token. Test hooks: `paused` (a stalled reader), `keep_raw`, `arrivals`, `send_raw()`.

## Tests

`tests/net/`: codec, protocol, chunking and resync units, the snapshot pipeline on the real M1 sim, and the L3 suite `test_net_server.gd` (server and clients over loopback in one process, port 0). `tools/gate.sh l3` runs only `tests/net`, pinned to 2 cores; `l1` runs them with everything else.
