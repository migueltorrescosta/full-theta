# Network protocol

The custom WebSocket protocol between the headless server and every station (FT-NET-004, D70). Code: `net/net_protocol.gd` (message set, control codec), `net/snapshot_builder.gd` and `net/sections/` (snapshot codec), `net/net_chunker.gd` (chunks and bundles). The threads and seams are in `net/README.md`.

Protocol version: `NetProtocol.PROTOCOL_VERSION` = 1. Bump it on any incompatible change.

## Transport

- One WebSocket connection per client, binary messages only. The server listens on `--bind ADDR --port N` (WS); the HTTP server for web stations will use N − 1 (D108).
- Every protocol message is split into chunks of at most 16 KiB of payload (FT-NET-038). A chunk has an 11-byte header, little endian: stream u8, msg_id u32, index u16, count u16, length u16. Streams: 0 control (handshake, lobby, commands, acks, events), 1 snapshot, 2 voice.
- A sender queues all chunks of a message together in one lane, so per stream they arrive contiguously. The receiver keeps one partial message per stream and drops it when another message starts on that stream; malformed chunks and messages over 8 MiB are errors. The server closes a connection after 16 malformed messages.
- Each connection has two lanes. The high lane (control, events, snapshots) is FIFO; the low lane (voice) is served only when the high lane is empty, one chunk per pump (PROVISIONAL), so voice never delays a snapshot by more than one chunk.
- **Bundles.** All chunks one pump may send to a client go out as one WebSocket message of at most 48 KiB, a concatenation of whole chunks. Receivers split it by the length field (`NetChunker.feed_packet`).
- The server keeps `WebSocketPeer`'s 64 KiB buffer defaults; bundles and chunks stay under them. Web clients raise `inbound_buffer_size` to 1 MiB (D108); `NetClient.inbound_buffer_size` is where.

### Packets per message (known limit)

Godot's `WebSocketPeer` writes each frame's 2–4 byte header and its payload in separate `send` calls, and the server sets `TCP_NODELAY`, so every WebSocket message costs two TCP packets (S9, "Wi-Fi"). GDScript can't change that write path, and turning Nagle back on would trade it for delayed-ACK stalls of up to 200 ms. The cheap part is done: bundling makes it one WebSocket message per client per pump instead of one per protocol message, so a pump that sends a snapshot plus events costs two packets, not two per message. The rest needs an engine change (write header and payload in one `send`); #4 measures the airtime on Wi-Fi.

## Encodings

Every message starts with a u8 type (`NetProtocol.Type`).

- **Snapshots** (type 12) are packed binary (below): they are 30 Hz traffic and the bandwidth budget (R15, S9) needs fixed point and dead reckoning.
- **Every other message** is the type byte followed by `var_to_bytes` of a Dictionary, decoded with `bytes_to_var` (which never builds objects) and checked against `NetProtocol.SCHEMAS`: every field present with its Variant type, no other field, else the message is dropped. These are rare (handshake, lobby, commands at human rates, events), so a self-describing encoding costs little, keeps the schema in one table, and needs no hand-written codec per message. Commands carry the sim command as a Dictionary (`SimCommand.to_dict()` fields), validated field by field on the server (`CommandGate`).

## Messages

Direction: C client to server, S server to client. Lane: H high, L low. "Task" is the #6 task that fills in the behaviour; T041 defines and round-trips them all (`tests/net/test_net_protocol.gd`).

