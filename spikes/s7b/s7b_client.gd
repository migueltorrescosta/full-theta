extends SceneTree
## S7b spike headless client: the S4 client's join, snapshot and event path,
## plus voice clips. A headless client has no audio output, so "audible" is
## the moment the whole clip is wrapped in an AudioStreamWAV, ready for an
## AudioStreamPlayer (FT-AUD-015's end point, minus the output device's own
## buffer).
##
## godot --headless --path . -s res://spikes/s7b/s7b_client.gd -- [flags]
## Flags: --url [ws://127.0.0.1:47840] --name [c0] --log path [none]
## --run-for s [400] --max-fps [60] --dump DIR [none] (saves each part as a
## WAV after its hand-off time is taken, for listening) --render [0] (1: run
## as a rendering client, not --headless: a lit spinning mesh in a 3D scene,
## and each clip part is played on an AudioStreamPlayer; frame times logged)
##
## Log lines: v,<json> per voice clip (server timings plus first_chunk_us,
## complete_us, handoff_us); x,<kind>,unix_us,<json> for milestones and the
## summary. Times are Time.get_unix_time_from_system() in µs (same host).

const PROTO: int = 1

var url: String = "ws://127.0.0.1:47840"
var client_name: String = "c0"
var log_path: String = ""
var run_for: float = 400.0
var max_fps: int = 60
var dump_dir: String = ""
var render: bool = false

var _peer: WebSocketPeer = WebSocketPeer.new()
var _chunker: S4Chunker = S4Chunker.new()
var _msg_id: int = 1
var _history: Dictionary = {}
var _last_seq: int = -1
var _inbox: S4EventInbox = S4EventInbox.new()
var _sent_hello: bool = false
var _was_open: bool = false
var _acked: Vector2i = Vector2i(-2, -2)
var _voice_first: Dictionary = {}
var _log: FileAccess
var _start_ticks: int = 0
var _counts: Dictionary = {"snaps": 0, "events": 0, "voice": 0, "voice_bytes": 0}
var _mesh: MeshInstance3D
var _player: AudioStreamPlayer
var _frame_us: PackedInt32Array = PackedInt32Array()
var _last_frame: int = 0


func _initialize() -> void:
	_parse_args(OS.get_cmdline_user_args())
	Engine.max_fps = max_fps
	_start_ticks = Time.get_ticks_usec()
	if log_path != "":
		_log = FileAccess.open(log_path, FileAccess.WRITE)
	if render:
		_build_scene()
	if _peer.connect_to_url(url) != OK:
		push_error("connect failed")
		quit(1)


func _process(_delta: float) -> bool:
	var elapsed: float = (Time.get_ticks_usec() - _start_ticks) / 1_000_000.0
	if render:
		var now: int = Time.get_ticks_usec()
		if _last_frame > 0:
			_frame_us.append(now - _last_frame)
		_last_frame = now
		_mesh.rotate_y(_delta)
		_mesh.rotate_x(_delta * 0.3)
	_peer.poll()
	var state: WebSocketPeer.State = _peer.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		_was_open = true
		if not _sent_hello:
			_send({"t": "hello", "proto": PROTO, "name": client_name, "token": ""})
			_sent_hello = true
		while _peer.get_available_packet_count() > 0:
			_on_chunk(_peer.get_packet())
		var ack: Vector2i = Vector2i(_last_seq, _inbox.last_seq)
		if ack != _acked and _last_seq >= 0:
			_send({"t": "ack", "snap": ack.x, "ev": ack.y})
			_acked = ack
		_peer.poll()
	var closed: bool = state == WebSocketPeer.STATE_CLOSED and (_was_open or elapsed > 30.0)
	if closed or elapsed >= run_for:
		if render:
			_counts["frame_us"] = _frame_stats()
		_milestone("summary", _counts)
		if _log != null:
			_log.close()
		return true
	return false


