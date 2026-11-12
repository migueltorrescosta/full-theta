class_name NetProtocol
extends RefCounted
## The protocol's message set and its control-message codec (T040, FT-NET-004,
## FT-NET-005, FT-NET-011); docs/protocol.md is the reference. Every message starts
## with a u8 type. Snapshots (Type.SNAPSHOT) are packed binary (SnapshotWriter,
## SnapshotState). Every other message is the type byte followed by `var_to_bytes` of a
## Dictionary, decoded with `bytes_to_var` (which never builds objects) and checked
## against schemas: every field present with its type, no other field.
##
## Bump PROTOCOL_VERSION on any incompatible change; Hello's fields never change, so a
## client of any version gets a readable HelloRejected (FT-NET-005).

enum Type {
	HELLO = 1,
	WELCOME = 2,
	HELLO_REJECTED = 3,
	CATALOGUE = 4,
	PICK = 5,
	RELEASE = 6,
	READY = 7,
	CLAIM = 8,
	RELEASE_CLAIM = 9,
	COMMAND = 10,
	ACK = 11,
	SNAPSHOT = 12,
	EVENT = 13,
	ABANDON = 14,
	TAKEOVER = 15,
	BYE = 16,
	VOICE = 17,
	ABANDON_VOTE = 18,
	ALERT = 19,
	MARK = 20,
	PING = 21,
	RUN_AGAIN = 22,
	# Lobby data-shortcut toggles and preset, host only.
	TOGGLES = 23,
	# Send or answer a request chip.
	CHIP = 24,
	# Main-screen view switch by the Captain, or Relay with no Captain.
	MAIN_VIEW = 25,
	# Relay sends a mark to an allied Relay, or accepts one from its inbox.
	MARK_SEND = 26,
	MARK_ACCEPT = 27,
	# 28 is unused: Science's puzzle rides the SCIENCE section and its commands.
	# A client's snapshot-age report for the server log (D199).
	CLIENT_STATS = 29,
	# A source station shares a data shortcut with its partner (D210).
	SHARE = 30,
	# The host pauses or resumes the whole universe in co-op (D127, FT-MIS-040).
	HOST_PAUSE = 40,
	# Multi-ship lobby and PvP (#11, version 8): any player adds a ship (M4-Q3); a crew puts
	# its ship on a team (M4-Q6); the host sets the mode and its options; a destroyed ship's
	# crew votes to relaunch (M4-Q2).
	SHIP_ADD = 41,
	SHIP_TEAM = 42,
	GAME_MODE = 43,
	RELAUNCH = 44,
	# A client's frame over 500 ms and what ran in it, for the server log (#28).
	CLIENT_FRAME = 45,
	# Solo training (D303): a client asks the server to run a station lesson for it, or the
	# crew drill.
	TRAINING = 46,
	# A player changes their name mid-session (#35 A5).
	RENAME = 47,
	# The host starts the game once every crewed ship is covered and every crew player is
	# Ready; with no host connected, any Ready crew player (#37 C1, version 11).
	START = 48,
	# Gameplay (#38, version 12): the host rerolls the run modifier in the Game setup sheet
	# (gp-11); the Captain sets or clears the priority target (gp-15); a crew member taps
	# Ready to skip the quiet gap between encounters (gp-07). Schemas: the owning strand.
	REROLL_MODIFIER = 49,
	PRIORITY_TARGET = 50,
	SKIP_GAP = 51,
}

const PROTOCOL_VERSION: int = 12
## Default WebSocket port; the HTTP port for web stations is this minus one (D108).
const DEFAULT_WS_PORT: int = 47801

## Hello.kind values.
const CLIENT_KINDS: Array[String] = ["desktop", "web", "bot"]
## Longest Hello.name kept (UTF-8 bytes, after trimming); longer names are cut.
const MAX_NAME_BYTES: int = 32
## ClientStats limits (D199, D207): pairs per report and bytes of the user agent.
const MAX_STATS_PAIRS: int = 400
const MAX_UA_BYTES: int = 200
## ClientFrame's `what`, cut to this many bytes.
const MAX_FRAME_WHAT_BYTES: int = 120

