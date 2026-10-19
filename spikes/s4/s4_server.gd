extends SceneTree
## S4 spike server (T019, TECH-2): TCPServer + WebSocketPeer, a 60 Hz fake sim,
## 30 Hz snapshots (full on join or resync, deltas against the client's acked
## base), a reliable event stream, session tokens, backpressure and chunking.
##
## godot --headless --path . -s res://spikes/s4/s4_server.gd -- [flags]
## Flags (defaults in brackets): --port [47810] --ships [6] --contacts [40]
## --layout-floats [2048] --tick-hz [60] --snapshot-hz [30] --run-for s [60]
## --log path [none] --lag-limit snapshots [15] --grace-s [10]
## --chunk-size bytes [16384] --voice-to client-name [none] --voice-at s [-1]
## --voice-seconds [3] --voice-per-pump chunks [1] --max-fps [120] --seed [1]
## Messages are var_to_bytes Dictionaries inside S4Chunker chunks.

const PROTO: int = 1
const HISTORY: int = 64


class Conn:
	extends RefCounted
	var peer: WebSocketPeer
	var id: int = 0
	var name: String = ""
	var token: String = ""
	var joined: bool = false
	var queue: S4SendQueue
	var resync: S4Resync
	var chunker: S4Chunker = S4Chunker.new()
	var acked_ev: int = 0
	var max_buffered: int = 0
	var bytes_out: int = 0
	var skipped: int = 0
	var blocked_pumps: int = 0
	var voice_due: bool = false


var port: int = 47810
var ships: int = 6
var contacts: int = 40
var layout_floats: int = 2048
var tick_hz: int = 60
var snapshot_hz: int = 30
var run_for: float = 60.0
var log_path: String = ""
var lag_limit: int = 15
var grace_s: float = 10.0
var chunk_size: int = S4Chunker.DEFAULT_CHUNK_SIZE
var voice_to: String = ""
var voice_at: float = -1.0
var voice_seconds: float = 3.0
var voice_per_pump: int = 1
var max_fps: int = 120
var seed_value: int = 1

var _tcp: TCPServer = TCPServer.new()
var _conns: Array[Conn] = []
var _sim: S4FakeSim
var _sessions: S4Sessions
var _events: Array[Dictionary] = []
var _event_bytes: Dictionary = {}
var _event_seq: int = 0
var _history: Dictionary = {}
var _delta_cache: Dictionary = {}
var _snap_seq: int = 0
var _next_conn_id: int = 1
var _join_count: int = 0
var _start_ticks: int = 0
var _next_tick_ticks: int = 0
var _tick_us: int = 0
var _voice_done: bool = false
var _log: FileAccess
var _stat_next_s: int = 1
var _stat_work_max: int = 0
var _stat_work_sum: int = 0
var _stat_frames: int = 0
var _full_bytes: int = 0
var _delta_bytes_sum: int = 0
var _delta_count: int = 0
var _delta_encodes: int = 0


func _initialize() -> void:
	_parse_args(OS.get_cmdline_user_args())
	Engine.max_fps = max_fps
	if log_path != "":
		_log = FileAccess.open(log_path, FileAccess.WRITE)
	_sim = S4FakeSim.new(ships, contacts, layout_floats, seed_value)
	_sessions = S4Sessions.new(int(grace_s * 1_000_000))
	var probe: WebSocketPeer = WebSocketPeer.new()
	_note(
		"defaults",
		{
			"inbound_buffer_size": probe.inbound_buffer_size,
			"outbound_buffer_size": probe.outbound_buffer_size,
			"max_queued_packets": probe.max_queued_packets,
			"encode_buffer_max_size": probe.encode_buffer_max_size,
			"heartbeat_interval": probe.heartbeat_interval,
		}
	)
	var err: Error = _tcp.listen(port, "127.0.0.1")
	if err != OK:
		push_error("listen failed on %d: %s" % [port, error_string(err)])
		quit(1)
		return
	_start_ticks = Time.get_ticks_usec()
	_tick_us = int(1_000_000 / float(tick_hz))
	_next_tick_ticks = _start_ticks + _tick_us
	_note("listening", {"port": port, "ships": ships, "contacts": contacts, "chunk": chunk_size})


