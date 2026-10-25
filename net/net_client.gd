# gdlint: disable=max-public-methods
class_name NetClient
extends RefCounted
## Reusable headless client of the protocol (T041): connect, handshake (with a token to
## resume), apply snapshots into a NetViewState, acknowledge, send commands, deliver
## events in order (NetEventInbox), and resume by token after a drop. Poll-driven, no
## thread: call poll() every frame. Tests, the L4 bots and the #7 client shell use it.
## It never names sim/ (FT-ARC-005): commands are plain dictionaries
## ({"kind": "fire", "mount_index": 0}) that the server validates.

## Each event as it arrives, before take_events() hands it out: lets tools/l4 watch a
## client the station UI polls.
signal event_received(event: Dictionary)

## Lifecycle states.
enum State { IDLE, CONNECTING, WELCOMED, REJECTED, CLOSED }

## Acks at most this often (us), and at once after a full snapshot or a snapshot it
## couldn't apply (S9: every 200 ms is enough for the 15-snapshot stall limit and saves
## packets).
const ACK_INTERVAL_US: int = 200_000
## D199: a report goes out every STATS_INTERVAL_US with at most STATS_MAX_PAIRS pairs of
## snapshot seq and arrival unix us.
const STATS_INTERVAL_US: int = 2_000_000
const STATS_MAX_PAIRS: int = 400

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
## Counters: snapshots applied, fulls, failed applies, events, voice clips.
var stats: Dictionary = {"snapshots": 0, "fulls": 0, "bad_snapshots": 0, "events": 0, "voice": 0}
## Received voice clips (NetProtocol.Type.VOICE fields).
var voice_clips: Array[Dictionary] = []
## Stream of every completed inbound message, in arrival order (tests).
var arrivals: PackedByteArray = PackedByteArray()
## Test hook: keep each snapshot's bytes by seq in raw_snapshots.
var keep_raw: bool = false
var raw_snapshots: Dictionary = {}
## Load-gate hook (D161): when true, each applied snapshot appends its seq and the unix
## time it arrived, before decoding (us), to snapshot_log.
var log_snapshots: bool = false
var snapshot_log: PackedInt64Array = PackedInt64Array()
## D199: whether the client reports snapshot arrival times to the server, and the
## browser's user agent it sends with them ("" off the web).
var report_stats: bool = true
var user_agent: String = ""

var _peer: WebSocketPeer
var _chunker: NetChunker = NetChunker.new()
var _queue: NetSendQueue = NetSendQueue.new()
var _events: Array[Dictionary] = []
var _next_seq: int = 1
var _acked: Vector2i = Vector2i(-1, -1)
var _last_ack_us: int = 0
var _force_ack: bool = false
## Sent Ack snap -1 for the current need_full (once: a second would cost another full).
var _full_asked: bool = false
var _hello_sent: bool = false
var _arrivals: PackedInt64Array = PackedInt64Array()
var _last_report_us: int = 0


## Connects to ws://host:port and sends Hello once open (with the token, if any).
func connect_to(server_url: String) -> Error:
	url = server_url
	_peer = WebSocketPeer.new()
	_peer.inbound_buffer_size = inbound_buffer_size
	_chunker = NetChunker.new()
	_queue = NetSendQueue.new()
	welcome = {}
	_hello_sent = false
	_arrivals.clear()
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
	_maybe_report()
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


## Casts or withdraws a "Run again" vote after the ship's outcome; the host's vote
## resets the run at once (D178).
func run_again(ship: int, vote: bool) -> void:
	_send(NetProtocol.Type.RUN_AGAIN, {"ship": ship, "vote": vote})


func takeover(ship: int, entry: String) -> void:
	_send(NetProtocol.Type.TAKEOVER, {"ship": ship, "entry": entry})


## Sends a crew command; returns its seq (`command_rejected` events name it).
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


## Sets the ship's alert level: 0 Normal, 1 Yellow, 2 Red (FT-STN-008).
func set_alert(level: int) -> void:
	_send(NetProtocol.Type.ALERT, {"level": level})


## Places a mark: slot -1 takes the first free one, name "" the slot's default; contact
## >= 0 attaches it to that contact, else it is free at pos on site (FT-SPA-012 to
## FT-SPA-014).
func place_mark(slot: int, name: String, contact: int, site: int, pos: Vector3) -> void:
	_mark("place", slot, name, contact, site, pos)


## Moves a mark to pos on site, or attaches it to a contact (contact >= 0).
func move_mark(slot: int, contact: int, site: int, pos: Vector3) -> void:
	_mark("move", slot, "", contact, site, pos)


## Renames a mark ("" restores the slot's default name).
func rename_mark(slot: int, name: String) -> void:
	_mark("rename", slot, name, -1, -1, Vector3.ZERO)


func delete_mark(slot: int) -> void:
	_mark("delete", slot, "", -1, -1, Vector3.ZERO)


## Pings an item on every screen of the ship (FT-SPA-016): kind "contact" (id), "mark"
## (id = slot), "card" (id = a Comms card, FT-CPT-005), "site" (site) or "point" (pos on
## site).
func ping(kind: String, id: int, site: int, pos: Vector3) -> void:
	_send(
		NetProtocol.Type.PING,
		{"kind": kind, "id": id, "site": site, "x": pos.x, "y": pos.y, "z": pos.z}
	)