## Most bytes in one WebSocket message (a bundle of chunks): under the 64 KiB
## WebSocketPeer buffers the server keeps at their defaults (D108).
const BUNDLE_MAX: int = 48 * 1024
## Close codes (docs/protocol.md); NetTransport closes with them, NetClient reads them.
const CLOSE_REJECTED: int = 4000
const CLOSE_TAKEN_OVER: int = 4001
const CLOSE_SEND_FAILED: int = 4002
const CLOSE_PROTOCOL: int = 4003
## More than NetResync.QUEUED_LIMIT queued for a connection without a stream key.
const CLOSE_QUEUE_FULL: int = 4004
## request_rejected and command_rejected reasons shared by several server parts and read by
## the client's rules (MainScreen, CrewMarks).
const REASON_NOT_CREW: String = "not_crew"
const REASON_NOT_ALLOWED: String = "not_allowed"
## Most lines a ship's relay log keeps (CrewRelay; the client shows as many).
const RELAY_LOG_MAX: int = 60

## HelloRejected reasons.
const REJECT_VERSION: String = "version_mismatch"
const REJECT_FULL: String = "session_full"
const REJECT_BAD_HELLO: String = "bad_hello"

## Event types the server emits besides the sim's own event kinds (SimEvent.kind).
const EVENT_COMMAND_REJECTED: String = "command_rejected"
const EVENT_PICKED: String = "picked"
const EVENT_REQUEST_REJECTED: String = "request_rejected"
const EVENT_LOBBY: String = "lobby"
const EVENT_STARTED: String = "started"
const EVENT_CLAIM: String = "claim"
const EVENT_PAUSE: String = "pause"
const EVENT_RESUME: String = "resume"
## {ship, voters, needed} to every client during a pause (D128).
const EVENT_ABANDON_VOTES: String = "abandon_votes"
const EVENT_ABANDONED: String = "abandoned"
## Crew state of a ship (CrewMarks, CrewPings), to every session with a pick on it:
## {ship, level, by}, {ship, marks}, {ship, kind, id, x, y, z, by, copy}.
const EVENT_ALERT: String = "alert"
const EVENT_MARKS: String = "marks"
const EVENT_PING: String = "ping"
## The run reset (D178, NetRunReset), to every session with a pick on the ship:
## {ship, outcome ("win" | "loss"), time, hull} and {ship, voters, needed}.
const EVENT_SHIP_OUTCOME: String = "ship_outcome"
const EVENT_RUN_VOTES: String = "run_votes"
## The end-of-run debrief (RunDebrief.for_ship, FT-MIS-006, FT-MIS-010, FT-MIS-038,
## FT-PAIR-013), right after `ship_outcome` to every session with a pick on the ship.
const EVENT_DEBRIEF: String = "debrief"
## Relay (docs/protocol.md "Relay"): {ship, zones: [...]} (hazard zones and
## scan positions, every pick of the ship); {ship, routes: [[{x, y, z}]]} (Relay, and other
## stations unless the toggle set is Hard); {ship, items: [...]} the mark inbox and {ship,
## entries: [{tick, key, args}], replace} the ship's log (Relay picks only).
const EVENT_ZONES: String = "zones"
const EVENT_ROUTES: String = "routes"
const EVENT_INBOX: String = "inbox"
const EVENT_RELAY_LOG: String = "relay_log"
const EVENT_MAIN_VIEW: String = "main_view"
## A request chip the session sent was answered (NetChips): {chip, arg, accept, by}.
const EVENT_CHIP_ANSWER: String = "chip_answer"
## The shortcuts shared to the session's ship (NetShares): {ship, left: {feature:
## seconds until the share ends}}; sent to its picks when the set changes.
const EVENT_SHARES: String = "shares"
## The ship's approach lanes (P5, CrewRelay.lane_items), to Comms always and to the other
## stations while Comms shares them (the lanes toggle on and the press not expired) or their
## view holds Comms: {ship, lanes: [{card, x, y, z, opens_in, closes_in, by}]}, the seconds being
## the time left at sending. Sent when a clearance is accepted or settled and when a share
## starts or ends.
const EVENT_LANES: String = "lanes"
## Multi-ship games and PvP (#11, version 8); FleetMessages builds and checks each payload.
## `fleet`: the multi-ship lobby, to every session. `takeover`: who took which station in a
## pause, to every session of the ship's side. `handover`: an eliminated session's new view.
## `scoreboard`: the live scoreboard rows, to the sessions on it. `eliminated`, `relaunch_votes`
## and `relaunched`: a ship left play, its crew's relaunch vote, and its relaunch.
## `game_over`: who won and why, to every session.
const EVENT_FLEET: String = "fleet"
const EVENT_TAKEOVER: String = "takeover"
const EVENT_HANDOVER: String = "handover"
const EVENT_SCOREBOARD: String = "scoreboard"
const EVENT_ELIMINATED: String = "eliminated"
const EVENT_RELAUNCH_VOTES: String = "relaunch_votes"
const EVENT_RELAUNCHED: String = "relaunched"
const EVENT_GAME_OVER: String = "game_over"
## The director's quiet gap and who is Ready to skip it (NetSkipGap, gp-07): {faction,
## ends_at (tick, 0: no gap), ready, voters (session ids)}, to the sessions on the faction's ships.
const EVENT_GAP: String = "gap"
## A ship-computer or NPC line to play (VoiceService).
const EVENT_VOICE_LINE: String = "voice_line"

