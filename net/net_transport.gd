class_name NetTransport
extends RefCounted
## The server's net thread (FT-NET-040, D111): it owns every socket (accept, poll,
## receive, decode), the per-connection send queues, stall detection (NetResync), the
## per-session event outboxes and the snapshot encoder (SnapshotBuilder), so the sim
## tick on the main thread holds only the sim. The main thread talks to it through two
## mutex-protected queues: it posts operations (send, close, bind a connection to a
## session, set a session's view key, events, state copies, voice) and takes inbound
## decoded messages. Session logic (handshake decisions, lobby, claims, validation)
## stays on the main thread (ServerSession). See net/README.md.

## Inbound pseudo-type for a connection that closed (no wire message has type 0).
const CLOSED: int = 0
## Snapshot capture stamps kept for the snapshot-age log (about 40 s at 30 Hz).
const STAMP_KEEP: int = 1200
## Most bytes in one WebSocket message (a bundle of chunks): under the 64 KiB
## WebSocketPeer buffers the server keeps at their defaults (D108).
const BUNDLE_MAX: int = 48 * 1024
## Close codes (docs/protocol.md).
const CLOSE_REJECTED: int = 4000
const CLOSE_TAKEN_OVER: int = 4001
const CLOSE_SEND_FAILED: int = 4002
const CLOSE_PROTOCOL: int = 4003
## More than NetResync.QUEUED_LIMIT queued for a connection without a view key.
const CLOSE_QUEUE_FULL: int = 4004
## How often the net thread publishes stats() (us).
const STATS_INTERVAL_US: int = 20_000
## How long a closing connection waits for the client to close first (us).
const CLOSE_LINGER_US: int = 1_000_000
## A closing connection still open after this long is dropped without the close
## handshake (a client that doesn't read never answers it) (us).
const CLOSE_TIMEOUT_US: int = 5_000_000
## A connection is closed once it has sent this many malformed messages.
const MAX_ERRORS: int = 16
## Largest message a client may send (bytes); the chunker drops longer ones.
const MAX_CLIENT_MESSAGE: int = 64 * 1024
## A connection without a session (no accepted Hello) is closed after this long (us).
const HELLO_TIMEOUT_US: int = 5_000_000
## Most connections without a session at once; more wait in the listen backlog (the
## clients' TCP retries) until one gets a session or closes.
const MAX_SESSIONLESS: int = 16
## Load probe row layouts (probe_dump()).
const SNAP_FIELDS: Array[String] = [
	"unix_us",
	"seq",
	"stamp_us",
	"restore_us",
	"build_us",
	"send_us",
	"keys",
	"sends",
	"delta_messages",
	"full_messages",
	"section_updates",
	"near_sets_us",
	"kin_us",
	"status_us",
	"helm_us",
	"engineering_us",
	"mounts_us",
	"contacts_us",
	"near_us",
	"projectiles_us",
	"ownership_us",
]
## ops_us includes SimCopy.restore; snapshot_us is _snapshot() (build and queue).
const SECOND_FIELDS: Array[String] = [
	"unix_us", "loops", "poll_us", "pump_us", "ops_us", "snapshot_us"
]


class Conn:
	extends RefCounted
	var id: int = 0
	var peer: WebSocketPeer
	var chunker: NetChunker = NetChunker.new()
	var queue: NetSendQueue
	var resync: NetResync
	var session: int = -1
	var view_key: String = ""
	## When the connection was accepted (us).
	var opened_us: int = 0
	var closing: bool = false
	## When the connection started closing (us), and the code and reason it closes with.
	var closing_since_us: int = 0
	var close_code: int = 1000
	var close_reason: String = ""
	var errors: int = 0
	var stats: Dictionary = {"bytes": 0, "ws_messages": 0, "fulls": 0, "deltas": 0, "skipped": 0}


## Stall limit in unacknowledged snapshots (D106).
var lag_limit: int = NetResync.LAG_LIMIT
## Chunk payload size (FT-NET-038); tests lower it to force chunking.
var chunk_size: int = NetChunker.DEFAULT_CHUNK_SIZE
## Voice chunks per pump when the high lane is empty.
var voice_per_pump: int = 1
## Net thread idle sleep per loop (us).
var loop_sleep_us: int = 1000
## Load-gate probe (#11, D161): when set before start(), the net thread records every
## snapshot's costs and the capture stamp it was built from, and once a second its loop
## costs and every connection's byte counters; read them with probe_dump() after stop().
var probe: bool = false

