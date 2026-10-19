extends SceneTree
## S7b spike server (T020, TECH-5): the S4 server (snapshots, events, sessions,
## chunked two-lane send queues) with runtime Piper. One persistent Piper
## process per voice runs behind a worker thread (S7bPiper); the 60 Hz sim
## thread only queues requests and collects finished clips. Each clip goes on
## the voice lane of exactly one client (FT-AUD-019, FT-ARC-019). The sim tick
## also steps S6WorldPacked (100 ships, 500 projectiles) so the thread is busy.
##
## Phases: load voices; Start (synthesise and cache each language's closed set,
## load the prerendered number and word fragments; D101, FT-AUD-018); listen;
## once --target joins, fire one sim event every --line-every s: the free-text
## lines of --lines (synthesised now), then the stitched lines of --closed
## (built from the cache). Ends --tail s after the last clip has been sent.
##
## godot --headless --path . -s res://spikes/s7b/s7b_server.gd -- [flags]
## Flags (defaults in brackets): --port [47840] --python PATH (venv python, required)
## --wrapper [tools/tts/piper_stream.py] --threads [1] --lines [res://spikes/s7b/lines.json]
## --closed [res://spikes/s7b/closed_set.json] --fragments DIR [~/.cache/full-theta/s7b/fragments]
## --langs [en,it,pt] --target [c0] --lines-at s [2] --line-every s [1.0]
## --free N [all] --sim-ships [100] --sim-proj [500] --log PATH --tail s [3]
## --max-fps [120] --run-for s [300, a cap] --seed [1] --stream [sentence|clip]
## --nice [5] (Piper runs this much nicer than the server) --burst [1] (events per firing)

enum Phase { LOADING, START, RUN, DONE }

const PROTO: int = 1
const HISTORY: int = 64
const TICK_HZ: int = 60
const SNAPSHOT_HZ: int = 30


class Conn:
	extends RefCounted
	var peer: WebSocketPeer
	var id: int = 0
	var name: String = ""
	var token: String = ""
	var joined: bool = false
	var joined_us: int = 0
	var queue: S4SendQueue
	var resync: S4Resync
	var chunker: S4Chunker = S4Chunker.new()
	var acked_ev: int = 0
	var bytes_out: int = 0
	var voice_msgs: int = 0
	var voice_bytes: int = 0


var port: int = 47840
var python: String = ""
var wrapper: String = "tools/tts/piper_stream.py"
var threads: int = 1
var lines_path: String = "res://spikes/s7b/lines.json"
var closed_path: String = "res://spikes/s7b/closed_set.json"
var fragments_dir: String = ""
var langs: PackedStringArray = ["en", "it", "pt"]
var target: String = "c0"
var lines_at: float = 2.0
var line_every: float = 1.0
var free_count: int = -1
var sim_ships: int = 100
var sim_proj: int = 500
var log_path: String = ""
var tail_s: float = 3.0
var max_fps: int = 120
var run_for: float = 300.0
var seed_value: int = 1
var stream_mode: String = "sentence"
var niceness: int = 5
var burst: int = 1

var _phase: Phase = Phase.LOADING
var _tcp: TCPServer = TCPServer.new()
var _conns: Array[Conn] = []
var _sim: S4FakeSim
var _world: S6WorldPacked
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
var _log: FileAccess

## Voices: name -> S7bPiper.
var _voices: Dictionary = {}
var _load_start_us: int = 0
## Closed set and fragments: lang -> {key -> PackedByteArray}, plus rates.
var _cache: Dictionary = {}
var _rates: Dictionary = {}
var _closed: Dictionary = {}
var _start_lang: int = -1
var _start_t0: int = 0
var _start_wait: Dictionary = {}
var _start_total_us: int = 0

