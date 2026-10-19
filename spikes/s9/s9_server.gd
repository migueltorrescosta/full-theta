extends SceneTree
## S9 spike server (T023, TECH-9): the S6 load (100 ships, 500 projectiles) at
## 60 Hz and per-view snapshots at 30 Hz to up to 64 WebSocket clients, in one
## thread. Transport from S4 (chunks, two-lane send queue, ack-based resync);
## codec and view keys from S9Builder.
##
## godot --headless --path . -s res://spikes/s9/s9_server.gd -- [flags]
## Flags (defaults in brackets): --port [47830] --expect clients [64]
## --run-for measured s [60] --warmup s [3] --join-timeout s [30] --log path
## --ships player ships [6] --world-ships [100] --projectiles [500]
## --factions [1] --toggles [normal] --pos-tol m [0.5] --rot-tol deg [1]
## --near-range m [2000] --proj-range m [1000] --tick-hz [60]
## --snapshot-hz [30] --lag-limit [15] --max-fps [120] --seed [1]
##
## Clients send a hello (var_to_bytes {"t": "hello", "proto", "name", "ship",
## "entry"}) and then acks (S9Views.ack). Any client may join, so an extra
## rendering client can share the run (TECH-5). The measured window starts
## `warmup` s after `expect` clients have joined (or the join timeout) and
## lasts `run-for` s; the server then logs a summary and quits.

const PROTO: int = 9


class Conn:
	extends RefCounted
	var peer: WebSocketPeer
	var id: int = 0
	var name: String = ""
	var ship: int = 0
	var entry: String = ""
	var joined: bool = false
	var queue: S9SendQueue = S9SendQueue.new()
	var resync: S4Resync
	var chunker: S4Chunker = S4Chunker.new()
	var bytes_out: int = 0
	var bytes_at_start: int = 0
	var msgs: int = 0
	var fulls: int = 0
	var skipped: int = 0
	var blocked_pumps: int = 0


var port: int = 47830
var expect: int = 64
var run_for: float = 60.0
var warmup: float = 3.0
var join_timeout: float = 30.0
var log_path: String = ""
var ships: int = 6
var world_ships: int = 100
var projectiles: int = 500
var factions: int = 1
var toggles: String = "normal"
var pos_tol: float = 0.5
var rot_tol: float = 1.0
var near_range: float = 2000.0
var proj_range: float = 1000.0
var tick_hz: int = 60
var snapshot_hz: int = 30
var lag_limit: int = 15
var max_fps: int = 120
var seed_value: int = 1

var _tcp: TCPServer = TCPServer.new()
var _conns: Array[Conn] = []
var _world: S9World
var _builder: S9Builder
var _log: FileAccess
var _next_conn_id: int = 1
var _snap_seq: int = 0
var _start_ticks: int = 0
var _tick_us: int = 0
var _next_tick_ticks: int = 0
## Phase: 0 waiting for joins, 1 warm-up, 2 measuring.
var _phase: int = 0
var _phase_at: int = 0
var _measure_start_us: int = 0
var _cpu_start: int = 0
var _net_start: PackedInt64Array = PackedInt64Array()
var _stat_next: int = 0
## Per tick frame (a frame that ran a sim tick): total work and its parts, us.
var _f_work: PackedInt32Array = PackedInt32Array()
var _f_sim: PackedInt32Array = PackedInt32Array()
var _f_snap: PackedInt32Array = PackedInt32Array()
var _f_pump: PackedInt32Array = PackedInt32Array()
var _f_poll: PackedInt32Array = PackedInt32Array()
var _f_is_snapshot: PackedByteArray = PackedByteArray()
## On-CPU and run-queue wait time of the main thread per tick frame, us
## (/proc/thread-self/schedstat): wall time minus preemption by other work.
var _f_oncpu: PackedInt32Array = PackedInt32Array()
var _f_wait: PackedInt32Array = PackedInt32Array()
var _other_frames: int = 0
var _sends: int = 0
## Snapshot chunks of the current snapshot by view key and full flag.
var _chunks: Dictionary = {}