var _tcp: TCPServer = TCPServer.new()
var _thread: Thread
var _mutex: Mutex = Mutex.new()
var _running: bool = false
var _ops: Array = []
var _inbound: Array = []
var _stats: Dictionary = {}
# Net thread only from here on.
var _conns: Dictionary[int, Conn] = {}
## Session -> the connection bound to it.
var _by_session: Dictionary[int, Conn] = {}
var _outboxes: Dictionary[int, NetEventOutbox] = {}
var _builder: SnapshotBuilder = SnapshotBuilder.new()
var _state: SimWorld
## The last state restored, for repost_state().
var _last_state: SimWorld
var _snap_seq: int = 0
## Snapshot seq -> unix us of the capture it was built from (a re-encoded idle state
## counts from its encode time), the newest STAMP_KEEP seqs: the server's side of the
## snapshot age (D199). Read from the main thread through stamp_of().
var _stamps: Dictionary = {}
var _state_fresh: bool = false
var _next_conn: int = 1
var _published_us: int = 0
var _totals: Dictionary = {
	"snapshots": 0, "sends": 0, "delta_messages": 0, "full_messages": 0, "errors": 0
}
## Unix time (us) the main thread captured the state now in _state (post_state).
var _state_stamp_us: int = 0
var _restore_us: int = 0
## Probe records (net thread; probe_dump() after stop()): one row of SNAP_FIELDS per
## snapshot, one row of SECOND_FIELDS and one {conn: [session, view_key, bytes,
## ws_messages, fulls, deltas, stalls, skipped]} per second.
var _probe_snaps: PackedInt64Array = PackedInt64Array()
var _probe_seconds: PackedInt64Array = PackedInt64Array()
var _probe_conns: Array[Dictionary] = []
var _probe_acc: PackedInt64Array = PackedInt64Array([0, 0, 0, 0, 0])
var _probe_next_us: int = 0


## Listens on bind_address:port (port 0 picks a free one) and starts the net thread.
func start(port: int, bind_address: String) -> Error:
	var err: Error = _tcp.listen(port, bind_address)
	if err != OK:
		return err
	_builder.chunk_size = chunk_size
	_builder.time_parts = probe
	_running = true
	_thread = Thread.new()
	_thread.start(_run)
	return OK


## The bound WebSocket port.
func port() -> int:
	return _tcp.get_local_port()


## Stops the thread and closes every socket.
func stop() -> void:
	if _thread == null:
		return
	_mutex.lock()
	_running = false
	_mutex.unlock()
	_thread.wait_to_finish()
	_thread = null
	for c: Conn in _conns.values():
		c.peer.close(1001, "server stopped")
		c.peer.poll()
	_conns.clear()
	_tcp.stop()


# --- Main-thread API: each call queues an operation for the net thread. ---


## Queues a message for a connection on a stream's lane.
func send(conn: int, data: PackedByteArray, stream: int = NetChunker.STREAM_CONTROL) -> void:
	_post(["send", conn, stream, data])


## Closes a connection after its queued messages have gone.
func close(conn: int, code: int, reason: String) -> void:
	_post(["close", conn, code, reason])


## Binds a connection to a session and sends Welcome (its ev_from is filled in here from
## the session's outbox). A session already bound to another connection is taken over:
## that connection is closed. new_session starts an empty outbox.
func bind(
	conn: int, session: int, welcome: Dictionary, view_key: String, new_session: bool
) -> void:
	_post(["bind", conn, session, welcome, view_key, new_session])


## Sets the view key a session's snapshots use ("" for none); the next one is full.
func set_view(session: int, view_key: String) -> void:
	_post(["view", session, view_key])


## Adds an event to each listed session's reliable stream (FT-NET-011).
func post_event(sessions: PackedInt32Array, tick: int, type: String, payload: Dictionary) -> void:
	_post(["event", sessions, tick, type, payload])


## Hands over the state for the next snapshot (SimCopy.capture, restored on the net
## thread); a newer one replaces an older one the net thread hasn't encoded yet.
## stamp_us is the unix time of the capture (the load probe's snapshot age).
func post_state(state: Array, stamp_us: int = 0) -> void:
	_post(["state", state, stamp_us])


