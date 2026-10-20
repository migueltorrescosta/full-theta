extends SceneTree
## S9 spike load client: several simulated stations in one headless process,
## each its own WebSocket connection. Connection i of the run takes seat
## S9Views.seat_for(first + i). Each logs every snapshot's age and size and
## acks it; the first `decode` connections also apply the snapshots to an
## S9ViewState, as a real station would.
##
## godot --headless --path . -s res://spikes/s9/s9_load_client.gd -- [flags]
## Flags: --url [ws://127.0.0.1:47830] --first [0] --conns [8] --ships [6]
## --decode [1] --log path --run-for s [120] --max-fps [60] --prefix [p]
## --ack-ms [200] (acks at most this often, and at once after a full snapshot)
##
## Log lines (CSV): s,conn,seq,full,sent_us,recv_us,bytes and
## x,conn,<kind>,recv_us,<json>. Age = recv_us - sent_us, both unix
## microseconds from Time.get_unix_time_from_system() on the same host.

const PROTO: int = 9


class Link:
	extends RefCounted
	var index: int = 0
	var name: String = ""
	var seat: Dictionary = {}
	var peer: WebSocketPeer = WebSocketPeer.new()
	var chunker: S4Chunker = S4Chunker.new()
	var state: S9ViewState
	var hello_sent: bool = false
	var was_open: bool = false
	var closed: bool = false
	var last_seq: int = -1
	var acked: int = -1
	var acked_us: int = 0
	var got_full: bool = false
	var msg_id: int = 1
	var snaps: int = 0
	var decode_failures: int = 0


var url: String = "ws://127.0.0.1:47830"
var first: int = 0
var conns: int = 8
var ships: int = 6
var decode: int = 1
var log_path: String = ""
var run_for: float = 120.0
var max_fps: int = 60
var prefix: String = "p"
var ack_us: int = 200_000

var _links: Array[Link] = []
var _log: FileAccess
var _start_ticks: int = 0


func _initialize() -> void:
	_parse_args(OS.get_cmdline_user_args())
	Engine.max_fps = max_fps
	_start_ticks = Time.get_ticks_usec()
	if log_path != "":
		_log = FileAccess.open(log_path, FileAccess.WRITE)
	for i: int in range(conns):
		var l: Link = Link.new()
		l.index = i
		l.seat = S9Views.seat_for(first + i, ships)
		l.name = "%s%02d" % [prefix, first + i]
		if i < decode:
			l.state = S9ViewState.new()
		var err: Error = l.peer.connect_to_url(url)
		if err != OK:
			push_error("connect failed: %s" % error_string(err))
		_links.append(l)


func _process(_delta: float) -> bool:
	var now_us: int = _unix_us()
	var open_or_pending: int = 0
	for l: Link in _links:
		if l.closed:
			continue
		l.peer.poll()
		var st: WebSocketPeer.State = l.peer.get_ready_state()
		if st == WebSocketPeer.STATE_CLOSED:
			l.closed = true
			_mark(l, "closed", {"code": l.peer.get_close_code(), "snaps": l.snaps})
			continue
		open_or_pending += 1
		if st != WebSocketPeer.STATE_OPEN:
			continue
		l.was_open = true
		if not l.hello_sent:
			var hello: Dictionary = {
				"t": "hello",
				"proto": PROTO,
				"name": l.name,
				"ship": l.seat["ship"],
				"entry": l.seat["entry"],
			}
			_send(l, var_to_bytes(hello))
			l.hello_sent = true
		while l.peer.get_available_packet_count() > 0:
			var msg: Dictionary = l.chunker.feed(l.peer.get_packet())
			if not msg.is_empty():
				_on_message(l, msg["data"], now_us)
		# Acks only feed the server's stall detector (15 snapshots, 500 ms), so
		# 5 a second is enough and saves a packet per snapshot each way.
		if l.last_seq != l.acked and (l.got_full or now_us - l.acked_us >= ack_us):
			_send(l, S9Views.ack(l.last_seq))
			l.acked = l.last_seq
			l.acked_us = now_us
			l.got_full = false
		l.peer.poll()
	var elapsed: float = (Time.get_ticks_usec() - _start_ticks) / 1_000_000.0
	if open_or_pending == 0 or elapsed >= run_for:
		_line(
			(
				"x,-1,cpu,%d,%s"
				% [_unix_us(), JSON.stringify({"cpu_s": _cpu_ticks() / 100.0, "wall_s": elapsed})]
			)
		)
		if _log != null:
			_log.close()
		return true
	return false


func _on_message(l: Link, data: PackedByteArray, now_us: int) -> void:
	if data[0] == S9Views.MSG_SNAPSHOT:
		var head: Array = S9Views.peek(data)
		l.last_seq = head[0]
		l.got_full = l.got_full or head[1]
		l.snaps += 1
		if l.state != null and not l.state.apply(data):
			l.decode_failures += 1
		_line(
			(
				"s,%d,%d,%d,%d,%d,%d"
				% [l.index, head[0], 1 if head[1] else 0, head[3], now_us, data.size()]
			)
		)
		return
	var m: Variant = bytes_to_var(data)
	if m is Dictionary:
		var d: Dictionary = m
		_mark(l, d.get("t", "?"), {"seat": l.seat, "name": l.name, "msg": d})


func _send(l: Link, payload: PackedByteArray) -> void:
	for chunk: PackedByteArray in S4Chunker.split(
		S4Chunker.STREAM_CONTROL, l.msg_id, payload, S4Chunker.DEFAULT_CHUNK_SIZE
	):
		l.peer.send(chunk)
	l.msg_id += 1


func _mark(l: Link, kind: String, data: Dictionary) -> void:
	if l.state != null:
		data["decode_failures"] = l.decode_failures
		data["out_of_order"] = l.state.out_of_order
	_line("x,%d,%s,%d,%s" % [l.index, kind, _unix_us(), JSON.stringify(data)])


func _line(text: String) -> void:
	if _log != null:
		_log.store_line(text)


## utime + stime of this process in clock ticks (100 per second on Linux).
static func _cpu_ticks() -> int:
	var f: FileAccess = FileAccess.open("/proc/self/stat", FileAccess.READ)
	if f == null:
		return 0
	var line: String = f.get_line()
	var fields: PackedStringArray = line.substr(line.rfind(")") + 2).split(" ")
	return int(fields[11]) + int(fields[12])


static func _unix_us() -> int:
	return int(Time.get_unix_time_from_system() * 1_000_000.0)


func _parse_args(args: PackedStringArray) -> void:
	var opts: Dictionary = {}
	for i: int in range(0, args.size() - 1, 2):
		opts[args[i].trim_prefix("--")] = args[i + 1]
	url = opts.get("url", url)
	first = int(opts.get("first", first))
	conns = int(opts.get("conns", conns))
	ships = int(opts.get("ships", ships))
	decode = int(opts.get("decode", decode))
	log_path = opts.get("log", log_path)
	run_for = float(opts.get("run-for", run_for))
	max_fps = int(opts.get("max-fps", max_fps))
	prefix = opts.get("prefix", prefix)
	ack_us = int(opts.get("ack-ms", ack_us / 1000)) * 1000