## Line schedule: each entry {kind, id, lang, voice, text | keys}.
var _schedule: Array[Dictionary] = []
var _next_line: int = 0
var _next_line_ticks: int = 0
## Request id -> {event_us, line, lang, voice, kind}.
var _in_flight: Dictionary = {}
var _next_req: int = 1
var _last_sent_ticks: int = 0
var _sim_us: PackedInt32Array = PackedInt32Array()
var _work_us: PackedInt32Array = PackedInt32Array()
var _late_us_max: int = 0
var _stat_next_s: int = 1
var _stat_work_max: int = 0
var _stat_sim_max: int = 0


func _initialize() -> void:
	_parse_args(OS.get_cmdline_user_args())
	Engine.max_fps = max_fps
	if log_path != "":
		_log = FileAccess.open(log_path, FileAccess.WRITE)
	if python == "":
		push_error("--python is required (the tools/tts venv interpreter)")
		quit(2)
		return
	_sim = S4FakeSim.new(6, 40, 2048, seed_value)
	_world = S6WorldPacked.new(seed_value)
	_world.setup_benchmark(sim_ships, sim_proj)
	_sessions = S4Sessions.new()
	_closed = JSON.parse_string(FileAccess.get_file_as_string(closed_path))
	var lines: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(lines_path))
	_build_schedule(lines["lines"])
	var names: Dictionary = {}
	for lang: String in langs:
		var spec: Dictionary = _closed["languages"][lang]
		names[spec["computer"]] = true
		names[spec["npc"]] = true
	for entry: Dictionary in _schedule:
		if entry["kind"] == "free":
			names[entry["voice"]] = true
	_load_start_us = S7bPiper.unix_us()
	var abs_wrapper: String = ProjectSettings.globalize_path("res://" + wrapper)
	for voice: String in names:
		var piper: S7bPiper = S7bPiper.new()
		piper.per_sentence = false
		var err: Error = piper.start(python, abs_wrapper, voice, threads, niceness)
		if err != OK:
			push_error("cannot start Piper for %s: %s" % [voice, error_string(err)])
			quit(1)
			return
		_voices[voice] = piper
	_note(
		"voices_starting",
		{"voices": names.keys(), "threads": threads, "nice": niceness, "stream": stream_mode}
	)
	_start_ticks = Time.get_ticks_usec()


func _build_schedule(lines: Array) -> void:
	var n: int = lines.size() if free_count < 0 else mini(free_count, lines.size())
	for i: int in range(n):
		var line: Dictionary = lines[i]
		if line["lang"] in langs:
			(
				_schedule
				. append(
					{
						"kind": "free",
						"id": line["id"],
						"lang": line["lang"],
						"voice": line["voice"],
						"text": line["text"],
					}
				)
			)
	var stitched: Array = _closed["stitched"]
	for lang: String in langs:
		for i: int in range(stitched.size()):
			_schedule.append(
				{
					"kind": "stitched",
					"id": "s%d-%s" % [i + 1, lang],
					"lang": lang,
					"keys": stitched[i]
				}
			)


func _process(_delta: float) -> bool:
	match _phase:
		Phase.LOADING:
			_poll_loading()
		Phase.START:
			_poll_start()
		Phase.RUN:
			_frame()
		Phase.DONE:
			return true
	if (Time.get_ticks_usec() - _start_ticks) / 1_000_000.0 > run_for:
		_note("run_for_cap", {})
		_finish()
		return true
	return false


func _poll_loading() -> void:
	for voice: String in _voices:
		var piper: S7bPiper = _voices[voice]
		if not piper.is_ready():
			if piper.info()["error"] != "":
				push_error("Piper %s failed: %s" % [voice, piper.info()["error"]])
				_finish()
			return
	var loads: Dictionary = {}
	for voice: String in _voices:
		var piper: S7bPiper = _voices[voice]
		loads[voice] = piper.info()["load_us"]
	_note("voices_ready", {"wall_us": S7bPiper.unix_us() - _load_start_us, "load_us": loads})
	_phase = Phase.START
	_start_next_language()