## Encodes the next snapshot from the last state posted again (the sim hasn't stepped
## since, so the main thread needn't capture it again).
func repost_state() -> void:
	_post(["state", null])


## A new world replaces the old one (the run reset, NetRunReset): the encoder starts
## from empty sections, the last state is dropped, and every client's next snapshot is
## full (its ticks restart). Post the ownership tables and the new state after it.
func reset_snapshots() -> void:
	_post(["reset"])


## A ship's claims and last writers for the OWNERSHIP section (ServerSession).
func post_ownership(ship: int, table: Dictionary) -> void:
	_post(["ownership", ship, table.duplicate(true)])


## Queues a voice clip (NetProtocol.Type.VOICE message) on a session's low lane.
func post_voice(session: int, data: PackedByteArray) -> void:
	_post(["voice", session, data])


## Inbound messages since the last call, oldest first: [conn, Dictionary with "t"].
func take_inbound() -> Array:
	_mutex.lock()
	var out: Array = _inbound
	_inbound = []
	_mutex.unlock()
	return out


## Counters published by the net thread: totals plus "conns": conn -> stats.
func stats() -> Dictionary:
	_mutex.lock()
	var out: Dictionary = _stats.duplicate(true)
	_mutex.unlock()
	return out


func _post(op: Array) -> void:
	_mutex.lock()
	_ops.append(op)
	_mutex.unlock()


# --- Net thread. ---


func _run() -> void:
	while true:
		_mutex.lock()
		var running: bool = _running
		var ops: Array = _ops
		_ops = []
		_mutex.unlock()
		if not running:
			return
		var t0: int = Time.get_ticks_usec() if probe else 0
		for op: Array in ops:
			_apply(op)
		var t1: int = Time.get_ticks_usec() if probe else 0
		_accept()
		var inbound: Array = _poll()
		var t2: int = Time.get_ticks_usec() if probe else 0
		if _state != null:
			_snapshot()
		var t3: int = Time.get_ticks_usec() if probe else 0
		_pump()
		_publish(inbound)
		if probe:
			_probe_loop(PackedInt64Array([t0, t1, t2, t3, Time.get_ticks_usec()]))
		OS.delay_usec(loop_sleep_us)


## Adds one loop's times (start, after ops, after poll, after the snapshot, after the
## pump) to the probe's per-second row, and once a second writes the row and every
## connection's counters.
func _probe_loop(t: PackedInt64Array) -> void:
	_probe_acc[0] += 1
	_probe_acc[1] += t[2] - t[1]
	_probe_acc[2] += t[4] - t[3]
	_probe_acc[3] += t[1] - t[0]
	_probe_acc[4] += t[3] - t[2]
	if t[4] < _probe_next_us:
		return
	_probe_next_us = t[4] + 1_000_000
	_probe_seconds.append(LoadProbe.unix_us())
	_probe_seconds.append_array(_probe_acc)
	_probe_acc.fill(0)
	var conns: Dictionary = {}
	for c: Conn in _conns.values():
		conns[c.id] = [
			c.session,
			c.view_key,
			c.stats["bytes"],
			c.stats["ws_messages"],
			c.stats["fulls"],
			c.stats["deltas"],
			c.resync.stall_count,
			c.stats["skipped"],
		]
	_probe_conns.append(conns)


## The probe's records (call after stop()): {snap_fields, snaps (flat rows),
## second_fields, seconds (flat rows), conns (one per second)}.
func probe_dump() -> Dictionary:
	return {
		"snap_fields": SNAP_FIELDS,
		"snaps": Array(_probe_snaps),
		"second_fields": SECOND_FIELDS,
		"seconds": Array(_probe_seconds),
		"conns": _probe_conns,
	}


