extends SceneTree
## S4 spike headless client: joins, applies full and delta snapshots, delivers
## events in order, acks both, and logs per-snapshot age.
##
## godot --headless --path . -s res://spikes/s4/s4_client.gd -- [flags]
## Flags: --url [ws://127.0.0.1:47810] --name [c0] --token-file path [none]
## --log path [none] --run-for s [70] --stall-at s [-1] --stall-for s [2]
## --launched-us unix_us [0] --max-fps [60]
##
## Log lines (CSV): s,seq,full,sent_us,recv_us,bytes  e,seq,recv_us,via
## k,stream,msg,index,count,recv_us (chunks of multi-chunk messages)
## x,<kind>,recv_us,<json>  (milestones and the final summary)
## Age = recv_us - sent_us, both from Time.get_unix_time_from_system() on the
## same host: get_ticks_usec() starts at each process's launch, so it has no
## common base across processes.

const PROTO: int = 1

var url: String = "ws://127.0.0.1:47810"
var client_name: String = "c0"
var token_file: String = ""
var log_path: String = ""
var run_for: float = 70.0
var stall_at: float = -1.0
var stall_for: float = 2.0
var launched_us: int = 0
var max_fps: int = 60

var _peer: WebSocketPeer = WebSocketPeer.new()
var _chunker: S4Chunker = S4Chunker.new()
var _msg_id: int = 1
var _state: Dictionary = {}
var _history: Dictionary = {}
var _last_seq: int = -1
var _inbox: S4EventInbox = S4EventInbox.new()
var _token: String = ""
var _stored_seat: Dictionary = {}
var _seat: Dictionary = {}
var _resumed: bool = false
var _sent_hello: bool = false
var _was_open: bool = false
var _acked: Vector2i = Vector2i(-2, -2)
var _stall_phase: int = 0
var _stall_resume_us: int = 0
var _await_full_after_stall: bool = false
var _await_first_full: bool = true
var _voice_partial: bool = false
var _log: FileAccess
var _start_ticks: int = 0
var _next_flush_s: float = 1.0
var _counts: Dictionary = {"snaps": 0, "fulls": 0, "deltas": 0, "events": 0, "missing_base": 0}


func _initialize() -> void:
	_parse_args(OS.get_cmdline_user_args())
	Engine.max_fps = max_fps
	_start_ticks = Time.get_ticks_usec()
	if log_path != "":
		_log = FileAccess.open(log_path, FileAccess.WRITE)
	if token_file != "" and FileAccess.file_exists(token_file):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(token_file))
		if saved is Dictionary:
			_token = (saved as Dictionary).get("token", "")
			_stored_seat = (saved as Dictionary).get("seat", {})
	_milestone("start", {"launched_us": launched_us, "token": _token != ""})
	var err: Error = _peer.connect_to_url(url)
	if err != OK:
		push_error("connect failed: %s" % error_string(err))
		quit(1)


func _process(_delta: float) -> bool:
	var elapsed: float = (Time.get_ticks_usec() - _start_ticks) / 1_000_000.0
	if stall_at >= 0.0 and _stall_phase == 0 and elapsed >= stall_at:
		_stall_phase = 1
		_milestone("stall_start", {})
	if _stall_phase == 1:
		if elapsed < stall_at + stall_for:
			return false
		_stall_phase = 2
		_stall_resume_us = _unix_us()
		_await_full_after_stall = true
		_milestone("stall_end", {})
	_peer.poll()
	var state: WebSocketPeer.State = _peer.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		_was_open = true
		if not _sent_hello:
			_send({"t": "hello", "proto": PROTO, "name": client_name, "token": _token})
			_sent_hello = true
		while _peer.get_available_packet_count() > 0:
			_on_chunk(_peer.get_packet(), _unix_us())
		var ack: Vector2i = Vector2i(_last_seq, _inbox.last_seq)
		if ack != _acked and _last_seq >= 0:
			# Flush first, so a log survives SIGKILL with everything acked.
			if _log != null:
				_log.flush()
			_send({"t": "ack", "snap": ack.x, "ev": ack.y})
			_acked = ack
		_peer.poll()
	if elapsed >= _next_flush_s and _log != null:
		_log.flush()
		_next_flush_s += 1.0
	var closed: bool = state == WebSocketPeer.STATE_CLOSED and (_was_open or elapsed > 5.0)
	if closed or elapsed >= run_for:
		_finish(closed)
		return true
	return false