func _initialize() -> void:
	_parse_args(OS.get_cmdline_user_args())
	Engine.max_fps = max_fps
	if log_path != "":
		_log = FileAccess.open(log_path, FileAccess.WRITE)
	_world = S9World.new(seed_value)
	_world.setup_benchmark(world_ships, projectiles)
	_builder = (
		S9Builder
		. new(
			_world,
			{
				"ships": ships,
				"factions": factions,
				"pos_tol": pos_tol,
				"rot_tol_deg": rot_tol,
				"near_range": near_range,
				"proj_range": proj_range,
			}
		)
	)
	var err: Error = _tcp.listen(port, "127.0.0.1")
	if err != OK:
		push_error("listen failed on %d: %s" % [port, error_string(err)])
		quit(1)
		return
	_start_ticks = Time.get_ticks_usec()
	_phase_at = _start_ticks
	_tick_us = int(1_000_000 / float(tick_hz))
	_next_tick_ticks = _start_ticks + _tick_us
	_note("listening", {"port": port, "expect": expect, "pid": OS.get_process_id()})


func _process(_delta: float) -> bool:
	var t0: int = Time.get_ticks_usec()
	var sched0: PackedInt64Array = PackedInt64Array()
	if _phase == 2 and t0 >= _next_tick_ticks:
		sched0 = _sched()
	_accept()
	_poll_all()
	var t1: int = Time.get_ticks_usec()
	var sim_us: int = 0
	var snap_us: int = 0
	var ticks: int = 0
	var snapshot_frame: bool = false
	while t0 >= _next_tick_ticks and ticks < 4:
		var s0: int = Time.get_ticks_usec()
		_world.step()
		_builder.note_tick_events()
		var s1: int = Time.get_ticks_usec()
		sim_us += s1 - s0
		if _world.tick % int(tick_hz / float(snapshot_hz)) == 0:
			_snapshot()
			snap_us += Time.get_ticks_usec() - s1
			snapshot_frame = true
		_next_tick_ticks += _tick_us
		ticks += 1
	if t0 >= _next_tick_ticks:
		_next_tick_ticks = t0 + _tick_us
	var t2: int = Time.get_ticks_usec()
	_pump_all()
	var t3: int = Time.get_ticks_usec()
	if _phase == 2:
		if ticks > 0:
			_f_work.append(t3 - t0)
			_f_sim.append(sim_us)
			_f_snap.append(snap_us)
			_f_pump.append(t3 - t2)
			_f_poll.append(t1 - t0)
			_f_is_snapshot.append(1 if snapshot_frame else 0)
			var sched1: PackedInt64Array = _sched()
			if sched0.size() == 2 and sched1.size() == 2:
				_f_oncpu.append((sched1[0] - sched0[0]) / 1000)
				_f_wait.append((sched1[1] - sched0[1]) / 1000)
		else:
			_other_frames += 1
	return _advance_phase(t3)


func _advance_phase(now: int) -> bool:
	var since: float = (now - _phase_at) / 1_000_000.0
	if _phase == 0:
		var joined: int = 0
		for c: Conn in _conns:
			if c.joined:
				joined += 1
		if joined >= expect or since >= join_timeout:
			_note("all_joined", {"joined": joined})
			_phase = 1
			_phase_at = now
	elif _phase == 1 and since >= warmup:
		_phase = 2
		_phase_at = now
		_stat_next = 1
		_measure_start_us = _unix_us()
		_cpu_start = _cpu_ticks()
		_net_start = _lo_bytes()
		for c: Conn in _conns:
			c.bytes_at_start = c.bytes_out
		_builder.take_counts()
		_sends = 0
		_note("measure_start", {"clients": _conns.size()})
	elif _phase == 2:
		if since >= _stat_next:
			_stats()
			_stat_next += 1
		if since >= run_for:
			_finish(now)
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
		_conns.append(c)


func _poll_all() -> void:
	var closed: Array[Conn] = []
	for c: Conn in _conns:
		c.peer.poll()
		if c.peer.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			closed.append(c)
			continue
		while c.peer.get_available_packet_count() > 0:
			var msg: Dictionary = c.chunker.feed(c.peer.get_packet())
			if msg.is_empty():
				continue
			var data: PackedByteArray = msg["data"]
			if c.joined and data[0] == S9Views.MSG_ACK:
				c.resync.on_ack(data.decode_u32(1))
			elif not c.joined:
				_on_hello(c, bytes_to_var(data))
	for c: Conn in closed:
		_conns.erase(c)
		_note("drop", {"client": c.name, "conn": c.id, "code": c.peer.get_close_code()})