func _apply(op: Array) -> void:
	match op[0]:
		"send":
			var c: Conn = _conns.get(op[1])
			if c != null:
				c.queue.push(op[2], op[3])
		"close":
			var c: Conn = _conns.get(op[1])
			if c != null:
				_close(c, op[2], op[3])
		"bind":
			_bind(op[1], op[2], op[3], op[4], op[5])
		"view":
			var c: Conn = _by_session.get(op[1])
			if c != null and not c.closing:
				c.view_key = op[2]
				c.resync.force_full()
		"event":
			_event(op[1], op[2], op[3], op[4])
		"state":
			# A repost (op[1] null) re-encodes the last state: same capture stamp, no restore.
			_restore_us = 0
			_state_fresh = op[1] != null
			if op[1] != null:
				var t0: int = Time.get_ticks_usec()
				_last_state = SimCopy.restore(op[1])
				_state_stamp_us = op[2]
				_restore_us = Time.get_ticks_usec() - t0
			_state = _last_state
		"voice":
			var c: Conn = _by_session.get(op[1])
			if c != null and not c.closing:
				c.queue.push(NetChunker.STREAM_VOICE, op[2])
		"ownership":
			_builder.set_ownership(op[1], op[2])
		"reset":
			_builder = SnapshotBuilder.new()
			_builder.chunk_size = chunk_size
			_state = null
			_last_state = null
			for c: Conn in _conns.values():
				c.resync.force_full()


func _bind(
	conn: int, session: int, welcome: Dictionary, view_key: String, new_session: bool
) -> void:
	var c: Conn = _conns.get(conn)
	if c == null:
		return
	var other: Conn = _by_session.get(session)
	if other != null and other != c:
		other.session = -1
		_close(other, CLOSE_TAKEN_OVER, "session taken over")
	_by_session[session] = c
	if new_session or not _outboxes.has(session):
		_outboxes[session] = NetEventOutbox.new()
	var box: NetEventOutbox = _outboxes[session]
	box.restart()
	c.session = session
	c.view_key = view_key
	c.resync = NetResync.new(lag_limit)
	welcome["ev_from"] = box.acked
	c.queue.push(NetChunker.STREAM_CONTROL, NetProtocol.encode(NetProtocol.Type.WELCOME, welcome))
	_push_events(c)


func _event(sessions: PackedInt32Array, tick: int, type: String, payload: Dictionary) -> void:
	for s: int in sessions:
		var box: NetEventOutbox = _outboxes.get(s)
		if box == null:
			continue
		box.add(tick, type, payload)
		var c: Conn = _by_session.get(s)
		if c != null:
			_push_events(c)


## Pushes the session's unpushed events unless the connection is waiting for a full
## snapshot, which then carries them (pushed right before it).
func _push_events(c: Conn) -> void:
	if c.closing or c.session < 0 or (c.view_key != "" and c.resync.holds_events()):
		return
	for bytes: PackedByteArray in _outboxes[c.session].take_unpushed():
		c.queue.push(NetChunker.STREAM_CONTROL, bytes)


## Accepts new connections while fewer than MAX_SESSIONLESS have no session.
func _accept() -> void:
	var sessionless: int = 0
	for c: Conn in _conns.values():
		if c.session < 0:
			sessionless += 1
	while sessionless < MAX_SESSIONLESS and _tcp.is_connection_available():
		sessionless += 1
		var tcp: StreamPeerTCP = _tcp.take_connection()
		tcp.set_no_delay(true)
		var c: Conn = Conn.new()
		c.id = _next_conn
		_next_conn += 1
		c.opened_us = Time.get_ticks_usec()
		c.peer = WebSocketPeer.new()
		c.peer.accept_stream(tcp)
		c.chunker.max_message_size = MAX_CLIENT_MESSAGE
		c.queue = NetSendQueue.new(chunk_size, voice_per_pump)
		c.resync = NetResync.new(lag_limit)
		_conns[c.id] = c


## Polls every socket and closes the connections that broke a rule; returns the inbound
## messages for the main thread.
func _poll() -> Array:
	var out: Array = []
	var now: int = Time.get_ticks_usec()
	for c: Conn in _conns.values():
		c.peer.poll()
		if c.peer.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			_conns.erase(c.id)
			if _by_session.get(c.session) == c:
				_by_session.erase(c.session)
			out.append([c.id, {"t": CLOSED, "code": c.peer.get_close_code(), "session": c.session}])
			continue
		while c.peer.get_available_packet_count() > 0:
			var packet: PackedByteArray = c.peer.get_packet()
			if not c.closing:
				_read(c, packet, out)
		if c.closing:
			if now - c.closing_since_us > CLOSE_TIMEOUT_US:
				c.peer.close(-1)
		elif c.errors >= MAX_ERRORS:
			_close(c, CLOSE_PROTOCOL, "malformed messages")
		elif c.session < 0 and now - c.opened_us > HELLO_TIMEOUT_US:
			_close(c, CLOSE_PROTOCOL, "no hello")
		elif c.view_key == "" and c.queue.high_bytes > NetResync.QUEUED_LIMIT:
			# No snapshots, so no stall policy: a client that doesn't read is closed and
			# resumes with its token (its events wait in the outbox).
			_close(c, CLOSE_QUEUE_FULL, "queue full")
	return out


