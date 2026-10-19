# Network protocol

The custom WebSocket protocol between the headless server and every station (FT-NET-004, D70). Code: `net/net_protocol.gd` (message set, control codec), `net/snapshot_builder.gd` and `net/sections/` (snapshot codec), `net/net_chunker.gd` (chunks and bundles). The threads and seams are in `net/README.md`.

Protocol version: `NetProtocol.PROTOCOL_VERSION` = 2. Bump it on any incompatible change.

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
| 2 | Welcome | S | `v`, `token`, `session` int, `resumed` bool, `tick` int, `period` float (site period P in m, D124/D125), `ev_from` int (last event acknowledged), `ship` int, `entry` String (current pick, -1/"" for none), `dev_all` bool, `lang` String (the session language, `en`, `pt_PT` or `it`, from the server's `--language`, FT-AUD-013) | H | Reply to an accepted Hello. | T041 |
| 3 | HelloRejected | S | `v`, `reason`: `version_mismatch`, `session_full`, `bad_hello` | H | Reply to a refused Hello; the server then closes (code 4000) once the client has had time to read it. | T041 (T046: full) |
| 4 | Catalogue | S | `ships` [{id, def, name, faction}] (crewable ships only), `entries` [{id, name, stations}], `load_tags` [] | H | After Welcome; again when it changes. | T042/T043 fill availability and load tags |
| 5 | Pick | C | `ship` int, `entry` String (`StationViews` id: a station, `p1`…`p15`, `captain`, `viewer`, `all` with `--dev-all-stations`) | H | Lobby or mid-run pick. Answered by a `picked` event. | T041 basic, T043 rules |
| 6 | Release | C | — | H | Back to the pick screen. | T041 basic, T043 |
| 7 | Ready | C | `ready` bool | H | Ready/Start control. | T043 |
| 8 | Claim | C | `item` String | H | Claim a sub-control (FT-NET-022). Answered by a `claim` event; T041 answers `request_rejected` `not_implemented`. | T044 |
| 9 | ReleaseClaim | C | `item` String | H | Release a claim. | T044 |
| 10 | Command | C | `seq` int (client sequence), `cmd` Dictionary (`kind` plus the command's fields; `ship_id` optional, must be the sender's) | H | Every crew input. | T041 |
| 11 | Ack | C | `snap` int (newest snapshot applied), `ev` int (newest event delivered) | H | At most every 200 ms, and at once after a full snapshot. Consumed on the net thread. | T041 |
| 12 | Snapshot | S | packed, below | H | 30 Hz per client with a pick: full on join, pick change or resync, deltas otherwise. | T041, T042 filters |
| 13 | Event | S | `seq` int (per session, from 1), `tick` int, `type` String, `payload` Dictionary | H | Reliable ordered stream (FT-NET-011), below. | T041 |
| 14 | Abandon | C | `ship` int | H | The host abandons a paused ship alone (D96, D128). T041 answers `request_rejected` `not_paused`. | T045 |
| 15 | Takeover | C | `ship` int, `entry` String | H | Take over an uncovered station during a pause (FT-NET-042). | T045 |
| 16 | Bye | C | `reason` String | H | Orderly leave; the client then closes. | T041 |
| 17 | Voice | S | `clip` int, `rate` int (Hz), `pcm` PackedByteArray (16-bit mono), `part` int (from 0), `last` bool (ends the clip) | L | Stitched and synthesised lines, one per sentence or stitched clip, after the line's `voice_line` event (`audio/README.md`, S7b). | E10 fills, T041 carries |
| 18 | AbandonVote | C | `ship` int, `vote` bool (cast or withdraw) | H | Crew of a paused ship vote to abandon it (D128). | T045 |

### Events

`Event.type` is either a sim event kind (`SimEvent.kind`: `hit`, `fired`, `fault`, `contact_detected`, `outcome`, …, with `payload` {ship, faction, other, value, vector, tag}) or a server event:

| Type | Payload | Sent to | Task |
|---|---|---|---|
| `command_rejected` | `seq` (the Command's), `reason` | the sender only (FT-NET-007) | T041 |
| `picked` | `ship`, `entry`, `reason` ("" when accepted) | the sender | T041, T043 |
| `request_rejected` | `request` (message type), `item` or nothing, `reason` | the sender | T041 placeholder |
| `claim` | claim changes | the ship's clients | T044 |
| `pause`, `resume` | ship, uncovered stations | every client (FT-NET-034) | T045 |
| `abandon_votes` | `ship`, `voters` [names], `needed` | every client (D128) | T045 |
| `voice_line` | `clip`, `line` (line id, "" for free text), `text` (session language, slots filled), `role`, `priority`, `max_age_ms`, `coalesce`, `resume`, `audio` (false: subtitles only), `local` (true: the client plays its own prerendered clip) | the line's audience only: the NPC's conversation claimer or the stations concerned (FT-AUD-005, FT-AUD-006) | E10 (`audio/README.md`) |

Command rejection reasons (`CommandGate`): `no_pick`, `rate_limited`, `unknown_kind`, `not_allowed` (server-only command such as `reset_ship`), `not_your_station`, `wrong_ship`, `bad_field`, `bad_value` (non-finite), `sim_rejected` (the sim refused it on apply: game rules), `ship_destroyed` (the sim dropped it); T044 adds claim reasons.

Sim events go to the sessions whose ship belongs to the event's faction (FT-NET-010); events of no ship go to every picked session (PROVISIONAL; T042 filters per station). Each session has its own sequence. The server keeps every event until the client acknowledges it, across stalls and reconnects; nothing is dropped (FT-NET-037). While a client waits for a full snapshot (join, stall) its events are held and sent right before that snapshot. A new connection of a session gets every unacknowledged event again; `NetEventInbox` drops duplicates.

## Handshake and sessions

1. The client sends Hello. The server reads `v` before anything else, so a client of any version gets `HelloRejected{version_mismatch}` (FT-NET-005); a Hello of the right version that fails the schema gets `bad_hello`.
2. A Hello with a known token resumes that session (same id, pick and event stream; a connection still holding it is closed with code 4001). Otherwise the server checks the session cap (`ServerSession.admit_rule`, T046) and opens a session with a new 128-bit token.
3. Welcome then Catalogue. A session with a pick gets a full snapshot next.

Tokens expire `--grace-s` (10 s) after the session's connection drops (`NetSessions`); T045 adds the pause and claim rules.

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

Which entry sees which section, and the block field sets, are in `net/station_views.gd` (PROVISIONAL until T042).

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
