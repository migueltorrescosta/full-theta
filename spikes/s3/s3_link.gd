class_name S3Link
extends RefCounted
## Client side of the S4 protocol for the S3 panel: joins with a stored token,
## applies full and delta snapshots, delivers events in order, acks both, and
## hands voice clips to the caller. Same logic as spikes/s4/s4_client.gd,
## shaped for a Node to poll each frame.

const PROTO: int = 1
const INBOUND_BUFFER: int = 1 << 20

var url: String = ""
var client_name: String = "web"
var token: String = ""
var seat: Dictionary = {}
var resumed: bool = false
var state: Dictionary = {}
var last_seq: int = -1
var snapshots: int = 0
var fulls: int = 0
var events: int = 0

var _peer: WebSocketPeer = WebSocketPeer.new()
var _chunker: S4Chunker = S4Chunker.new()
var _inbox: S4EventInbox = S4EventInbox.new()
var _history: Dictionary = {}
var _msg_id: int = 1
var _sent_hello: bool = false
var _acked: Vector2i = Vector2i(-2, -2)


func _init(ws_url: String, stored_token: String, name: String) -> void:
	url = ws_url
	token = stored_token
	client_name = name
	# On the web the browser hands every message to Godot as it arrives, and
	# WebSocketPeer drops what doesn't fit its inbound buffer before the next
	# poll ("Buffer payload full! Dropping data."). The 64 KiB default can't
	# hold one 68 kB full snapshot, so leave room for a snapshot, a voice clip
	# and a slow frame.
	_peer.inbound_buffer_size = INBOUND_BUFFER


func open() -> Error:
	return _peer.connect_to_url(url)


func ready_state() -> WebSocketPeer.State:
	return _peer.get_ready_state()


func is_open() -> bool:
	return _peer.get_ready_state() == WebSocketPeer.STATE_OPEN


## Polls the socket. Returns the messages that matter to the UI, in order:
## {"t": "welcome"|"snap"|"voice"|"reject"|"closed", ...}; snapshots appear as
## {"t": "snap", "seq", "full"} after they are applied to `state`.
func poll() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_peer.poll()
	var st: WebSocketPeer.State = _peer.get_ready_state()
	if st == WebSocketPeer.STATE_CLOSED:
		out.append({"t": "closed", "code": _peer.get_close_code()})
		return out
	if st != WebSocketPeer.STATE_OPEN:
		return out
	if not _sent_hello:
		send({"t": "hello", "proto": PROTO, "name": client_name, "token": token})
		_sent_hello = true
	while _peer.get_available_packet_count() > 0:
		var msg: Dictionary = _chunker.feed(_peer.get_packet())
		if msg.is_empty():
			continue
		var m: Dictionary = bytes_to_var(msg["data"])
		match m.get("t", ""):
			"welcome":
				token = m["token"]
				seat = m["seat"]
				resumed = m["resumed"]
				_inbox = S4EventInbox.new(m["ev_from"])
				out.append(m)
			"snap":
				if _apply(m):
					out.append({"t": "snap", "seq": m["seq"], "full": int(m["base"]) == -1})
			"ev":
				events += _inbox.receive(m).size()
			"voice", "reject":
				out.append(m)
	var ack: Vector2i = Vector2i(last_seq, _inbox.last_seq)
	if ack != _acked and last_seq >= 0:
		send({"t": "ack", "snap": ack.x, "ev": ack.y})
		_acked = ack
	return out


func send(m: Dictionary) -> void:
	for chunk: PackedByteArray in S4Chunker.split(
		S4Chunker.STREAM_CONTROL, _msg_id, var_to_bytes(m), S4Chunker.DEFAULT_CHUNK_SIZE
	):
		_peer.send(chunk)
	_msg_id += 1


func close() -> void:
	_peer.close(1000, "bye")


## The seat's ship entity from the latest snapshot, or {}.
func my_ship() -> Dictionary:
	return state.get(int(seat.get("ship", -1)), {})


func _apply(m: Dictionary) -> bool:
	var seq: int = m["seq"]
	var base: int = m["base"]
	if base == -1:
		state = m["ents"]
		_history = {seq: state}
		fulls += 1
		var carried: Array = m["events"]
		for e: Dictionary in carried:
			events += _inbox.receive(e).size()
	else:
		if not _history.has(base):
			return false
		state = S4Snapshot.apply(_history[base], m)
		_history[seq] = state
		for old: int in _history.keys():
			if old < base:
				_history.erase(old)
	snapshots += 1
	last_seq = seq
	return true