## Reads one WebSocket message from a client: control-stream chunks only.
func _read(c: Conn, packet: PackedByteArray, out: Array) -> void:
	var errors_before: int = c.chunker.errors
	for chunk: PackedByteArray in c.chunker.unbundle(packet):
		if NetChunker.stream_of(chunk) != NetChunker.STREAM_CONTROL:
			c.errors += 1
			continue
		var msg: Dictionary = c.chunker.feed(chunk)
		if not msg.is_empty():
			_receive(c, msg["data"], out)
	c.errors += c.chunker.errors - errors_before


func _receive(c: Conn, data: PackedByteArray, out: Array) -> void:
	var type: int = NetProtocol.type_of(data)
	if not NetProtocol.FROM_CLIENT.has(type):
		c.errors += 1
		_totals["errors"] += 1
		return
	var msg: Dictionary = NetProtocol.decode(data)
	if type == NetProtocol.Type.HELLO and msg.is_empty():
		# Unreadable or another version's Hello: the main thread answers with a reason.
		out.append([c.id, {"t": type, "v": NetProtocol.hello_version(data), "invalid": true}])
		return
	if msg.is_empty():
		c.errors += 1
		_totals["errors"] += 1
		return
	if type == NetProtocol.Type.ACK:
		if c.session >= 0:
			c.resync.on_ack(msg["snap"])
			_outboxes[c.session].ack(msg["ev"])
		return
	if type != NetProtocol.Type.HELLO and c.session < 0:
		c.errors += 1
		return
	out.append([c.id, msg])


func _snapshot() -> void:
	var world: SimWorld = _state
	_state = null
	var keys: Dictionary = {}
	for c: Conn in _conns.values():
		if c.session >= 0 and c.view_key != "" and not c.closing:
			keys[c.view_key] = true
	if keys.is_empty():
		return
	_snap_seq += 1
	_record_stamp(_snap_seq, _state_stamp_us if _state_fresh else LoadProbe.unix_us())
	_state_fresh = false
	var t0: int = Time.get_ticks_usec()
	_builder.build(world, _snap_seq, keys.keys())
	var t1: int = Time.get_ticks_usec()
	var sends: int = 0
	for c: Conn in _conns.values():
		if c.session < 0 or c.view_key == "" or c.closing:
			continue
		var action: NetResync.Action = c.resync.decide(c.queue.high_bytes)
		if action == NetResync.Action.NONE:
			c.stats["skipped"] += 1
			continue
		var is_full: bool = action == NetResync.Action.FULL
		c.resync.on_sent(_snap_seq, is_full)
		if is_full:
			# Events held while the client lagged go right before the full snapshot.
			_push_events(c)
		c.queue.push_chunks(_builder.chunks(c.view_key, is_full))
		c.stats["fulls" if is_full else "deltas"] += 1
		_totals["sends"] += 1
		sends += 1
	_totals["snapshots"] += 1
	var counts: Dictionary = _builder.take_counts()
	_totals["delta_messages"] += counts["delta_messages"]
	_totals["full_messages"] += counts["full_messages"]
	if probe:
		(
			_probe_snaps
			. append_array(
				[
					LoadProbe.unix_us(),
					_snap_seq,
					_state_stamp_us,
					_restore_us,
					t1 - t0,
					Time.get_ticks_usec() - t1,
					keys.size(),
					sends,
					counts["delta_messages"],
					counts["full_messages"],
					counts["section_updates"],
				]
			)
		)
		_probe_snaps.append_array(_builder.part_us)
		_builder.part_us.fill(0)


func _record_stamp(seq: int, stamp_us: int) -> void:
	_mutex.lock()
	_stamps[seq] = stamp_us
	_stamps.erase(seq - STAMP_KEEP)
	_mutex.unlock()