## Start, one language at a time (a session has one language, FT-AUD-013):
## request every closed-set item, then load that language's fragments.
func _start_next_language() -> void:
	_start_lang += 1
	if _start_lang >= langs.size():
		_note("start_done", {"total_us": _start_total_us})
		_listen()
		return
	var lang: String = langs[_start_lang]
	var spec: Dictionary = _closed["languages"][lang]
	_cache[lang] = {}
	_start_t0 = S7bPiper.unix_us()
	_start_wait = {}
	for group: String in ["ships", "callsigns", "npcs"]:
		var voice: String = spec["npc"] if group == "npcs" else spec["computer"]
		var items: Array = spec[group]
		for i: int in range(items.size()):
			var req: int = _next_req
			_next_req += 1
			_start_wait[req] = "%s:%d" % [group.trim_suffix("s"), i]
			(_voices[voice] as S7bPiper).request(req, items[i])


func _poll_start() -> void:
	var lang: String = langs[_start_lang]
	for piper: S7bPiper in _voices.values():
		for clip: Dictionary in piper.take_clips():
			var key: String = _start_wait[clip["id"]]
			_start_wait.erase(clip["id"])
			_cache[lang][key] = S7bStitch.trim(clip["pcm"], clip["rate"])
			_rates[lang] = clip["rate"]
	if not _start_wait.is_empty():
		return
	var synth_us: int = S7bPiper.unix_us() - _start_t0
	var items: int = (_cache[lang] as Dictionary).size()
	var synth_bytes: int = _cache_bytes(lang)
	var frag_us: int = _load_fragments(lang)
	var total_us: int = S7bPiper.unix_us() - _start_t0
	_start_total_us += total_us
	_note(
		"start_lang",
		{
			"lang": lang,
			"items": items,
			"synth_us": synth_us,
			"synth_bytes": synth_bytes,
			"fragments": (_cache[lang] as Dictionary).size() - items,
			"fragment_load_us": frag_us,
			"cache_bytes": _cache_bytes(lang),
			"total_us": total_us,
		}
	)
	_start_next_language()


## Loads LANG.pcm and LANG.json from prerender.py into the cache; returns µs.
func _load_fragments(lang: String) -> int:
	var t0: int = Time.get_ticks_usec()
	var index: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(fragments_dir.path_join(lang + ".json"))
	)
	var blob: PackedByteArray = FileAccess.get_file_as_bytes(fragments_dir.path_join(lang + ".pcm"))
	var frags: Dictionary = index["frags"]
	for key: String in frags:
		var span: Array = frags[key]
		var first: int = int(span[0]) * 2
		_cache[lang][key] = blob.slice(first, first + int(span[1]) * 2)
	return Time.get_ticks_usec() - t0


func _cache_bytes(lang: String) -> int:
	var total: int = 0
	for pcm: PackedByteArray in (_cache[lang] as Dictionary).values():
		total += pcm.size()
	return total


func _listen() -> void:
	var err: Error = _tcp.listen(port, "127.0.0.1")
	if err != OK:
		push_error("listen failed on %d: %s" % [port, error_string(err)])
		_finish()
		return
	for piper: S7bPiper in _voices.values():
		piper.per_sentence = stream_mode == "sentence"
	_tick_us = int(1_000_000 / float(TICK_HZ))
	_next_tick_ticks = Time.get_ticks_usec() + _tick_us
	_phase = Phase.RUN
	_note("listening", {"port": port, "sim_ships": sim_ships, "sim_proj": sim_proj})