| Type | Message | Dir | Fields | Lane | When | Task |
|---|---|---|---|---|---|---|
| 1 | Hello | C | `v` int, `token` String ("" for a new session), `name` String, `kind` String (desktop, web, bot), `host_secret` String ("" unless host, D127; the launcher hands it to the server child in the `FT_HOST_SECRET` environment variable, never on the command line) | H | First message after the socket opens. | T041 |
| 2 | Welcome | S | `v`, `token`, `session` int, `resumed` bool, `tick` int, `period` float (site period P in m, D124/D125), `ev_from` int (last event acknowledged), `ship` int, `entry` String (current pick, -1/"" for none; after a lapsed rejoin `ship` set and `entry` "" is that ship's pick screen), `dev_all` bool, `host` bool (accepted as the host, D127) | H | Reply to an accepted Hello. | T041 |
| 3 | HelloRejected | S | `v`, `reason`: `version_mismatch`, `session_full`, `bad_hello` | H | Reply to a refused Hello; the server then closes (code 4000) once the client has had time to read it. | T041 (T046: full) |
| 4 | Catalogue | S | `ships` [{id, def, name, faction}] (crewable ships only), `entries` [StationDef: {id, name, load_tag, stations, crew, sections, fields, commands, claims, controls}], `load_tags` ["light", "busy", "intense"] | H | After Welcome. | T042 |
| 5 | Pick | C | `ship` int, `entry` String (a StationDef id: `helm` … `comms`, `tactical`, `systems`, `ops`, `captain`, `viewer`, `all` with `--dev-all-stations`) | H | Lobby or mid-run pick; replaces the current one (one pick per player). Answered by a `picked` event. | T043 |
| 6 | Release | C | — | H | Back to the ship list (ship −1). Same rules as a pick. | T043 |
| 7 | Ready | C | `ready` bool | H | Start: `true` from a crew player starts the ship's run if its coverage check passes; `false` is ignored. Refusals: `request_rejected` `not_crew`, `started`, `coverage` (with `uncovered`). | T043 |
| 8 | Claim | C | `item` String (`flight`, `shield_facing`, `mount:N`, `crew:N`) | H | Claim a sub-control of a station the pick covers (FT-NET-022). Answered by a `claim` event to the ship's clients, or `request_rejected` `bad_item`, `not_your_station`, `claimed`. | T044 |
| 9 | ReleaseClaim | C | `item` String | H | Release a claim the sender holds; else `request_rejected` `not_claimed`. | T044 |
| 10 | Command | C | `seq` int (client sequence), `cmd` Dictionary (`kind` plus the command's fields; `ship_id` optional, must be the sender's) | H | Every crew input. | T041 |
| 11 | Ack | C | `snap` int (newest snapshot applied), `ev` int (newest event delivered) | H | At most every 200 ms, and at once after a full snapshot. Consumed on the net thread. | T041 |
| 12 | Snapshot | S | packed, below | H | 30 Hz per client with a pick: full on join, pick change or resync, deltas otherwise. | T041, T042 filters |
| 13 | Event | S | `seq` int (per session, from 1), `tick` int, `type` String, `payload` Dictionary | H | Reliable ordered stream (FT-NET-011), below. | T041 |
| 14 | Abandon | C | `ship` int | H | The host abandons a paused ship alone (D96, D127). Refusals: `request_rejected` `not_paused`, `not_host`. | T045 |
| 15 | Takeover | C | `ship` int, `entry` String (a crew entry) | H | During a pause, the Captain or a Viewer of the paused ship takes an uncovered station (FT-NET-042); answered like a pick. Refusals: `not_paused`, `not_allowed` (a crew player: use Pick), `not_implemented` (another ship's player, #11), `bad_pick`. | T045 |
| 16 | Bye | C | `reason` String | H | Orderly leave; the client then closes. | T041 |
| 17 | Voice | S | `clip` int, `rate` int (Hz), `pcm` PackedByteArray (16-bit mono) | L | Synthesised lines (S7b). | #8 fills, T041 carries |
| 18 | AbandonVote | C | `ship` int, `vote` bool (cast or withdraw) | H | A remaining connected crew player of a paused ship votes to abandon it (D128). Refusals: `not_paused`, `not_crew`. | T045 |

### Events

`Event.type` is either a sim event kind (`SimEvent.kind`: `hit`, `fired`, `fault`, `contact_detected`, `outcome`, …, with `payload` {ship, faction, other, value, vector, tag}) or a server event:

| Type | Payload | Sent to | Task |
|---|---|---|---|
| `command_rejected` | `seq` (the Command's; −1 for a refused Pick or Release), `reason` | the sender only (FT-NET-007) | T041 |
| `picked` | `ship`, `entry`, `reason` ("" when accepted; `bad_pick`, `captain_taken`, `breaks_coverage`) | the sender | T041, T043 |
| `request_rejected` | `request` (message type), `reason`, and the request's `item`, `ship`, `entry` or `uncovered` | the sender | T043–T045 |
| `lobby` | `ship`, `crew` (crew players), `min_crew` (3, or 1 with the dev flag), `uncovered` [stations], `ready` (coverage passes), `started`, `in_play`, `captain` (name or "") | clients on the ship list and those on ships of the ship's faction, on join and whenever it changes (FT-NET-021) | T043 |
| `started` | `ship`, `tick` | every client, when a ship's Start is accepted | T043 |
| `claim` | `ship`, `item`, `session` (holder, −1 free), `name` (holder's name, "" free) | the ship's clients, whenever a holder changes | T044 |
| `pause` | `ship`, `uncovered` [stations], `crew`, `min_crew` | every client, when a ship pauses or its uncovered list changes, and on join (FT-NET-034) | T045 |
| `resume` | `tick` | every client, when no ship is paused any more | T045 |
| `abandon_votes` | `ship`, `voters` [names, sorted], `needed` (more than half of the remaining connected crew) | every client, on each vote, withdrawal or voter drop, and on join during a pause (D128) | T045 |
| `abandoned` | `ship`, `by` (`vote` or `host`) | every client (FT-NET-041) | T045 |

Command rejection reasons (`CommandGate`): `no_pick`, `rate_limited`, `unknown_kind`, `not_allowed` (server-only command such as `reset_ship`), `not_your_station`, `wrong_ship`, `bad_field`, `bad_value` (non-finite), `claimed` (another player holds the item, FT-NET-023), `ship_abandoned`, `breaks_coverage` (a refused mid-run Pick or Release, seq −1, FT-NET-043), `sim_rejected` (the sim refused it on apply: game rules), `ship_destroyed` (the sim dropped it).

Sim events go to the sessions holding a pick on a ship of the event's faction (FT-NET-010) whose entry sees the kind: repair events only to entries covering Engineering, `fire_blocked` and `friendly_fire_warning` only to Weapons, `ai_mode` to nobody, every other kind to every entry (`StationViews.EVENT_STATIONS`). Events of no ship go to nobody. Each session has its own sequence. The server keeps every event until the client acknowledges it, across stalls and reconnects; nothing is dropped (FT-NET-037). While a client waits for a full snapshot (join, stall) its events are held and sent right before that snapshot. A new connection of a session gets every unacknowledged event again; `NetEventInbox` drops duplicates.

## Lobby, claims and the pause

**Lobby (T043).** The catalogue (`StationViews`, one `StationDef` each) is the six stations, Tactical (Helm + Weapons), Systems (Engineering + Science), Ops (Relay + Comms), Captain and Viewer, plus `all` with `--dev-all-stations`; the other 12 joint views come with M2 (FT-JNT-004). Each player holds one pick; any number may share a station or joint view; one Captain per ship (CLASH-10; a Captain within grace still holds the seat). The coverage check (`NetCoverage`) passes with at least 3 crew players (1 with the dev flag) and all six stations covered; Captain and Viewer don't count. The sim doesn't step until a ship starts: Ready{true} from any crew player of a ship that passes coverage starts it, and the universe steps from the first Start (D129; with several crewable ships, #11 decides whether every ship must start). Snapshots flow before the start and during a pause at 30 Hz of wall clock.

**Claims (T044).** Claimable items: `flight` (Helm: `helm_input` with face, decoupled, all-stop, Align; dock and jump when they exist), `shield_facing` (Helm: shield focus), `mount:N` (Weapons: aim and fire; ammo type when it exists), `crew:N` (Engineering: dispatch and recall). A claimed item takes commands only from its claimer (`claimed` otherwise); an unclaimed one from anyone at its station. A player alone on a station holds all its free items; when a second player joins, the first keeps them, implicit ones included, and the newcomer claims only what the first releases (D130). Claims are released by ReleaseClaim, by a pick change that no longer covers the item's station, and when the claimer's grace ends. Every other control is ship-wide, last writer wins (target selection included, approved in #6): `pips:K` (set_pips per subsystem kind), `shield` (set_shield), `boost` (Engineering), `target` (Helm's target selection). The OWNERSHIP snapshot section names claimers and last writers to the entries of that station (`NetViewState.claimer(item)`, `last_writer(control)`). Claims and `claim_rule` apply in the lobby too: a command on an item another player holds is refused at once before Start; accepted commands queue and apply on the first tick after Start.

**Grace and pause (T045).** A dropped session keeps its pick and claims (not its abandon vote: only connected crew vote) for `--grace-s` (10 s), timed on the server's wall clock, also while paused. When the grace ends, the session lapses: its pick and claims are released and remembered, and if a started ship still in play (not destroyed, retreated or abandoned) then fails coverage, the whole universe pauses (only a grace expiry starts a pause; other changes only update or end one): the sim doesn't step, snapshots keep flowing, and every client gets `pause`. During a pause the paused ship's crew may change picks freely; outside it, a Pick or Release that would make a passing ship in play fail coverage is refused (`breaks_coverage`). The universe resumes (`resume`) once no ship in play fails coverage: a rejoin, a takeover, a pick change, or abandoning the ship. Captain and Viewer never count, so their drops never pause.

**Abandon (D128).** During a pause each connected crew player of the paused ship may vote or withdraw; when the votes exceed half of them (2 of 2), or at once when the host sends Abandon, the ship is abandoned: it leaves play, the pause ends, and a logged server command (`AbandonShipCommand`) makes the sim mark it ABANDONED and give it a LOSS, which ends the M1 encounter. Votes clear when the pause ends. A vote is evaluated only when cast (a voter who drops loses the vote; the others aren't abandoned by someone else's drop; approved in #6). The abandoned ship's crew commands get `ship_abandoned`.

**Rejoin.** A client joining or rejoining during a pause gets the current `lobby`, `pause` and `abandon_votes` events right after Welcome and the Catalogue. A token resumes its session for the server's life (approved in #6). Within the grace everything is as it was. After it, the session gets its ship back and its pick if still allowed (the Captain seat may be taken), else that ship's pick screen (Welcome `ship` set, `entry` ""); its old claims come back where still free.

## Handshake and sessions

1. The client sends Hello. The server reads `v` before anything else, so a client of any version gets `HelloRejected{version_mismatch}` (FT-NET-005); a Hello of the right version that fails the schema gets `bad_hello`.
2. A Hello with a known token resumes that session (same id, pick and event stream; a connection still holding it is closed with code 4001). Otherwise the server checks the session cap (`ServerSession.admit_rule`, T046) and opens a session with a new 128-bit token.
3. Welcome then Catalogue. A session with a pick gets a full snapshot next.

A session's grace is `--grace-s` (10 s) after its connection drops (`NetSessions`); its token stays valid after that (see Rejoin above).

## Snapshots

Header: u8 type (12), u8 flags (bit 0 full), u32 seq, u32 tick, u8 n sections; then n sections of u8 kind, u16 length, payload. A delta omits sections with nothing to say.

A view key is (ship, catalogue entry, difficulty toggles) (FT-NET-040). Each section is encoded once per snapshot per owner (a ship, or a faction for contacts), each view key's message once, and all clients of a key get the same chunks. Deltas chain on the previous snapshot of the stream; a client that misses one (a stall) gets a full snapshot instead (FT-NET-037). Clients check that a delta's seq follows the last one applied.

Fixed point (`NetCodec`): positions 1/16 m as int32 site-local offsets, wrapped into [−P/2, P/2) (D104, D124); velocities 1/16 m/s int16 (±2,048 m/s); angular velocities 1/50 rad/s int8; orientations smallest-three in 32 bits; projectile velocities 1/8 m/s. Dead reckoning is integer arithmetic on both ends, so they agree bit for bit; residuals and predictions use the minimum image with P from Welcome, so a contact crossing a seam costs a small residual.

| Kind | Section | Owner | Content |
|---|---|---|---|
| 1 | KIN | ship | Own ship every snapshot: site, position, velocity, orientation, angular velocity (26 B). |
| 2 | STATUS | ship | Top bar block when it changes: alive, run status, outcome, hull, shields, pips used, propellant. |
| 3 | HELM | ship | Helm block: decoupled, throttle setpoint, face, approach, all-stop, Align stage, target, shield focus. |
| 4 | ENGINEERING | ship | Boost, weapon energy, hull, spare parts, shield strength and tightness, per subsystem health, pips, heat, crews, fault armed. |
| 5 | MOUNTS | ship | Per mount barrel, cooldown, ammo, heat, aim set. |
| 6 | CONTACTS | faction | Detected contacts and own ships, dead reckoned (0.5 m), with callsign and identified flag on change. |
| 7 | NEAR | ship | Orientations of contacts within 2 km, dead reckoned (1°). |
| 8 | PROJECTILES | ship | Projectiles within 3 km, sent once each, extrapolated by clients. |
| 9 | OWNERSHIP | ship, per entry | `var_to_bytes` of {claims: {item: [session, name]}, writers: {control: [session, name]}}, only the entry's own stations' items; whole on change (rare, so self-describing). |

Which entry sees which section, and the block field sets, are each entry's `StationDef` (`net/station_views.gd`; also in the Catalogue). A view key's difficulty-toggle set is one of `easy`, `normal`, `hard`; M1's sim has no data shortcut yet, so no field depends on it (`tests/net/test_net_stations_filter.gd` checks the filter at each set).

## Rates and limits (PROVISIONAL)

| Setting | Value | Where |
|---|---|---|
| Snapshot rate | every 2 sim ticks (30 Hz) | `NetServer.SNAPSHOT_TICKS` |
| Stall | > 15 unacknowledged snapshots, a failed send (connection closed, code 4002), or > 256 KiB queued on the high lane (D106) | `NetResync` |
| Command rate limit | 90 per second, burst 180, per session | `ServerSession.DEFAULT_RATE`, `DEFAULT_BURST` |
| Chunk payload | 16 KiB | `NetChunker.DEFAULT_CHUNK_SIZE` |
| Bundle | 48 KiB | `NetTransport.BUNDLE_MAX` |
| Voice | one chunk per pump, only when the high lane is empty | `NetTransport.voice_per_pump` |
| Ack | at most every 200 ms, at once after a full snapshot | `NetClient.ACK_INTERVAL_US` |
| Dead reckoning | 0.5 m, 1°, near 2 km, projectiles 3 km | `SnapshotBuilder` |