## Unix us of the capture snapshot `seq` was built from, or 0 when it is older than the
## last STAMP_KEEP snapshots (or unknown). Main thread; a client's report joins its
## arrival times to these (SnapshotAgeStats).
func stamp_of(seq: int) -> int:
	_mutex.lock()
	var us: int = _stamps.get(seq, 0)
	_mutex.unlock()
	return us


func _pump() -> void:
	for c: Conn in _conns.values():
		if c.peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
			continue
		c.queue.begin_pump()
		while true:
			var room: int = mini(
				BUNDLE_MAX,
				c.peer.outbound_buffer_size - c.peer.get_current_outbound_buffered_amount()
			)
			var size: int = c.queue.peek_size()
			if size == 0 or size > room:
				break
			var bundle: PackedByteArray = c.queue.take_bundle(room)
			# The room check keeps the bundle within WebSocketPeer's buffer, so send()
			# fails only when the socket write itself fails (a reset connection). The
			# chunks have left the queue, so the stream is broken: close, and the client
			# resumes with its token and a full snapshot (FT-NET-037, D106).
			if c.peer.send(bundle) != OK:
				c.resync.on_send_error()
				_close(c, CLOSE_SEND_FAILED, "send failed")
				break
			c.stats["bytes"] += bundle.size()
			c.stats["ws_messages"] += 1
		c.peer.poll()
		# A client drops messages that arrive with the close frame, so the server lets
		# the client close first (NetClient does on HelloRejected and Bye) and closes
		# itself CLOSE_LINGER_US after the last message left.
		if c.closing and c.queue.is_empty() and c.peer.get_current_outbound_buffered_amount() == 0:
			if Time.get_ticks_usec() - c.closing_since_us > CLOSE_LINGER_US:
				c.peer.close(c.close_code, c.close_reason)


## Marks a connection closing: it sends what is queued (for example HelloRejected),
## then closes; nothing more is queued for it. A failed send or a full queue closes at
## once, and a connection whose WebSocket isn't open is dropped.
func _close(c: Conn, code: int, reason: String) -> void:
	if c.closing:
		return
	c.closing = true
	c.closing_since_us = Time.get_ticks_usec()
	c.close_code = code
	c.close_reason = reason
	if c.peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		c.peer.close(-1)
	elif code == CLOSE_SEND_FAILED or code == CLOSE_QUEUE_FULL:
		c.peer.close(code, reason)


func _publish(inbound: Array) -> void:
	var now: int = Time.get_ticks_usec()
	if now - _published_us < STATS_INTERVAL_US:
		if not inbound.is_empty():
			_mutex.lock()
			_inbound.append_array(inbound)
			_mutex.unlock()
		return
	_published_us = now
	var conns: Dictionary = {}
	for c: Conn in _conns.values():
		var s: Dictionary = c.stats.duplicate()
		s["session"] = c.session
		s["view_key"] = c.view_key
		s["high_bytes"] = c.queue.high_bytes
		s["low_bytes"] = c.queue.low_bytes
		s["stalled"] = c.resync.stalled
		s["stalls"] = c.resync.stall_count
		s["errors"] = c.errors
		s["acked_snap"] = c.resync.acked_seq
		s["last_sent"] = c.resync.last_sent_seq
		if c.closing:
			s["close_code"] = c.close_code
		conns[c.id] = s
	var outboxes: Dictionary = {}
	for s: int in _outboxes:
		outboxes[s] = {"pending": _outboxes[s].pending(), "acked": _outboxes[s].acked}
	_mutex.lock()
	_inbound.append_array(inbound)
	_stats = _totals.duplicate()
	_stats["conns"] = conns
	_stats["outboxes"] = outboxes
	_stats["snapshot_seq"] = _snap_seq
	_mutex.unlock()


## Open WebSocket connections, Hello or not, as of the last stats() publish (lags the
## net thread by up to STATS_INTERVAL_US). Reads under the mutex without copying.
func open_connections() -> int:
	_mutex.lock()
	var n: int = (_stats.get("conns", {}) as Dictionary).size()
	_mutex.unlock()
	return n


## Open connections bound to a session (past Hello), as of the last stats() publish.
func bound_connections() -> int:
	var n: int = 0
	_mutex.lock()
	for s: Dictionary in (_stats.get("conns", {}) as Dictionary).values():
		if s["session"] >= 0:
			n += 1
	_mutex.unlock()
	return n