## Every control message in one place: Type -> [flags, fields], fields being field name ->
## Variant type. SERVER: only the server sends it. SEND: a client may send it and the
## transport accepts it (any other type from a client is dropped). RATED: a SEND that also
## takes a token from the session's rate limit in NetGame (commands take theirs in
## CommandGate; Hello, Ack and Bye take none). NAMED: its `name` is a player's text, cleaned
## by clean_text in decode. from_client and rated_requests derive from this table.
const SERVER: int = 0
const SEND: int = 1
const RATED: int = 3
const NAMED: int = 4
const MESSAGES: Dictionary = {
	Type.HELLO:
	[
		SEND | NAMED,
		{
			"v": TYPE_INT,
			"token": TYPE_STRING,
			"name": TYPE_STRING,
			"kind": TYPE_STRING,
			"host_secret": TYPE_STRING,
		}
	],
	Type.WELCOME:
	[
		SERVER,
		{
			"v": TYPE_INT,
			"token": TYPE_STRING,
			"session": TYPE_INT,
			"resumed": TYPE_BOOL,
			"tick": TYPE_INT,
			"period": TYPE_FLOAT,
			"ev_from": TYPE_INT,
			"ship": TYPE_INT,
			"seat": TYPE_STRING,
			"dev_all": TYPE_BOOL,
			"host": TYPE_BOOL,
			"lang": TYPE_STRING,
			"tls": TYPE_BOOL,
		}
	],
	Type.HELLO_REJECTED: [SERVER, {"v": TYPE_INT, "reason": TYPE_STRING}],
	Type.CATALOGUE: [SERVER, {"ships": TYPE_ARRAY, "seats": TYPE_ARRAY, "load_tags": TYPE_ARRAY}],
	Type.PICK: [RATED, {"ship": TYPE_INT, "seat": TYPE_STRING}],
	Type.RELEASE: [RATED, {}],
	Type.READY: [RATED, {"ready": TYPE_BOOL}],
	Type.CLAIM: [RATED, {"item": TYPE_STRING}],
	Type.RELEASE_CLAIM: [RATED, {"item": TYPE_STRING}],
	Type.COMMAND: [SEND, {"seq": TYPE_INT, "cmd": TYPE_DICTIONARY}],
	Type.ACK: [SEND, {"snap": TYPE_INT, "ev": TYPE_INT}],
	Type.EVENT:
	[SERVER, {"seq": TYPE_INT, "tick": TYPE_INT, "type": TYPE_STRING, "payload": TYPE_DICTIONARY}],
	Type.ABANDON: [RATED, {"ship": TYPE_INT}],
	Type.HOST_PAUSE: [RATED, {"on": TYPE_BOOL}],
	Type.TAKEOVER: [RATED, {"ship": TYPE_INT, "seat": TYPE_STRING}],
	Type.BYE: [SEND, {"reason": TYPE_STRING}],
	Type.VOICE:
	[
		SERVER,
		{
			"clip": TYPE_INT,
			"rate": TYPE_INT,
			"pcm": TYPE_PACKED_BYTE_ARRAY,
			"part": TYPE_INT,
			"last": TYPE_BOOL,
		}
	],
	Type.ABANDON_VOTE: [RATED, {"ship": TYPE_INT, "vote": TYPE_BOOL}],
	Type.ALERT: [RATED, {"level": TYPE_INT}],
	Type.MARK:
	[
		RATED,
		{
			"op": TYPE_STRING,
			"slot": TYPE_INT,
			"name": TYPE_STRING,
			"contact": TYPE_INT,
			"x": TYPE_FLOAT,
			"y": TYPE_FLOAT,
			"z": TYPE_FLOAT,
		}
	],
	Type.PING:
	[
		RATED,
		{
			"kind": TYPE_STRING,
			"id": TYPE_INT,
			"x": TYPE_FLOAT,
			"y": TYPE_FLOAT,
			"z": TYPE_FLOAT,
		}
	],
	Type.RUN_AGAIN: [RATED, {"ship": TYPE_INT, "vote": TYPE_BOOL}],
	Type.MAIN_VIEW: [RATED, {"view": TYPE_INT}],
	Type.MARK_SEND: [RATED, {"slot": TYPE_INT, "ship": TYPE_INT}],
	Type.MARK_ACCEPT: [RATED, {"id": TYPE_INT, "accept": TYPE_BOOL, "slot": TYPE_INT}],
	Type.TOGGLES: [RATED, {"set": TYPE_STRING}],
	Type.CHIP:
	[
		RATED,
		{
			"op": TYPE_STRING,
			"chip": TYPE_STRING,
			"arg": TYPE_INT,
			"id": TYPE_INT,
			"accept": TYPE_BOOL
		}
	],
	Type.SHARE: [RATED, {"feature": TYPE_STRING}],
	Type.CLIENT_STATS:
	[RATED, {"sent_us": TYPE_INT, "ua": TYPE_STRING, "pairs": TYPE_PACKED_INT64_ARRAY}],
	Type.SHIP_ADD: [RATED | NAMED, {"name": TYPE_STRING}],
	Type.SHIP_TEAM: [RATED, {"ship": TYPE_INT, "team": TYPE_INT}],
	Type.GAME_MODE: [RATED, {"mode": TYPE_STRING, "team_win": TYPE_STRING, "lives": TYPE_INT}],
	Type.RELAUNCH: [RATED, {"ship": TYPE_INT, "vote": TYPE_BOOL}],
	Type.CLIENT_FRAME: [RATED, {"ms": TYPE_INT, "what": TYPE_STRING}],
	Type.TRAINING: [RATED, {"station": TYPE_STRING}],
	Type.RENAME: [RATED | NAMED, {"name": TYPE_STRING}],
	Type.START: [RATED, {}],
	Type.REROLL_MODIFIER: [RATED, {}],
	Type.PRIORITY_TARGET: [RATED, {"contact": TYPE_INT}],
	Type.SKIP_GAP: [RATED, {"ready": TYPE_BOOL}],
}

