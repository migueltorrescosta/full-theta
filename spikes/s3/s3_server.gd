extends "res://spikes/s4/s4_server.gd"
## S3 spike server (T021, TECH-3): the S4 WebSocket server plus a static HTTP
## server for the web export in the same process and thread (FT-NET-030), an
## Engineering model per ship, a voice clip on request (FT-AUD-017), and an
## S6 sim load each tick. Logs each tick's lateness and how much of it HTTP
## work caused (FT-NET-039).
##
## godot --headless --path . -s res://spikes/s3/s3_server.gd -- [flags]
## S3 flags (defaults in brackets): --http-port [47820] --bind [127.0.0.1]
## --http-root [build/s3] --http-budget-us [400] --http-slice [65536]
## --http-log 0|1 [0] --tick-log path [none] --load-ships [30] --load-proj [150]
## --clip-seconds [1.2]
## S4 flags apply too; S3 changes the defaults of --port [47821],
## --run-for [600] and --max-fps [1000].
## Client messages added to S4's: {"t": "cmd", "sys": i, "pips": n} and
## {"t": "voice_req"}.

var http_port: int = 47820
var bind: String = "127.0.0.1"
var http_root: String = ""
var http_budget_us: int = 400
var http_slice: int = 65536
var tick_log_path: String = ""
var http_log: bool = false
var load_ships: int = 30
var load_proj: int = 150
var clip_seconds: float = 1.2

var _http: S3StaticServer
var _load: S6WorldPacked
var _clip: PackedByteArray
var _tick_log: FileAccess
## Recent HTTP poll intervals, flat [start, end, start, end, ...] in ticks_usec.
var _http_spans: PackedInt64Array = PackedInt64Array()
var _http_max_us: int = 0
var _http_bytes_mark: int = 0


func _initialize() -> void:
	port = 47821
	run_for = 600.0
	max_fps = 1000
	_parse_s3_args(OS.get_cmdline_user_args())
	super._initialize()
	# A headless process can't draw, so Godot sleeps the low-processor delay
	# (6.9 ms) every frame whatever max_fps says: about 145 frames/s, which
	# also held for S4. Shorten it so max_fps sets the pace.
	OS.low_processor_usage_mode_sleep_usec = maxi(1, 500_000 / maxi(1, max_fps))
	_sim = S3StationSim.new(ships, contacts, layout_floats, seed_value)
	# S4 listens on loopback only; re-listen where the tablets can reach it.
	_tcp.stop()
	var err: Error = _tcp.listen(port, bind)
	if err != OK:
		push_error("ws listen failed on %s:%d" % [bind, port])
		quit(1)
		return
	_http = S3StaticServer.new(http_root, http_slice)
	_http.keep_log = http_log
	err = _http.listen(http_port, bind)
	if err != OK:
		push_error("http listen failed on %s:%d" % [bind, http_port])
		quit(1)
		return
	_load = S6WorldPacked.new(seed_value)
	_load.setup_benchmark(load_ships, load_proj)
	_clip = _build_clip()
	if tick_log_path != "":
		_tick_log = FileAccess.open(tick_log_path, FileAccess.WRITE)
		_tick_log.store_line(
			"unix_us,lateness_us,http_delay_us,tick_us,http_max_us,http_bytes,http_conns,ws_conns"
		)
	_note(
		"s3_listening",
		{
			"http": "%s:%d" % [bind, http_port],
			"ws": "%s:%d" % [bind, port],
			"root": http_root,
			"budget_us": http_budget_us,
			"load": [load_ships, load_proj],
			"max_fps": max_fps,
		}
	)


func _process(delta: float) -> bool:
	if super._process(delta):
		_http.stop()
		_note("http_summary", _http_summary())
		if _tick_log != null:
			_tick_log.close()
		return true
	var t0: int = Time.get_ticks_usec()
	_http.poll(http_budget_us)
	var t1: int = Time.get_ticks_usec()
	_http_max_us = maxi(_http_max_us, t1 - t0)
	_http_spans.append(t0)
	_http_spans.append(t1)
	for line: String in _http.log:
		_note("req", {"line": line})
	_http.log.clear()
	return false