func _frame() -> void:
	var frame_start: int = Time.get_ticks_usec()
	_accept()
	_poll_all()
	var ticks: int = 0
	_late_us_max = maxi(_late_us_max, frame_start - _next_tick_ticks)
	while frame_start >= _next_tick_ticks and ticks < 4:
		_sim_tick()
		_next_tick_ticks += _tick_us
		ticks += 1
	if frame_start >= _next_tick_ticks:
		_next_tick_ticks = frame_start + _tick_us
	_collect_clips()
	_pump_all()
	var work: int = Time.get_ticks_usec() - frame_start
	_work_us.append(work)
	_stat_work_max = maxi(_stat_work_max, work)
	var elapsed: float = (frame_start - _start_ticks) / 1_000_000.0
	if elapsed >= _stat_next_s:
		_stats()
		_stat_next_s = int(elapsed) + 1
	var done: bool = _next_line >= _schedule.size() and _in_flight.is_empty()
	if done and _last_sent_ticks > 0 and _voice_lanes_empty():
		if (frame_start - _last_sent_ticks) / 1_000_000.0 >= tail_s:
			_finish()


func _accept() -> void:
	while _tcp.is_connection_available():
		var tcp: StreamPeerTCP = _tcp.take_connection()
		tcp.set_no_delay(true)
		var c: Conn = Conn.new()
		c.peer = WebSocketPeer.new()
		c.peer.accept_stream(tcp)
		c.id = _next_conn_id
		_next_conn_id += 1
		c.queue = S4SendQueue.new()
		_conns.append(c)


func _poll_all() -> void:
	var now_us: int = S7bPiper.unix_us()
	var closed: Array[Conn] = []
	for c: Conn in _conns:
		c.peer.poll()
		if c.peer.get_ready_state() == WebSocketPeer.STATE_CLOSED:
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
		_note("drop", {"client": c.name, "conn": c.id})


func _on_message(c: Conn, m: Dictionary, now_us: int) -> void:
	match m.get("t", ""):
		"hello":
			c.name = m.get("name", "")
			c.acked_ev = _event_seq
			c.token = _sessions.issue(_sim.seat_for(_join_count), c.acked_ev)
			_join_count += 1
			c.joined = true
			c.joined_us = now_us
			c.resync = S4Resync.new()
			var welcome: Dictionary = {
				"t": "welcome",
				"token": c.token,
				"seat": {},
				"resumed": false,
				"ev_from": c.acked_ev
			}
			c.queue.push(S4Chunker.STREAM_CONTROL, var_to_bytes(welcome))
			_note("join", {"client": c.name, "conn": c.id})
			if c.name == target and _next_line_ticks == 0:
				_next_line_ticks = Time.get_ticks_usec() + int(lines_at * 1_000_000)
		"ack":
			if c.joined:
				c.resync.on_ack(m["snap"])
				c.acked_ev = maxi(c.acked_ev, m["ev"])
				_sessions.set_acked_event(c.token, c.acked_ev)
				_trim_events()


func _sim_tick() -> void:
	var t0: int = Time.get_ticks_usec()
	_world.step()
	var event: Dictionary = _sim.step(1.0 / TICK_HZ)
	var sim_us: int = Time.get_ticks_usec() - t0
	_sim_us.append(sim_us)
	_stat_sim_max = maxi(_stat_sim_max, sim_us)
	if not event.is_empty():
		_event_seq += 1
		event["seq"] = _event_seq
		event["t"] = "ev"
		_events.append(event)
		_event_bytes[_event_seq] = var_to_bytes(event)
		for c: Conn in _conns:
			if c.joined and not c.resync.holds_events():
				c.queue.push(S4Chunker.STREAM_CONTROL, _event_bytes[_event_seq])
	if _next_line_ticks > 0 and _next_line < _schedule.size() and t0 >= _next_line_ticks:
		for i: int in range(mini(burst, _schedule.size() - _next_line)):
			_fire_line(_schedule[_next_line])
			_next_line += 1
		_next_line_ticks += int(line_every * 1_000_000)
	if _sim.tick % int(TICK_HZ / float(SNAPSHOT_HZ)) == 0:
		_snapshot_tick()