func _on_hello(c: Conn, m: Variant) -> void:
	var hello: Dictionary = m if m is Dictionary else {}
	c.name = hello.get("name", "")
	var entry: String = hello.get("entry", "")
	var ship: int = int(hello.get("ship", -1))
	if (
		int(hello.get("proto", 0)) != PROTO
		or not S9Views.SECTIONS.has(entry)
		or ship < 0
		or ship >= ships
	):
		var reason: String = "bad hello"
		c.queue.push(S4Chunker.STREAM_CONTROL, var_to_bytes({"t": "reject", "reason": reason}))
		c.peer.close(4000, reason)
		return
	c.ship = ship
	c.entry = entry
	c.joined = true
	c.resync = S4Resync.new(lag_limit)
	var key: String = S9Views.key(ship, entry, toggles)
	c.queue.push(
		S4Chunker.STREAM_CONTROL, var_to_bytes({"t": "welcome", "client": c.id, "key": key})
	)
	_note("join", {"client": c.name, "conn": c.id, "key": key})


func _snapshot() -> void:
	_snap_seq += 1
	_builder.build(_snap_seq, _unix_us())
	_chunks.clear()
	for c: Conn in _conns:
		if not c.joined:
			continue
		var buffered: int = c.peer.get_current_outbound_buffered_amount()
		var action: S4Resync.Action = c.resync.decide(c.queue.high_bytes)
		if action == S4Resync.Action.NONE:
			c.skipped += 1
			continue
		var is_full: bool = action == S4Resync.Action.FULL
		var k: String = "%d|%s|%d" % [c.ship, c.entry, 1 if is_full else 0]
		var chunks: Array[PackedByteArray] = []
		if _chunks.has(k):
			chunks = _chunks[k]
		else:
			var bytes: PackedByteArray = _builder.message(c.ship, c.entry, toggles, is_full)
			chunks = S4Chunker.split(
				S4Chunker.STREAM_SNAPSHOT, _snap_seq, bytes, S4Chunker.DEFAULT_CHUNK_SIZE
			)
			_chunks[k] = chunks
		if chunks.size() == 1:
			c.queue.push_chunk(chunks[0])
		else:
			c.queue.push(
				S4Chunker.STREAM_SNAPSHOT, _builder.message(c.ship, c.entry, toggles, is_full)
			)
		c.resync.on_sent(_snap_seq, is_full)
		c.msgs += 1
		_sends += 1
		if is_full:
			c.fulls += 1


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
			if c.peer.get_current_outbound_buffered_amount() + size > limit:
				c.blocked_pumps += 1
				break
			var chunk: PackedByteArray = c.queue.next_chunk()
			if c.peer.send(chunk) != OK:
				if c.resync != null:
					c.resync.on_send_error()
				break
			c.bytes_out += chunk.size()
		c.peer.poll()


func _stats() -> void:
	var bytes: int = 0
	for c: Conn in _conns:
		bytes += c.bytes_out - c.bytes_at_start
	var last: PackedInt32Array = _f_work.slice(maxi(0, _f_work.size() - tick_hz))
	var top: int = 0
	for w: int in last:
		top = maxi(top, w)
	_note(
		"stats",
		{"clients": _conns.size(), "bytes": bytes, "tick_frames": last.size(), "work_max_us": top}
	)