## Messages a client may send; the server drops any other type from a client.
static var from_client: Array[int] = _types(SEND)
## Client requests that take a token from the session's rate limit in NetGame.
static var rated_requests: Array[int] = _types(RATED)


## Encodes a control message (not a snapshot): the type byte then the fields. The
## fields are not checked here; check() is the receiver's job.
static func encode(type: Type, fields: Dictionary) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray([type])
	out.append_array(var_to_bytes(fields))
	return out


## Type byte of a message, or 0 for an empty one.
static func type_of(data: PackedByteArray) -> int:
	return data[0] if data.size() > 0 else 0


## Decodes a control message into its fields plus "t" (the type), or {} when the bytes
## are not a known control type holding a Dictionary that passes check(). A Hello's
## kind must be one of CLIENT_KINDS; a NAMED message's name is cleaned by clean_text.
static func decode(data: PackedByteArray) -> Dictionary:
	var type: int = type_of(data)
	if not MESSAGES.has(type):
		return {}
	var body: Variant = bytes_to_var(data.slice(1))
	if not body is Dictionary:
		return {}
	var fields: Dictionary = body
	if check(type, fields) != "":
		return {}
	if type == Type.HELLO and not CLIENT_KINDS.has(fields["kind"]):
		return {}
	if (MESSAGES[type][0] as int) & NAMED:
		fields["name"] = clean_text(fields["name"], MAX_NAME_BYTES)
	fields["t"] = type
	return fields