func _process(_delta: float) -> bool:
	var frame_start: int = Time.get_ticks_usec()
	_accept()
	_poll_all()
	var ticks: int = 0
	while frame_start >= _next_tick_ticks and ticks < 4:
		_sim_tick()
		_next_tick_ticks += _tick_us
		ticks += 1
	if frame_start >= _next_tick_ticks:
		_next_tick_ticks = frame_start + _tick_us
	_pump_all()
	var work: int = Time.get_ticks_usec() - frame_start
	_stat_work_max = maxi(_stat_work_max, work)
	_stat_work_sum += work
	_stat_frames += 1
	var elapsed: float = (frame_start - _start_ticks) / 1_000_000.0
	if elapsed >= _stat_next_s:
		_stats()
		_stat_next_s += 1
	if elapsed >= run_for:
		_finish()
		return true
	return false


func _accept() -> void:
	while _tcp.is_connection_available():
		var tcp: StreamPeerTCP = _tcp.take_connection()
		tcp.set_no_delay(true)
		var c: Conn = Conn.new()
		c.peer = WebSocketPeer.new()
		c.peer.accept_stream(tcp)
		c.id = _next_conn_id
		_next_conn_id += 1
		c.queue = S4SendQueue.new(chunk_size, voice_per_pump)
		_conns.append(c)


func _poll_all() -> void:
	var now_us: int = _unix_us()
	var closed: Array[Conn] = []
	for c: Conn in _conns:
		c.peer.poll()
		var state: WebSocketPeer.State = c.peer.get_ready_state()
		if state == WebSocketPeer.STATE_CLOSED:
			closed.append(c)
			continue
		while c.peer.get_available_packet_count() > 0:
			var msg: Dictionary = c.chunker.feed(c.peer.get_packet())
			if not msg.is_empty():
				_on_message(c, bytes_to_var(msg["data"]), now_us)
	for c: Conn in closed:
		_conns.erase(c)
		if c.token != "":
			_sessions.drop(c.token, now_us)
		_note("drop", {"client": c.name, "conn": c.id, "code": c.peer.get_close_code()})
	for token: String in _sessions.expire(now_us):
		_note("grace_expired", {"token": token.left(8)})


func _on_message(c: Conn, m: Dictionary, now_us: int) -> void:
	match m.get("t", ""):
		"hello":
			_on_hello(c, m, now_us)
		"ack":
			if c.joined:
				c.resync.on_ack(m["snap"])
				c.acked_ev = maxi(c.acked_ev, m["ev"])
				_sessions.set_acked_event(c.token, c.acked_ev)
				_trim_events()


func _on_hello(c: Conn, m: Dictionary, now_us: int) -> void:
	c.name = m.get("name", "")
	if int(m.get("proto", 0)) != PROTO:
		_send(c, S4Chunker.STREAM_CONTROL, {"t": "reject", "reason": "protocol mismatch"})
		c.peer.close(4000, "protocol mismatch")
		return
	var token: String = m.get("token", "")
	var session: Dictionary = _sessions.resume(token, now_us) if token != "" else {}
	var resumed: bool = not session.is_empty()
	var seat: Dictionary
	if resumed:
		seat = session["seat"]
		c.acked_ev = session["acked_ev"]
		for other: Conn in _conns:
			if other != c and other.token == token:
				other.token = ""
				other.peer.close(4001, "replaced")
	else:
		if token != "":
			_note("token_unknown", {"client": c.name})
		seat = _sim.seat_for(_join_count)
		_join_count += 1
		c.acked_ev = _event_seq
		token = _sessions.issue(seat, c.acked_ev)
	c.token = token
	c.joined = true
	c.resync = S4Resync.new(lag_limit)
	_send(
		c,
		S4Chunker.STREAM_CONTROL,
		{
			"t": "welcome",
			"token": token,
			"seat": seat,
			"resumed": resumed,
			"ev_from": c.acked_ev,
			"client": c.id,
		}
	)
	_note("join", {"client": c.name, "conn": c.id, "resumed": resumed, "seat": seat})


func _sim_tick() -> void:
	var event: Dictionary = _sim.step(1.0 / tick_hz)
	if not event.is_empty():
		_event_seq += 1
		event["seq"] = _event_seq
		event["t"] = "ev"
		_events.append(event)
		_event_bytes[_event_seq] = var_to_bytes(event)
		for c: Conn in _conns:
			if c.joined and not c.resync.holds_events():
				c.queue.push(S4Chunker.STREAM_CONTROL, _event_bytes[_event_seq])
	if _sim.tick % int(tick_hz / float(snapshot_hz)) == 0:
		_snapshot_tick()