## The sim event that needs a voice line: stamp it, then either queue it for
## Piper (free text) or stitch it from the Start cache right here.
func _fire_line(entry: Dictionary) -> void:
	var event_us: int = S7bPiper.unix_us()
	var req: int = _next_req
	_next_req += 1
	var meta: Dictionary = {
		"event_us": event_us, "line": entry["id"], "lang": entry["lang"], "kind": entry["kind"]
	}
	if entry["kind"] == "free":
		meta["voice"] = entry["voice"]
		_in_flight[req] = meta
		(_voices[entry["voice"]] as S7bPiper).request(req, entry["text"])
		return
	var t0: int = Time.get_ticks_usec()
	var parts: Array[PackedByteArray] = []
	var cache: Dictionary = _cache[entry["lang"]]
	for key: String in entry["keys"]:
		parts.append(cache[key])
	var pcm: PackedByteArray = S7bStitch.join(parts, _rates[entry["lang"]])
	var stitch_us: int = Time.get_ticks_usec() - t0
	meta["voice"] = "cache"
	var clip: Dictionary = {
		"id": req,
		"part": 0,
		"last": true,
		"pcm": pcm,
		"rate": _rates[entry["lang"]],
		"synth_us": stitch_us,
		"error": "",
		"queued_us": event_us,
		"started_us": event_us,
		"first_us": event_us + stitch_us,
		"done_us": event_us + stitch_us,
	}
	_in_flight[req] = meta
	_send_clip(clip)


func _collect_clips() -> void:
	for piper: S7bPiper in _voices.values():
		for clip: Dictionary in piper.take_clips():
			_send_clip(clip)


## Exactly one recipient per clip: the target client (FT-AUD-019).
func _send_clip(clip: Dictionary) -> void:
	var meta: Dictionary = _in_flight[clip["id"]]
	if clip["last"]:
		_in_flight.erase(clip["id"])
	var to: Conn = null
	for c: Conn in _conns:
		if c.joined and c.name == target:
			to = c
	var pcm: PackedByteArray = clip["pcm"]
	var timing: Dictionary = {
		"line": meta["line"],
		"kind": meta["kind"],
		"part": clip["part"],
		"last": clip["last"],
		"lang": meta["lang"],
		"voice": meta["voice"],
		"event_us": meta["event_us"],
		"started_us": clip["started_us"],
		"first_us": clip["first_us"],
		"done_us": clip["done_us"],
		"synth_us": clip["synth_us"],
		"sent_us": S7bPiper.unix_us(),
		"rate": clip["rate"],
		"audio_ms": pcm.size() * 500 / maxi(1, int(clip["rate"])),
		"error": clip["error"],
	}
	_note("clip", timing)
	if to == null:
		return
	timing["t"] = "voice"
	timing["pcm"] = pcm
	var bytes: PackedByteArray = var_to_bytes(timing)
	to.queue.push(S4Chunker.STREAM_VOICE, bytes)
	to.voice_msgs += 1
	to.voice_bytes += bytes.size()
	_last_sent_ticks = Time.get_ticks_usec()


func _voice_lanes_empty() -> bool:
	for c: Conn in _conns:
		if c.queue.low_bytes > 0:
			return false
	return true


func _snapshot_tick() -> void:
	_snap_seq += 1
	_history[_snap_seq] = {"state": _sim.state(), "tick": _sim.tick, "sent_us": S7bPiper.unix_us()}
	_history.erase(_snap_seq - HISTORY)
	_delta_cache.erase(_snap_seq - HISTORY)
	for c: Conn in _conns:
		if c.joined:
			_send_snapshot(c)


func _send_snapshot(c: Conn) -> void:
	var action: S4Resync.Action = c.resync.decide(c.queue.high_bytes)
	var entry: Dictionary = _history[_snap_seq]
	var base: int = c.resync.delta_base()
	if action == S4Resync.Action.DELTA and not _history.has(base):
		action = S4Resync.Action.FULL
	if action == S4Resync.Action.NONE:
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
	else:
		bytes = _delta_bytes(base)
	c.queue.push(S4Chunker.STREAM_SNAPSHOT, bytes)
	c.resync.on_sent(_snap_seq, action == S4Resync.Action.FULL)


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
			if c.peer.get_current_outbound_buffered_amount() + size > limit:
				break
			var chunk: PackedByteArray = c.queue.next_chunk()
			if c.peer.send(chunk) != OK:
				# As in S4Server: the chunk is gone, so drop the connection and
				# let the client resume with its token (D106).
				c.resync.on_send_error()
				c.peer.close(-1)
				break
			c.bytes_out += chunk.size()
		c.peer.poll()