## Switches the ship's main screen to view (MainScreen.View): the Captain, or Relay with
## no Captain seated (FT-MSC-005).
func set_main_view(view: int) -> void:
	_send(NetProtocol.Type.MAIN_VIEW, {"view": view})


## Relay (strand B of #9). Sends one of the ship's marks to an allied ship's Relay inbox
## (FT-RLY-008); accepts the inbox item `id` as a mark, replacing `slot` when all 8 are in
## use (slot -1 takes a free one), or declines it (FT-RLY-009, FT-SPA-022).
func send_mark(slot: int, to_ship: int) -> void:
	_send(NetProtocol.Type.MARK_SEND, {"slot": slot, "ship": to_ship})


func accept_mark(id: int, slot: int = -1) -> void:
	_send(NetProtocol.Type.MARK_ACCEPT, {"id": id, "accept": true, "slot": slot})


func decline_mark(id: int) -> void:
	_send(NetProtocol.Type.MARK_ACCEPT, {"id": id, "accept": false, "slot": -1})


## Routes and hazard zones are Relay's Mark ops: a waypoint on route `route`, a hazard of
## `radius_m` (a multiple of 100 m) at a point, deleting a zone by id (FT-RLY-005).
func route_add(route: int, site: int, pos: Vector3) -> void:
	_mark("route_add", route, "", -1, site, pos)


func route_clear(route: int) -> void:
	_mark("route_clear", route, "", -1, -1, Vector3.ZERO)


func hazard_add(radius_m: float, site: int, pos: Vector3) -> void:
	_mark("hazard_add", roundi(radius_m / 100.0), "", -1, site, pos)


func hazard_delete(id: int) -> void:
	_mark("hazard_delete", id, "", -1, -1, Vector3.ZERO)


## Sends a raw, already-encoded message (tests: malformed or foreign messages).
func send_raw(data: PackedByteArray) -> void:
	_queue.push(NetChunker.STREAM_CONTROL, data)
	_flush()


# --- Internals. ---


func _send(type: NetProtocol.Type, fields: Dictionary) -> void:
	_queue.push(NetChunker.STREAM_CONTROL, NetProtocol.encode(type, fields))


func _mark(op: String, slot: int, name: String, contact: int, site: int, pos: Vector3) -> void:
	var fields: Dictionary = {"op": op, "slot": slot, "name": name, "contact": contact}
	fields.merge({"site": site, "x": pos.x, "y": pos.y, "z": pos.z})
	_send(NetProtocol.Type.MARK, fields)


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
		var got_us: int = LoadProbe.unix_us() if (log_snapshots or report_stats) else 0
		if view.apply(data):
			stats["snapshots"] += 1
			if report_stats:
				_arrivals.append(view.seq)
				_arrivals.append(got_us)
				if _arrivals.size() > 2 * STATS_MAX_PAIRS * 4:
					_arrivals = _arrivals.slice(_arrivals.size() - 2 * STATS_MAX_PAIRS * 4)
			if log_snapshots:
				snapshot_log.append(view.seq)
				snapshot_log.append(got_us)
			if SnapshotBuilder.peek(data)[1]:
				stats["fulls"] += 1
				_force_ack = true
		else:
			stats["bad_snapshots"] += 1
			_force_ack = not _full_asked
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
			_full_asked = false
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
				event_received.emit(e)
		NetProtocol.Type.VOICE:
			voice_clips.append(msg)
			stats["voice"] += 1


## Sends the arrivals gathered since the last report (D199).
func _maybe_report() -> void:
	if state != State.WELCOMED or _arrivals.is_empty():
		return
	var now: int = Time.get_ticks_usec()
	if now - _last_report_us < STATS_INTERVAL_US:
		return
	_last_report_us = now
	var take: int = mini(_arrivals.size(), 2 * STATS_MAX_PAIRS)
	var pairs: PackedInt64Array = _arrivals.slice(0, take)
	_arrivals = _arrivals.slice(take)
	_send(
		NetProtocol.Type.CLIENT_STATS,
		{"sent_us": LoadProbe.unix_us(), "ua": user_agent.left(200), "pairs": pairs}
	)


## Acks the newest snapshot applied (0 before the first) and event delivered; a view
## that needs a full snapshot sends snap -1 once, then 0 until the full one arrives.
func _maybe_ack() -> void:
	if state != State.WELCOMED:
		return
	var snap: int = maxi(view.seq, 0)
	if view.need_full:
		snap = 0 if _full_asked else -1
	else:
		_full_asked = false
	var now: Vector2i = Vector2i(snap, inbox.last_seq)
	var due: bool = Time.get_ticks_usec() - _last_ack_us >= ACK_INTERVAL_US
	if now != _acked and (due or _force_ack):
		_queue.push(NetChunker.STREAM_CONTROL, NetProtocol.ack(now.x, now.y))
		_acked = now
		_full_asked = _full_asked or snap < 0
		_last_ack_us = Time.get_ticks_usec()
		_force_ack = false
