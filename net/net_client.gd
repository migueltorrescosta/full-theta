class_name NetClient
extends RefCounted
## Reusable headless client of the protocol (T041): connect, handshake (with a token to
## resume), apply snapshots into a NetViewState, acknowledge, send commands, deliver
## events in order (NetEventInbox), and resume by token after a drop. Poll-driven, no
## thread: call poll() every frame. Tests, the L4 bots and the #7 client shell use it.
## It never names sim/ (FT-ARC-005): commands are plain dictionaries
## ({"kind": "fire", "mount_index": 0}) that the server validates.

## Lifecycle states.
enum State { IDLE, CONNECTING, WELCOMED, REJECTED, CLOSED }

## Acks at most this often (us), and at once after a full snapshot (S9: every 200 ms is
## enough for the 15-snapshot stall limit and saves packets).
const ACK_INTERVAL_US: int = 200_000

var name: String = "client"
var client_kind: String = "bot"
var host_secret: String = ""
var url: String = ""
var state: State = State.IDLE
var token: String = ""
var session_id: int = -1
var reject_reason: String = ""
## Welcome fields of the current connection.
var welcome: Dictionary = {}
var catalogue: Dictionary = {}
var view: NetViewState = NetViewState.new()
var inbox: NetEventInbox = NetEventInbox.new()
## Test hook: while true, poll() does nothing: no reads, no acks (a stalled reader).
var paused: bool = false
## Inbound buffer size; web clients raise it to 1 MiB (D108).
var inbound_buffer_size: int = 65535
## Counters: snapshots applied, fulls, failed applies, events, voice clips, chunk errors.
var stats: Dictionary = {"snapshots": 0, "fulls": 0, "bad_snapshots": 0, "events": 0, "voice": 0}
## Received voice clips (NetProtocol VOICE fields) and their arrival order by stream.
var voice_clips: Array[Dictionary] = []
## Stream of every completed inbound message, in arrival order (tests).
var arrivals: PackedByteArray = PackedByteArray()
## Test hook: keep each snapshot's bytes by seq in raw_snapshots.
var keep_raw: bool = false
var raw_snapshots: Dictionary = {}

var _peer: WebSocketPeer
var _chunker: NetChunker = NetChunker.new()
var _queue: NetSendQueue = NetSendQueue.new()
var _events: Array[Dictionary] = []
var _next_seq: int = 1
var _acked: Vector2i = Vector2i(-1, -1)
var _last_ack_us: int = 0
var _force_ack: bool = false
var _hello_sent: bool = false


## Connects to ws://host:port and sends Hello once open (with the token, if any).
func connect_to(server_url: String) -> Error:
	url = server_url
	_peer = WebSocketPeer.new()
	_peer.inbound_buffer_size = inbound_buffer_size
	_chunker = NetChunker.new()
	_queue = NetSendQueue.new()
	welcome = {}
	_hello_sent = false
	state = State.CONNECTING
	var err: Error = _peer.connect_to_url(url)
	if err != OK:
		state = State.CLOSED
	return err


## Reconnects with the stored token: the server returns the same session, pick and
## event stream, and a full snapshot (FT-NET-025, FT-NET-026).
func resume() -> Error:
	if _peer != null:
		_peer.close()
	return connect_to(url)


## Drops the connection without Bye (tests: a crash or a network drop).
func drop() -> void:
	if _peer != null:
		_peer.close()
		_peer.poll()
	state = State.CLOSED


## Says Bye and closes.
func bye(reason: String = "bye") -> void:
	_send(NetProtocol.Type.BYE, {"reason": reason})
	_flush()
	_peer.close(1000, reason)


func poll() -> void:
	if _peer == null or paused:
		return
	_peer.poll()
	var ready_state: WebSocketPeer.State = _peer.get_ready_state()
	if ready_state == WebSocketPeer.STATE_OPEN and state == State.CONNECTING and not _hello_sent:
		_queue.push(
			NetChunker.STREAM_CONTROL, NetProtocol.hello(token, name, client_kind, host_secret)
		)
		_hello_sent = true
	# Read before looking at a close: HelloRejected arrives just before the close.
	while _peer.get_available_packet_count() > 0:
		for msg: Dictionary in _chunker.feed_packet(_peer.get_packet()):
			_on_message(msg["stream"], msg["data"])
	if ready_state == WebSocketPeer.STATE_CLOSED:
		if state != State.REJECTED:
			state = State.CLOSED
		return
	if ready_state != WebSocketPeer.STATE_OPEN:
		return
	_maybe_ack()
	_flush()


func is_welcomed() -> bool:
	return state == State.WELCOMED