func _trim_events() -> void:
	var low: int = _sessions.min_acked_event(_event_seq)
	while not _events.is_empty() and int(_events[0]["seq"]) <= low:
		_event_bytes.erase(_events[0]["seq"])
		_events.pop_front()


func _stats() -> void:
	var pending: int = 0
	for piper: S7bPiper in _voices.values():
		pending += piper.pending()
	_note(
		"stats",
		{
			"work_max_us": _stat_work_max,
			"sim_max_us": _stat_sim_max,
			"late_max_us": _late_us_max,
			"synth_pending": pending,
		}
	)
	_stat_work_max = 0
	_stat_sim_max = 0
	_late_us_max = 0


func _finish() -> void:
	_phase = Phase.DONE
	var clients: Dictionary = {}
	for c: Conn in _conns:
		clients[c.name] = {
			"voice_msgs": c.voice_msgs, "voice_bytes": c.voice_bytes, "bytes_out": c.bytes_out
		}
	_note(
		"summary",
		{
			"sim_us": _percentiles(_sim_us),
			"frame_work_us": _percentiles(_work_us),
			"snapshots": _snap_seq,
			"lines": _next_line,
			"clients": clients,
		}
	)
	for c: Conn in _conns:
		c.peer.close(1001, "server done")
		c.peer.poll()
	for piper: S7bPiper in _voices.values():
		piper.stop()
	if _log != null:
		_log.close()
	quit(0)


static func _percentiles(values: PackedInt32Array) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted: PackedInt32Array = values.duplicate()
	sorted.sort()
	var n: int = sorted.size()
	var total: int = 0
	for v: int in sorted:
		total += v
	return {
		"n": n,
		"mean": total / n,
		"p50": sorted[n / 2],
		"p99": sorted[mini(n - 1, n * 99 / 100)],
		"max": sorted[n - 1],
	}


func _note(kind: String, data: Dictionary) -> void:
	var line: String = "%d %s %s" % [S7bPiper.unix_us(), kind, JSON.stringify(data)]
	print(line)
	if _log != null:
		_log.store_line(line)
		_log.flush()


func _parse_args(args: PackedStringArray) -> void:
	var opts: Dictionary = {}
	for i: int in range(0, args.size() - 1, 2):
		opts[args[i].trim_prefix("--")] = args[i + 1]
	port = int(opts.get("port", port))
	python = opts.get("python", python)
	wrapper = opts.get("wrapper", wrapper)
	threads = int(opts.get("threads", threads))
	lines_path = opts.get("lines", lines_path)
	closed_path = opts.get("closed", closed_path)
	var default_frags: String = OS.get_environment("HOME").path_join(
		".cache/full-theta/s7b/fragments"
	)
	fragments_dir = opts.get("fragments", default_frags)
	langs = (opts.get("langs", ",".join(langs)) as String).split(",")
	target = opts.get("target", target)
	lines_at = float(opts.get("lines-at", lines_at))
	line_every = float(opts.get("line-every", line_every))
	free_count = int(opts.get("free", free_count))
	sim_ships = int(opts.get("sim-ships", sim_ships))
	sim_proj = int(opts.get("sim-proj", sim_proj))
	log_path = opts.get("log", log_path)
	tail_s = float(opts.get("tail", tail_s))
	max_fps = int(opts.get("max-fps", max_fps))
	run_for = float(opts.get("run-for", run_for))
	seed_value = int(opts.get("seed", seed_value))
	stream_mode = opts.get("stream", stream_mode)
	niceness = int(opts.get("nice", niceness))
	burst = int(opts.get("burst", burst))