## A player's text: trimmed, cut to max_bytes of UTF-8 between characters, trimmed again.
static func clean_text(text: String, max_bytes: int) -> String:
	return clip_utf8(text.strip_edges(), max_bytes).strip_edges()


## The types whose flags hold all of `mask`.
static func _types(mask: int) -> Array[int]:
	var out: Array[int] = []
	for type: int in MESSAGES:
		if (MESSAGES[type][0] as int) & mask == mask:
			out.append(type)
	return out


## The longest prefix of `text` that fits in max_bytes of UTF-8, cut between characters.
static func clip_utf8(text: String, max_bytes: int) -> String:
	var bytes: PackedByteArray = text.to_utf8_buffer()
	if bytes.size() <= max_bytes:
		return text
	var end: int = max_bytes
	while end > 0 and (bytes[end] & 0xC0) == 0x80:
		end -= 1
	return bytes.slice(0, end).get_string_from_utf8()


## Why the fields don't match the type's schema, or "" if they do.
static func check(type: int, fields: Dictionary) -> String:
	if not MESSAGES.has(type):
		return "unknown type %d" % type
	var schema: Dictionary = MESSAGES[type][1]
	if fields.size() != schema.size():
		return "type %d: %d fields, expected %d" % [type, fields.size(), schema.size()]
	for key: Variant in fields:
		if not key is String or not schema.has(key):
			return "type %d: unknown field %s" % [type, key]
		if typeof(fields[key]) != schema[key]:
			return "type %d: field %s has type %d" % [type, key, typeof(fields[key])]
	return ""


## Protocol version a Hello claims, read before any other check so a client of another
## version always gets REJECT_VERSION (FT-NET-005); -1 if unreadable.
static func hello_version(data: PackedByteArray) -> int:
	if type_of(data) != Type.HELLO:
		return -1
	var body: Variant = bytes_to_var(data.slice(1))
	if body is Dictionary and (body as Dictionary).get("v") is int:
		return (body as Dictionary)["v"]
	return -1


## host_secret is "" unless the client is the host that started the server (D127).
static func hello(
	token: String, name: String, kind: String, host_secret: String = ""
) -> PackedByteArray:
	return encode(
		Type.HELLO,
		{
			"v": PROTOCOL_VERSION,
			"token": token,
			"name": name,
			"kind": kind,
			"host_secret": host_secret
		}
	)


static func hello_rejected(reason: String) -> PackedByteArray:
	return encode(Type.HELLO_REJECTED, {"v": PROTOCOL_VERSION, "reason": reason})


static func ack(snap: int, ev: int) -> PackedByteArray:
	return encode(Type.ACK, {"snap": snap, "ev": ev})


static func event(seq: int, tick: int, type: String, payload: Dictionary) -> PackedByteArray:
	return encode(Type.EVENT, {"seq": seq, "tick": tick, "type": type, "payload": payload})