func _on_chunk(chunk: PackedByteArray, now_us: int) -> void:
	var count: int = S4Chunker.count_of(chunk)
	if count > 1 or _voice_partial:
		_line(
			(
				"k,%d,%d,%d,%d,%d"
				% [
					S4Chunker.stream_of(chunk),
					S4Chunker.msg_id_of(chunk),
					S4Chunker.index_of(chunk),
					count,
					now_us
				]
			)
		)
	if S4Chunker.stream_of(chunk) == S4Chunker.STREAM_VOICE:
		_voice_partial = S4Chunker.index_of(chunk) + 1 < count
	var msg: Dictionary = _chunker.feed(chunk)
	if msg.is_empty():
		return
	var data: PackedByteArray = msg["data"]
	var m: Dictionary = bytes_to_var(data)
	match m.get("t", ""):
		"welcome":
			_on_welcome(m)
		"snap":
			_on_snap(m, data.size(), now_us)
		"ev":
			_deliver(m, now_us, "ev")
		"voice":
			_on_voice(m, data.size())
		"reject":
			_milestone("rejected", {"reason": m["reason"]})


func _on_welcome(m: Dictionary) -> void:
	_token = m["token"]
	_seat = m["seat"]
	_resumed = m["resumed"]
	_inbox = S4EventInbox.new(m["ev_from"])
	if token_file != "":
		var f: FileAccess = FileAccess.open(token_file, FileAccess.WRITE)
		f.store_string(JSON.stringify({"token": _token, "seat": _seat}))
		f.close()
	var restored: bool = (
		_resumed
		and int(_stored_seat.get("ship", -1)) == int(_seat["ship"])
		and _stored_seat.get("station", "") == _seat["station"]
	)
	_milestone(
		"welcome",
		{"resumed": _resumed, "seat": _seat, "seat_restored": restored, "ev_from": m["ev_from"]}
	)


func _on_snap(m: Dictionary, size: int, now_us: int) -> void:
	var seq: int = m["seq"]
	var base: int = m["base"]
	var full: bool = base == -1
	if full:
		_state = m["ents"]
		_history = {seq: _state}
		_counts["fulls"] += 1
		var events: Array = m["events"]
		for e: Dictionary in events:
			_deliver(e, now_us, "full")
		if _await_full_after_stall:
			_await_full_after_stall = false
			_milestone(
				"stall_recovered",
				{"after_resume_us": now_us - _stall_resume_us, "seq": seq, "events": events.size()}
			)
		if _await_first_full:
			_await_first_full = false
			_milestone(
				"first_full",
				{
					"resumed": _resumed,
					"since_launch_us": now_us - launched_us if launched_us > 0 else -1,
					"bytes": size,
					"entities": _state.size(),
				}
			)
	else:
		if not _history.has(base):
			_counts["missing_base"] += 1
			return
		_state = S4Snapshot.apply(_history[base], m)
		_history[seq] = _state
		for old: int in _history.keys():
			if old < base:
				_history.erase(old)
		_counts["deltas"] += 1
	_counts["snaps"] += 1
	_last_seq = seq
	_line("s,%d,%d,%d,%d,%d" % [seq, 1 if full else 0, m["sent_us"], now_us, size])


func _deliver(event: Dictionary, now_us: int, via: String) -> void:
	for e: Dictionary in _inbox.receive(event):
		_counts["events"] += 1
		_line("e,%d,%d,%s" % [e["seq"], now_us, via])


func _on_voice(m: Dictionary, size: int) -> void:
	var pcm: PackedByteArray = m["pcm"]
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(pcm)
	var ok: bool = ctx.finish().hex_encode() == m["sha"]
	_milestone("voice", {"ok": ok, "bytes": size, "pcm_bytes": pcm.size()})


func _send(m: Dictionary) -> void:
	for chunk: PackedByteArray in S4Chunker.split(
		S4Chunker.STREAM_CONTROL, _msg_id, var_to_bytes(m), S4Chunker.DEFAULT_CHUNK_SIZE
	):
		_peer.send(chunk)
	_msg_id += 1


func _finish(closed: bool) -> void:
	_counts["closed_by_server"] = closed
	_counts["last_event"] = _inbox.last_seq
	_counts["event_duplicates"] = _inbox.duplicates
	_counts["events_waiting"] = _inbox.waiting()
	_counts["chunk_errors"] = _chunker.errors
	_milestone("summary", _counts)
	if _log != null:
		_log.close()


func _milestone(kind: String, data: Dictionary) -> void:
	_line("x,%s,%d,%s" % [kind, _unix_us(), JSON.stringify(data)])


func _line(text: String) -> void:
	if _log != null:
		_log.store_line(text)


static func _unix_us() -> int:
	return int(Time.get_unix_time_from_system() * 1_000_000.0)


func _parse_args(args: PackedStringArray) -> void:
	var opts: Dictionary = {}
	for i: int in range(0, args.size() - 1, 2):
		opts[args[i].trim_prefix("--")] = args[i + 1]
	url = opts.get("url", url)
	client_name = opts.get("name", client_name)
	token_file = opts.get("token-file", token_file)
	log_path = opts.get("log", log_path)
	run_for = float(opts.get("run-for", run_for))
	stall_at = float(opts.get("stall-at", stall_at))
	stall_for = float(opts.get("stall-for", stall_for))
	launched_us = int(opts.get("launched-us", launched_us))
	max_fps = int(opts.get("max-fps", max_fps))