func _finish(now: int) -> void:
	var secs: float = (now - _phase_at) / 1_000_000.0
	var cpu: int = _cpu_ticks() - _cpu_start
	var net: PackedInt64Array = _lo_bytes()
	var counts: Dictionary = _builder.take_counts()
	var clients: Array = []
	var total: int = 0
	for c: Conn in _conns:
		var b: int = c.bytes_out - c.bytes_at_start
		total += b
		(
			clients
			. append(
				{
					"name": c.name,
					"ship": c.ship,
					"entry": c.entry,
					"bytes": b,
					"msgs": c.msgs,
					"fulls": c.fulls,
					"skipped": c.skipped,
					"stalls": c.resync.stall_count if c.resync != null else 0,
					"blocked_pumps": c.blocked_pumps,
				}
			)
		)
	var snapshot_frames: PackedInt32Array = PackedInt32Array()
	for i: int in range(_f_work.size()):
		if _f_is_snapshot[i] == 1:
			snapshot_frames.append(_f_work[i])
	var builds: int = maxi(1, counts["builds"])
	var summary: Dictionary = {
		"seconds": secs,
		"measure_start_us": _measure_start_us,
		"clients": _conns.size(),
		"tick_frames": _dist(_f_work),
		"tick_frames_oncpu": _dist(_f_oncpu),
		"tick_frames_wait": _dist(_f_wait),
		"snapshot_frames": _dist(snapshot_frames),
		"sim_mean_us": _mean(_f_sim),
		"snap_mean_us": _mean(_f_snap),
		"pump_mean_us": _mean(_f_pump),
		"poll_mean_us": _mean(_f_poll),
		"other_frames": _other_frames,
		"cpu_s": cpu / 100.0,
		"cpu_pct_of_2_cores": 100.0 * cpu / 100.0 / secs / 2.0,
		"payload_bytes": total,
		"payload_mbit_s": total * 8.0 / secs / 1.0e6,
		"lo_bytes": net[0] - _net_start[0] if net.size() > 0 and _net_start.size() > 0 else -1,
		"lo_packets": net[1] - _net_start[1] if net.size() > 0 and _net_start.size() > 0 else -1,
		"snapshots": builds,
		"sends_per_snapshot": _sends / float(builds),
		"section_encodes_per_snapshot": counts["section_encodes"] / float(builds),
		"delta_messages_per_snapshot": counts["delta_messages"] / float(builds),
		"full_messages": counts["full_messages"],
		"build_us_per_snapshot":
		{
			"filter": counts["us_filter"] / float(builds),
			"radar": counts["us_radar"] / float(builds),
			"near": counts["us_near"] / float(builds),
			"own_proj": counts["us_own_proj"] / float(builds),
			"messages": counts["us_messages"] / float(builds),
		},
		"per_client": clients,
	}
	_note("summary", summary)
	for c: Conn in _conns:
		c.peer.close(1001, "server done")
		c.peer.poll()
	if _log != null:
		_log.close()


static func _dist(values: PackedInt32Array) -> Dictionary:
	if values.is_empty():
		return {}
	var s: PackedInt32Array = values.duplicate()
	s.sort()
	var n: int = s.size()
	return {
		"n": n,
		"mean_us": _mean(values),
		"p50_us": s[n / 2],
		"p99_us": s[mini(n - 1, int(n * 0.99))],
		"max_us": s[n - 1],
	}


static func _mean(values: PackedInt32Array) -> float:
	var sum: int = 0
	for v: int in values:
		sum += v
	return sum / float(maxi(1, values.size()))


## utime + stime of this process in clock ticks (100 per second on Linux).
static func _cpu_ticks() -> int:
	var f: FileAccess = FileAccess.open("/proc/self/stat", FileAccess.READ)
	if f == null:
		return 0
	var line: String = f.get_line()
	var fields: PackedStringArray = line.substr(line.rfind(")") + 2).split(" ")
	return int(fields[11]) + int(fields[12])


## Main thread's [ns on CPU, ns waiting on a run queue].
static func _sched() -> PackedInt64Array:
	var f: FileAccess = FileAccess.open("/proc/thread-self/schedstat", FileAccess.READ)
	if f == null:
		return PackedInt64Array()
	var cols: PackedStringArray = f.get_line().split(" ")
	return PackedInt64Array([int(cols[0]), int(cols[1])])


## Bytes and packets through `lo` in this network namespace (tx side).
static func _lo_bytes() -> PackedInt64Array:
	var f: FileAccess = FileAccess.open("/proc/net/dev", FileAccess.READ)
	if f == null:
		return PackedInt64Array()
	while not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if line.begins_with("lo:"):
			var cols: PackedStringArray = line.substr(3).split(" ", false)
			return PackedInt64Array([int(cols[8]), int(cols[9])])
	return PackedInt64Array()


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
	expect = int(opts.get("expect", expect))
	run_for = float(opts.get("run-for", run_for))
	warmup = float(opts.get("warmup", warmup))
	join_timeout = float(opts.get("join-timeout", join_timeout))
	log_path = opts.get("log", log_path)
	ships = int(opts.get("ships", ships))
	world_ships = int(opts.get("world-ships", world_ships))
	projectiles = int(opts.get("projectiles", projectiles))
	factions = int(opts.get("factions", factions))
	toggles = opts.get("toggles", toggles)
	pos_tol = float(opts.get("pos-tol", pos_tol))
	rot_tol = float(opts.get("rot-tol", rot_tol))
	near_range = float(opts.get("near-range", near_range))
	proj_range = float(opts.get("proj-range", proj_range))
	tick_hz = int(opts.get("tick-hz", tick_hz))
	snapshot_hz = int(opts.get("snapshot-hz", snapshot_hz))
	lag_limit = int(opts.get("lag-limit", lag_limit))
	max_fps = int(opts.get("max-fps", max_fps))
	seed_value = int(opts.get("seed", seed_value))