func _snapshot_tick() -> void:
	_snap_seq += 1
	var elapsed: float = (Time.get_ticks_usec() - _start_ticks) / 1_000_000.0
	_history[_snap_seq] = {"state": _sim.state(), "tick": _sim.tick, "sent_us": _unix_us()}
	_history.erase(_snap_seq - HISTORY)
	_delta_cache.erase(_snap_seq - HISTORY)
	if voice_at >= 0 and not _voice_done and elapsed >= voice_at:
		for c: Conn in _conns:
			if c.joined and c.name == voice_to:
				c.voice_due = true
				_voice_done = true
	for c: Conn in _conns:
		if c.joined:
			if c.voice_due:
				_queue_voice(c)
			_send_snapshot(c)


## Queues a clip, then forces a full snapshot behind it in the same pump: the
## snapshot chunks must still leave first (FT-NET-038).
func _queue_voice(c: Conn) -> void:
	c.voice_due = false
	var samples: int = int(22050 * voice_seconds)
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(samples * 2)
	for i: int in range(samples):
		pcm.encode_s16(i * 2, int(8000.0 * sin(TAU * 440.0 * i / 22050.0)))
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(pcm)
	var sha: String = ctx.finish().hex_encode()
	var bytes: PackedByteArray = var_to_bytes({"t": "voice", "sha": sha, "pcm": pcm})
	var msg_id: int = c.queue.push(S4Chunker.STREAM_VOICE, bytes)
	c.resync.force_full()
	_note(
		"voice_queued",
		{
			"client": c.name,
			"msg": msg_id,
			"bytes": bytes.size(),
			"chunks": ceili(float(bytes.size()) / chunk_size),
		}
	)


func _send_snapshot(c: Conn) -> void:
	var stalls_before: int = c.resync.stall_count
	var buffered: int = c.peer.get_current_outbound_buffered_amount()
	var action: S4Resync.Action = c.resync.decide(c.queue.high_bytes)
	if c.resync.stall_count != stalls_before:
		_note(
			"stall",
			{
				"client": c.name,
				"seq": _snap_seq,
				"acked": c.resync.acked_seq,
				"buffered": buffered,
				"queued": c.queue.high_bytes,
			}
		)
	var entry: Dictionary = _history[_snap_seq]
	var base: int = c.resync.delta_base()
	if action == S4Resync.Action.DELTA and not _history.has(base):
		action = S4Resync.Action.FULL
	if action == S4Resync.Action.NONE:
		c.skipped += 1
		return
	var bytes: PackedByteArray
	if action == S4Resync.Action.FULL:
		var events: Array[Dictionary] = []
		for e: Dictionary in _events:
			if int(e["seq"]) > c.acked_ev:
				events.append(e)
		bytes = var_to_bytes(
			{
				"t": "snap",
				"seq": _snap_seq,
				"base": -1,
				"tick": entry["tick"],
				"sent_us": entry["sent_us"],
				"ents": entry["state"],
				"events": events,
			}
		)
		_full_bytes = bytes.size()
		_note(
			"full",
			{
				"client": c.name,
				"seq": _snap_seq,
				"bytes": bytes.size(),
				"events": events.size(),
				"resync": c.resync.stalled,
			}
		)
	else:
		bytes = _delta_bytes(base)
		_delta_bytes_sum += bytes.size()
		_delta_count += 1
	c.queue.push(S4Chunker.STREAM_SNAPSHOT, bytes)
	c.resync.on_sent(_snap_seq, action == S4Resync.Action.FULL)


## One encode per (snapshot, base) pair, shared by every client on that base
## (the FT-NET-040 idea; here all clients share one view).
func _delta_bytes(base: int) -> PackedByteArray:
	var per_seq: Dictionary = _delta_cache.get(_snap_seq, {})
	if per_seq.has(base):
		return per_seq[base]
	var entry: Dictionary = _history[_snap_seq]
	var change: Dictionary = S4Snapshot.delta(_history[base]["state"], entry["state"])
	change["t"] = "snap"
	change["seq"] = _snap_seq
	change["base"] = base
	change["tick"] = entry["tick"]
	change["sent_us"] = entry["sent_us"]
	var bytes: PackedByteArray = var_to_bytes(change)
	per_seq[base] = bytes
	_delta_cache[_snap_seq] = per_seq
	_delta_encodes += 1
	return bytes