func _on_chunk(chunk: PackedByteArray) -> void:
	var now_us: int = _unix_us()
	if S4Chunker.stream_of(chunk) == S4Chunker.STREAM_VOICE and S4Chunker.index_of(chunk) == 0:
		_voice_first[S4Chunker.msg_id_of(chunk)] = now_us
	var msg: Dictionary = _chunker.feed(chunk)
	if msg.is_empty():
		return
	var m: Dictionary = bytes_to_var(msg["data"])
	match m.get("t", ""):
		"welcome":
			_inbox = S4EventInbox.new(m["ev_from"])
			_milestone("welcome", {})
		"snap":
			_on_snap(m)
		"ev":
			_counts["events"] += _inbox.receive(m).size()
		"voice":
			_on_voice(m, msg["msg_id"], now_us, (msg["data"] as PackedByteArray).size())


func _on_snap(m: Dictionary) -> void:
	var seq: int = m["seq"]
	var base: int = m["base"]
	if base == -1:
		_history = {seq: m["ents"]}
		for e: Dictionary in m["events"]:
			_counts["events"] += _inbox.receive(e).size()
	else:
		if not _history.has(base):
			return
		_history[seq] = S4Snapshot.apply(_history[base], m)
		for old: int in _history.keys():
			if old < base:
				_history.erase(old)
	_counts["snaps"] += 1
	_last_seq = seq


## Hands the clip to the audio layer: an AudioStreamWAV an AudioStreamPlayer
## (or an AudioStreamGenerator feeder) could start at once.
func _on_voice(m: Dictionary, msg_id: int, complete_us: int, size: int) -> void:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = m["rate"]
	wav.stereo = false
	wav.data = m["pcm"]
	if render and not wav.data.is_empty():
		# One player, parts queued back to back would need a playlist; the
		# spike plays each part on arrival, which is what the latency measures.
		_player.stream = wav
		_player.play()
	var handoff_us: int = _unix_us()
	m.erase("pcm")
	m.erase("t")
	m["first_chunk_us"] = _voice_first.get(msg_id, complete_us)
	m["complete_us"] = complete_us
	m["handoff_us"] = handoff_us
	m["bytes"] = size
	m["length_s"] = wav.get_length()
	_voice_first.erase(msg_id)
	_counts["voice"] += 1
	_counts["voice_bytes"] += size
	_line("v," + JSON.stringify(m))
	if dump_dir != "" and not wav.data.is_empty():
		wav.save_to_wav(dump_dir.path_join("%s-%d.wav" % [m["line"], m["part"]]))


func _build_scene() -> void:
	var world: Node3D = Node3D.new()
	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0, 0, 4)
	world.add_child(camera)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation = Vector3(-0.8, 0.5, 0)
	light.shadow_enabled = true
	world.add_child(light)
	_mesh = MeshInstance3D.new()
	var torus: TorusMesh = TorusMesh.new()
	torus.rings = 96
	torus.ring_segments = 48
	_mesh.mesh = torus
	world.add_child(_mesh)
	_player = AudioStreamPlayer.new()
	world.add_child(_player)
	root.add_child(world)


func _frame_stats() -> Dictionary:
	if _frame_us.is_empty():
		return {}
	var sorted: PackedInt32Array = _frame_us.duplicate()
	sorted.sort()
	var n: int = sorted.size()
	return {"n": n, "p50": sorted[n / 2], "p99": sorted[n * 99 / 100], "max": sorted[n - 1]}


func _send(m: Dictionary) -> void:
	for chunk: PackedByteArray in S4Chunker.split(
		S4Chunker.STREAM_CONTROL, _msg_id, var_to_bytes(m), S4Chunker.DEFAULT_CHUNK_SIZE
	):
		_peer.send(chunk)
	_msg_id += 1


func _milestone(kind: String, data: Dictionary) -> void:
	_line("x,%s,%d,%s" % [kind, _unix_us(), JSON.stringify(data)])


func _line(text: String) -> void:
	if _log != null:
		_log.store_line(text)
		_log.flush()


static func _unix_us() -> int:
	return int(Time.get_unix_time_from_system() * 1_000_000.0)


func _parse_args(args: PackedStringArray) -> void:
	var opts: Dictionary = {}
	for i: int in range(0, args.size() - 1, 2):
		opts[args[i].trim_prefix("--")] = args[i + 1]
	url = opts.get("url", url)
	client_name = opts.get("name", client_name)
	log_path = opts.get("log", log_path)
	run_for = float(opts.get("run-for", run_for))
	max_fps = int(opts.get("max-fps", max_fps))
	dump_dir = opts.get("dump", dump_dir)
	render = opts.get("render", "0") == "1"