## Runs one tick and logs its lateness. The HTTP share of the lateness is the
## time HTTP polls ran between the tick's due time and its start.
func _sim_tick() -> void:
	var due: int = _next_tick_ticks
	var start: int = Time.get_ticks_usec()
	var http_delay: int = 0
	var i: int = 0
	while i < _http_spans.size():
		http_delay += maxi(0, mini(_http_spans[i + 1], start) - maxi(_http_spans[i], due))
		i += 2
	_http_spans.clear()
	super._sim_tick()
	_load.step()
	var tick_us: int = Time.get_ticks_usec() - start
	if _tick_log != null:
		var line: String = (
			"%d,%d,%d,%d,%d,%d,%d,%d"
			% [
				_unix_us(),
				start - due,
				http_delay,
				tick_us,
				_http_max_us,
				_http.bytes_out - _http_bytes_mark,
				_http.open_connections(),
				_conns.size(),
			]
		)
		_tick_log.store_line(line)
	_http_max_us = 0
	_http_bytes_mark = _http.bytes_out


func _on_message(c: Conn, m: Dictionary, now_us: int) -> void:
	match m.get("t", ""):
		"cmd":
			if c.joined:
				var seat: Dictionary = _sessions.get_session(c.token).get("seat", {})
				var sim: S3StationSim = _sim as S3StationSim
				var applied: int = sim.set_pips(seat.get("ship", -1), m["sys"], m["pips"])
				_note("cmd", {"client": c.name, "sys": m["sys"], "pips": applied})
		"voice_req":
			if c.joined:
				var msg_id: int = c.queue.push(S4Chunker.STREAM_VOICE, _clip)
				_note("voice_queued", {"client": c.name, "msg": msg_id, "bytes": _clip.size()})
		"report":
			_note("client_report", {"client": c.name, "data": m.get("data", {})})
		_:
			super._on_message(c, m, now_us)


func _stats() -> void:
	super._stats()
	_note("http", _http_summary())
	if _tick_log != null:
		_tick_log.flush()


func _http_summary() -> Dictionary:
	return {
		"requests": _http.requests,
		"gzip": _http.gzip_responses,
		"not_modified": _http.not_modified,
		"errors": _http.errors,
		"bytes_out": _http.bytes_out,
		"open": _http.open_connections(),
	}


## A short two-note chime, 22.05 kHz mono 16-bit, as an S4 voice message.
func _build_clip() -> PackedByteArray:
	var rate: int = 22050
	var samples: int = int(rate * clip_seconds)
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(samples * 2)
	var half: int = samples / 2
	for i: int in range(samples):
		var freq: float = 660.0 if i < half else 880.0
		var t: float = float(i % half) / rate
		var env: float = exp(-4.0 * t)
		pcm.encode_s16(i * 2, int(12000.0 * env * sin(TAU * freq * i / rate)))
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(pcm)
	return var_to_bytes({"t": "voice", "sha": ctx.finish().hex_encode(), "pcm": pcm, "rate": rate})


func _parse_s3_args(args: PackedStringArray) -> void:
	var opts: Dictionary = {}
	for i: int in range(0, args.size() - 1, 2):
		opts[args[i].trim_prefix("--")] = args[i + 1]
	http_port = int(opts.get("http-port", http_port))
	bind = opts.get("bind", bind)
	http_root = opts.get("http-root", ProjectSettings.globalize_path("res://build/s3"))
	http_budget_us = int(opts.get("http-budget-us", http_budget_us))
	http_slice = int(opts.get("http-slice", http_slice))
	tick_log_path = opts.get("tick-log", tick_log_path)
	http_log = opts.get("http-log", "0") == "1"
	load_ships = int(opts.get("load-ships", load_ships))
	load_proj = int(opts.get("load-proj", load_proj))
	clip_seconds = float(opts.get("clip-seconds", clip_seconds))