func _pump_all() -> void:
	for c: Conn in _conns:
		if c.peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
			continue
		c.queue.begin_pump()
		var limit: int = c.peer.outbound_buffer_size
		while true:
			var size: int = c.queue.peek_size()
			if size == 0:
				break
			var buffered: int = c.peer.get_current_outbound_buffered_amount()
			if buffered + size > limit:
				c.blocked_pumps += 1
				break
			var chunk: PackedByteArray = c.queue.next_chunk()
			var err: Error = c.peer.send(chunk)
			if err != OK:
				# The chunk is gone from the queue, so the stream is broken: drop
				# the connection and let the client resume with its token, which
				# brings a full snapshot (D106 counts a failed send as a stall).
				if c.resync != null:
					c.resync.on_send_error()
				_note("send_error", {"client": c.name, "err": error_string(err)})
				c.peer.close(-1)
				break
			c.bytes_out += chunk.size()
		c.peer.poll()
		c.max_buffered = maxi(c.max_buffered, c.peer.get_current_outbound_buffered_amount())


func _send(c: Conn, stream: int, m: Dictionary) -> void:
	c.queue.push(stream, var_to_bytes(m))


func _trim_events() -> void:
	var low: int = _sessions.min_acked_event(_event_seq)
	while not _events.is_empty() and int(_events[0]["seq"]) <= low:
		_event_bytes.erase(_events[0]["seq"])
		_events.pop_front()


func _stats() -> void:
	var clients: Array = []
	for c: Conn in _conns:
		clients.append(
			[c.name, c.bytes_out, c.max_buffered, c.queue.high_bytes, c.queue.low_bytes, c.skipped]
		)
	_note(
		"stats",
		{
			"frames": _stat_frames,
			"work_mean_us": _stat_work_sum / maxi(1, _stat_frames),
			"work_max_us": _stat_work_max,
			"clients": clients,
		}
	)
	_stat_work_max = 0
	_stat_work_sum = 0
	_stat_frames = 0


func _finish() -> void:
	var clients: Dictionary = {}
	for c: Conn in _conns:
		if c.joined:
			clients[c.name] = {
				"stalls": c.resync.stall_count,
				"fulls": c.resync.full_count,
				"skipped": c.skipped,
				"max_buffered": c.max_buffered,
				"blocked_pumps": c.blocked_pumps,
				"bytes_out": c.bytes_out,
			}
	_note(
		"summary",
		{
			"snapshots": _snap_seq,
			"events": _event_seq,
			"full_bytes": _full_bytes,
			"delta_mean_bytes": _delta_bytes_sum / maxi(1, _delta_count),
			"delta_sends": _delta_count,
			"delta_encodes": _delta_encodes,
			"clients": clients,
		}
	)
	for c: Conn in _conns:
		c.peer.close(1001, "server done")
		c.peer.poll()
	if _log != null:
		_log.close()


func _note(kind: String, data: Dictionary) -> void:
	var line: String = "%d %s %s" % [_unix_us(), kind, JSON.stringify(data)]
	print(line)
	if _log != null:
		_log.store_line(line)
		_log.flush()


static func _unix_us() -> int:
	return int(Time.get_unix_time_from_system() * 1_000_000.0)


func _parse_args(args: PackedStringArray) -> void:
	var opts: Dictionary = {}
	for i: int in range(0, args.size() - 1, 2):
		opts[args[i].trim_prefix("--")] = args[i + 1]
	port = int(opts.get("port", port))
	ships = int(opts.get("ships", ships))
	contacts = int(opts.get("contacts", contacts))
	layout_floats = int(opts.get("layout-floats", layout_floats))
	tick_hz = int(opts.get("tick-hz", tick_hz))
	snapshot_hz = int(opts.get("snapshot-hz", snapshot_hz))
	run_for = float(opts.get("run-for", run_for))
	log_path = opts.get("log", log_path)
	lag_limit = int(opts.get("lag-limit", lag_limit))
	grace_s = float(opts.get("grace-s", grace_s))
	chunk_size = int(opts.get("chunk-size", chunk_size))
	voice_to = opts.get("voice-to", voice_to)
	voice_at = float(opts.get("voice-at", voice_at))
	voice_seconds = float(opts.get("voice-seconds", voice_seconds))
	voice_per_pump = int(opts.get("voice-per-pump", voice_per_pump))
	max_fps = int(opts.get("max-fps", max_fps))
	seed_value = int(opts.get("seed", seed_value))
