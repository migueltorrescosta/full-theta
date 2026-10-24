class_name NetProtocol
extends RefCounted
## The protocol's message set and its control-message codec (T040, FT-NET-004,
## FT-NET-005, FT-NET-011); docs/protocol.md is the reference. Every message starts
## with a u8 type. Snapshots (Type.SNAPSHOT) are packed binary (SnapshotBuilder,
## NetViewState). Every other message is the type byte followed by `var_to_bytes` of a
## Dictionary, decoded with `bytes_to_var` (which never builds objects) and checked
## against SCHEMAS: every field present with its type, no other field.
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
	# Reserved for M2 (#9); each strand adds its schema, FROM_CLIENT and docs/protocol.md
	# rows. Lobby data-shortcut toggles and preset, host only (strand G).
	TOGGLES = 23,
	# Send or answer a request chip (strand G).
	CHIP = 24,
	# Main-screen view switch by the Captain, or Relay with no Captain (strand F).
	MAIN_VIEW = 25,
	# Relay sends a mark to an allied Relay, or accepts one from its inbox (strand B).
	MARK_SEND = 26,
	MARK_ACCEPT = 27,
	# Scan or hack minigame: puzzle from the server, moves and solution from Science
	# (strands A and E).
	MINIGAME = 28,
	# A client's snapshot-age report for the session log (strand D, D199).
	CLIENT_STATS = 29,
}

const PROTOCOL_VERSION: int = 5
## Default WebSocket port; the HTTP port for web stations is this minus one (D108).
const DEFAULT_WS_PORT: int = 47801

## Hello.kind values.
const CLIENT_KINDS: Array[String] = ["desktop", "web", "bot"]
## Longest Hello.name kept (UTF-8 bytes, after trimming); longer names are cut.
const MAX_NAME_BYTES: int = 32

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
## {ship, level, by}, {ship, marks}, {ship, kind, id, site, x, y, z, by, copy}.
const EVENT_ALERT: String = "alert"
const EVENT_MARKS: String = "marks"
const EVENT_PING: String = "ping"
## The run reset (D178, NetRunReset), to every session with a pick on the ship:
## {ship, outcome ("win" | "loss"), time_s, hull} and {ship, voters, needed}.
const EVENT_RUN_OVER: String = "run_over"
const EVENT_RUN_VOTES: String = "run_votes"
## Relay and the callout layer (strand B of #9, docs/protocol.md "Relay"): {sites: [{site,
## name}]} to every pick; {ship, zones: [...]} (hazard zones and scan positions, every pick
## of the ship); {ship, routes: [[{site, x, y, z}]]} (Relay, and other stations unless the
## toggle set is Hard); {ship, items: [...]} the mark inbox and {ship, entries: [{tick, key,
## args}], replace} the ship's log (Relay picks only).
const EVENT_SITES: String = "sites"
const EVENT_ZONES: String = "zones"
const EVENT_ROUTES: String = "routes"
const EVENT_INBOX: String = "inbox"
const EVENT_RELAY_LOG: String = "relay_log"