## Events delivered since the last call, in order; each {"seq", "tick", "type",
## "payload"}.
func take_events() -> Array[Dictionary]:
	var out: Array[Dictionary] = _events
	_events = []
	return out


# --- Intents. ---


func pick(ship: int, entry: String) -> void:
	_send(NetProtocol.Type.PICK, {"ship": ship, "entry": entry})


func release_pick() -> void:
	_send(NetProtocol.Type.RELEASE, {})


func set_ready(ready: bool) -> void:
	_send(NetProtocol.Type.READY, {"ready": ready})


func claim(item: String) -> void:
	_send(NetProtocol.Type.CLAIM, {"item": item})


func release_claim(item: String) -> void:
	_send(NetProtocol.Type.RELEASE_CLAIM, {"item": item})


func abandon(ship: int) -> void:
	_send(NetProtocol.Type.ABANDON, {"ship": ship})


func vote_abandon(ship: int, vote: bool) -> void:
	_send(NetProtocol.Type.ABANDON_VOTE, {"ship": ship, "vote": vote})


func takeover(ship: int, entry: String) -> void:
	_send(NetProtocol.Type.TAKEOVER, {"ship": ship, "entry": entry})


## Sends a crew command; returns its seq (CommandRejected events name it).
func command(cmd: Dictionary) -> int:
	var seq: int = _next_seq
	_next_seq += 1
	_send(NetProtocol.Type.COMMAND, {"seq": seq, "cmd": cmd})
	return seq


func helm(throttle: float, rotation: Vector3 = Vector3.ZERO) -> int:
	return command({"kind": "helm_input", "throttle": throttle, "rotation": rotation})


func fire(mount_index: int = 0) -> int:
	return command({"kind": "fire", "mount_index": mount_index})


func set_pips(subsystem_kind: int, pips: int) -> int:
	return command({"kind": "set_pips", "subsystem_kind": subsystem_kind, "pips": pips})


## Sends a raw, already-encoded message (tests: malformed or foreign messages).
func send_raw(data: PackedByteArray) -> void:
	_queue.push(NetChunker.STREAM_CONTROL, data)
	_flush()


# --- Internals. ---


func _send(type: NetProtocol.Type, fields: Dictionary) -> void:
	_queue.push(NetChunker.STREAM_CONTROL, NetProtocol.encode(type, fields))


func _flush() -> void:
	if _peer == null or _peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_queue.begin_pump()
	while _queue.peek_size() > 0:
		_peer.send(_queue.take_bundle(NetTransport.BUNDLE_MAX))


func _on_message(stream: int, data: PackedByteArray) -> void:
	arrivals.append(stream)
	var type: int = NetProtocol.type_of(data)
	if type == NetProtocol.Type.SNAPSHOT:
		if keep_raw:
			raw_snapshots[SnapshotBuilder.peek(data)[0]] = data
		if view.apply(data):
			stats["snapshots"] += 1
			if SnapshotBuilder.peek(data)[1]:
				stats["fulls"] += 1
				_force_ack = true
		else:
			stats["bad_snapshots"] += 1
		return
	var msg: Dictionary = NetProtocol.decode(data)
	match type:
		NetProtocol.Type.WELCOME:
			welcome = msg
			token = msg["token"]
			session_id = msg["session"]
			state = State.WELCOMED
			view = NetViewState.new(NetCodec.period_units(msg["period"]))
			# A fresh session, or a relaunched client behind the server's cursor, starts
			# after ev_from; a reconnect within the process keeps its inbox (it dedups).
			if not msg["resumed"] or inbox.last_seq < msg["ev_from"]:
				inbox = NetEventInbox.new(msg["ev_from"])
			_acked = Vector2i(-1, -1)
		NetProtocol.Type.HELLO_REJECTED:
			reject_reason = msg.get("reason", "")
			state = State.REJECTED
			_peer.close(1000, reject_reason)
		NetProtocol.Type.CATALOGUE:
			catalogue = msg
		NetProtocol.Type.EVENT:
			for e: Dictionary in inbox.receive(msg):
				_events.append(e)
				stats["events"] += 1
		NetProtocol.Type.VOICE:
			voice_clips.append(msg)
			stats["voice"] += 1


func _maybe_ack() -> void:
	if state != State.WELCOMED:
		return
	var now: Vector2i = Vector2i(view.seq, inbox.last_seq)
	var due: bool = Time.get_ticks_usec() - _last_ack_us >= ACK_INTERVAL_US
	if now != _acked and (due or _force_ack):
		_queue.push(NetChunker.STREAM_CONTROL, NetProtocol.ack(now.x, now.y))
		_acked = now
		_last_ack_us = Time.get_ticks_usec()
		_force_ack = false