## Field name -> Variant type, per control message type.
const SCHEMAS: Dictionary = {
	Type.HELLO:
	{
		"v": TYPE_INT,
		"token": TYPE_STRING,
		"name": TYPE_STRING,
		"kind": TYPE_STRING,
		"host_secret": TYPE_STRING,
	},
	Type.WELCOME:
	{
		"v": TYPE_INT,
		"token": TYPE_STRING,
		"session": TYPE_INT,
		"resumed": TYPE_BOOL,
		"tick": TYPE_INT,
		"period": TYPE_FLOAT,
		"ev_from": TYPE_INT,
		"ship": TYPE_INT,
		"entry": TYPE_STRING,
		"dev_all": TYPE_BOOL,
		"host": TYPE_BOOL,
		"lang": TYPE_STRING,
	},
	Type.HELLO_REJECTED: {"v": TYPE_INT, "reason": TYPE_STRING},
	Type.CATALOGUE: {"ships": TYPE_ARRAY, "entries": TYPE_ARRAY, "load_tags": TYPE_ARRAY},
	Type.PICK: {"ship": TYPE_INT, "entry": TYPE_STRING},
	Type.RELEASE: {},
	Type.READY: {"ready": TYPE_BOOL},
	Type.CLAIM: {"item": TYPE_STRING},
	Type.RELEASE_CLAIM: {"item": TYPE_STRING},
	Type.COMMAND: {"seq": TYPE_INT, "cmd": TYPE_DICTIONARY},
	Type.ACK: {"snap": TYPE_INT, "ev": TYPE_INT},
	Type.EVENT:
	{"seq": TYPE_INT, "tick": TYPE_INT, "type": TYPE_STRING, "payload": TYPE_DICTIONARY},
	Type.ABANDON: {"ship": TYPE_INT},
	Type.TAKEOVER: {"ship": TYPE_INT, "entry": TYPE_STRING},
	Type.BYE: {"reason": TYPE_STRING},
	Type.VOICE:
	{
		"clip": TYPE_INT,
		"rate": TYPE_INT,
		"pcm": TYPE_PACKED_BYTE_ARRAY,
		"part": TYPE_INT,
		"last": TYPE_BOOL,
	},
	Type.ABANDON_VOTE: {"ship": TYPE_INT, "vote": TYPE_BOOL},
	Type.ALERT: {"level": TYPE_INT},
	Type.MARK:
	{
		"op": TYPE_STRING,
		"slot": TYPE_INT,
		"name": TYPE_STRING,
		"contact": TYPE_INT,
		"site": TYPE_INT,
		"x": TYPE_FLOAT,
		"y": TYPE_FLOAT,
		"z": TYPE_FLOAT,
	},
	Type.PING:
	{
		"kind": TYPE_STRING,
		"id": TYPE_INT,
		"site": TYPE_INT,
		"x": TYPE_FLOAT,
		"y": TYPE_FLOAT,
		"z": TYPE_FLOAT,
	},
	Type.RUN_AGAIN: {"ship": TYPE_INT, "vote": TYPE_BOOL},
	Type.MARK_SEND: {"slot": TYPE_INT, "ship": TYPE_INT},
	Type.MARK_ACCEPT: {"id": TYPE_INT, "accept": TYPE_BOOL, "slot": TYPE_INT},
}

## Messages a client may send; the server drops any other type from a client.
const FROM_CLIENT: Array[int] = [
	Type.HELLO,
	Type.PICK,
	Type.RELEASE,
	Type.READY,
	Type.CLAIM,
	Type.RELEASE_CLAIM,
	Type.COMMAND,
	Type.ACK,
	Type.ABANDON,
	Type.TAKEOVER,
	Type.BYE,
	Type.ABANDON_VOTE,
	Type.ALERT,
	Type.MARK,
	Type.PING,
	Type.RUN_AGAIN,
	Type.MARK_SEND,
	Type.MARK_ACCEPT,
]

## Client requests that take a token from the session's rate limit in ServerSession
## (commands take theirs in CommandGate; Hello, Ack and Bye take none).
const RATED_REQUESTS: Array[int] = [
	Type.PICK,
	Type.RELEASE,
	Type.READY,
	Type.CLAIM,
	Type.RELEASE_CLAIM,
	Type.ABANDON,
	Type.TAKEOVER,
	Type.ABANDON_VOTE,
	Type.ALERT,
	Type.MARK,
	Type.PING,
	Type.RUN_AGAIN,
	Type.MARK_SEND,
	Type.MARK_ACCEPT,
]


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
## kind must be one of CLIENT_KINDS; its name is trimmed and cut to MAX_NAME_BYTES.
static func decode(data: PackedByteArray) -> Dictionary:
	var type: int = type_of(data)
	if not SCHEMAS.has(type):
		return {}
	var body: Variant = bytes_to_var(data.slice(1))
	if not body is Dictionary:
		return {}
	var fields: Dictionary = body
	if check(type, fields) != "":
		return {}
	if type == Type.HELLO:
		if not CLIENT_KINDS.has(fields["kind"]):
			return {}
		var name: String = (fields["name"] as String).strip_edges()
		fields["name"] = clip_utf8(name, MAX_NAME_BYTES).strip_edges()
	fields["t"] = type
	return fields


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
	var schema: Dictionary = SCHEMAS.get(type, {})
	if not SCHEMAS.has(type):
		return "unknown type %d" % type
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


static func command(seq: int, cmd: Dictionary) -> PackedByteArray:
	return encode(Type.COMMAND, {"seq": seq, "cmd": cmd})


static func event(seq: int, tick: int, type: String, payload: Dictionary) -> PackedByteArray:
	return encode(Type.EVENT, {"seq": seq, "tick": tick, "type": type, "payload": payload})
