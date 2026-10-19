extends SceneTree
## Voice latency harness, server side (FT-AUD-015, FT-AUD-018; the S7b method,
## docs/spikes/S7b.md, on the promoted code). Composes the real NetServer and
## VoiceService the way app/main.gd does (ServerMain, VoiceSetup: piper_stream.py in
## development, the release binary when FT_PIPER_BIN is set), adds the S7b sim load
## (S6WorldPacked stepped once per NetServer tick on the same thread), waits for the
## target client c0 and the bystander c1, then runs one session per language:
## start_session() with the S7b closed set (Start time logged), the language's S7b
## free-text lines through say_free(), one a second, then a few stitched lines through
## say() with names and numbers, every line to c0's session only.
##
## godot --headless --path . -s res://tools/voice_latency/vl_server.gd -- --log PATH
##   [--port 47850] [--langs en,it,pt_PT] [--line-every 1.0] [--lines-at 2.0] [--tail 3.0]
##   [--sim-ships 100] [--sim-proj 500] [--max-lang-s 300]
##
## Log: one JSON object per line, "ev" one of listening, clients, start_begin,
## start_lang, line (clip, kind, lang, role, id, text, event_us), lang_done, summary.
## Times named *_us are unix µs (same host as the clients).

enum Phase { CLIENTS, START, FIRE, DRAIN, DONE }

const LINES: String = "res://spikes/s7b/lines.json"
const CLOSED_SET: String = "res://spikes/s7b/closed_set.json"
## S7b's language keys to session languages (FT-AUD-012).
const LANGS: Dictionary = {"en": "en", "it": "it", "pt": "pt_PT"}
## S7b's English voices by role (content/voices.json); it and pt_PT use one voice for
## both roles, so their lines alternate roles.
const VOICE_ROLES: Dictionary = {"en_GB-cori-medium": "computer", "en_US-norman-medium": "npc"}
const TARGET: String = "c0"
const BYSTANDER: String = "c1"

var port: int = 47850
var log_path: String = ""
var langs: PackedStringArray = ["en", "it", "pt"]
var line_every: float = 1.0
var lines_at: float = 2.0
var tail: float = 3.0
var sim_ships: int = 100
var sim_proj: int = 500
var max_lang_s: float = 300.0

var _server: NetServer
var _voice: VoiceService
var _load: S6WorldPacked
var _log: FileAccess
var _lines: Array = []
var _closed: Dictionary = {}
var _phase: Phase = Phase.CLIENTS
var _lang_i: int = -1
var _queue: Array[Dictionary] = []
var _next_us: int = 0
var _phase_us: int = 0
var _lang_us: int = 0
var _target: int = -1
var _last_tick: int = 0
var _last_frame_us: int = 0
var _sim_us: PackedInt32Array = PackedInt32Array()
var _frame_us: PackedInt32Array = PackedInt32Array()


func _initialize() -> void:
	if not _parse_args(OS.get_cmdline_user_args()):
		quit(2)
		return
	_log = FileAccess.open(log_path, FileAccess.WRITE)
	_lines = (JSON.parse_string(FileAccess.get_file_as_string(LINES)) as Dictionary)["lines"]
	_closed = (JSON.parse_string(FileAccess.get_file_as_string(CLOSED_SET)) as Dictionary)
	var cli: ServerMain = ServerMain.new()
	if not cli.parse_args(["--bind", "127.0.0.1", "--port", str(port), "--no-beacon"]):
		quit(2)
		return
	ServerMain.configure_engine()
	_server = cli.make_server()
	if _server == null:
		quit(1)
		return
	root.add_child(_server)
	_voice = cli.make_voice(_server)
	# pt_PT's voice is dev_only (D105): this harness measures it like S7b did.
	_voice.allow_dev_voices = true
	root.add_child(_voice)
	if sim_ships > 0:
		_load = S6WorldPacked.new(1)
		_load.setup_benchmark(sim_ships, sim_proj)
	_last_tick = _server.world.tick
	var adapter: String = "binary" if OS.get_environment(VoiceSetup.BIN_ENV) != "" else "stream"
	_note(
		"listening",
		{"port": _server.port(), "adapter": adapter, "sim_ships": sim_ships, "sim_proj": sim_proj}
	)
	_phase_us = Time.get_ticks_usec()


func _process(_delta: float) -> bool:
	var now: int = Time.get_ticks_usec()
	if _last_frame_us > 0:
		_frame_us.append(now - _last_frame_us)
	_last_frame_us = now
	_step_load()
	match _phase:
		Phase.CLIENTS:
			_wait_clients(now)
		Phase.START:
			if _voice.closed_set_done():
				_on_started(now)
			elif now - _lang_us > max_lang_s * 1_000_000.0:
				_lang_done("start timed out")
		Phase.FIRE:
			if now >= _next_us:
				_fire(_queue.pop_front())
				_next_us += int(line_every * 1_000_000.0)
				if _queue.is_empty():
					_phase = Phase.DRAIN
					_phase_us = now
		Phase.DRAIN:
			if _voice.free_queued() > 0 and now - _lang_us < max_lang_s * 1_000_000.0:
				_phase_us = now
			elif now - _phase_us > tail * 1_000_000.0:
				_lang_done("ok" if _voice.free_queued() == 0 else "timed out")
	return _phase == Phase.DONE


func _finalize() -> void:
	if _log != null:
		_log.close()


## Steps the S7b sim load once per NetServer tick since the last frame.
func _step_load() -> void:
	if _server == null:
		return
	var ticks: int = _server.world.tick - _last_tick
	_last_tick = _server.world.tick
	if _load == null:
		return
	for i: int in ticks:
		var t0: int = Time.get_ticks_usec()
		_load.step()
		_sim_us.append(Time.get_ticks_usec() - t0)


func _wait_clients(now: int) -> void:
	var by_name: Dictionary = {}
	for s: NetSession in _server.session.by_id.values():
		if s.connected():
			by_name[s.name] = s.id
	if by_name.has(TARGET) and by_name.has(BYSTANDER):
		_target = by_name[TARGET]
		_note("clients", {"target": _target, "bystander": by_name[BYSTANDER]})
		_next_lang()
	elif now - _phase_us > 60_000_000:
		_note("error", {"why": "clients did not join"})
		_phase = Phase.DONE


func _next_lang() -> void:
	_lang_i += 1
	if _lang_i >= langs.size():
		_summary()
		_phase = Phase.DONE
		return
	var key: String = langs[_lang_i]
	var spec: Dictionary = _closed["languages"][key]
	var closed: Dictionary = {
		"ship_names": spec["ships"], "callsigns": spec["callsigns"], "npc_names": spec["npcs"]
	}
	_lang_us = Time.get_ticks_usec()
	_note("start_begin", {"lang": LANGS[key]})
	_voice.start_session(LANGS[key], closed)
	_phase = Phase.START


func _on_started(now: int) -> void:
	var key: String = langs[_lang_i]
	var lang: String = LANGS[key]
	_note(
		"start_lang",
		{
			"lang": lang,
			"start_ms": int(_voice.start_ms.get(lang, -1)),
			"wall_ms": (now - _lang_us) / 1000,
			"computer": _voice.has_voice("computer"),
			"npc": _voice.has_voice("npc"),
		}
	)
	_queue.clear()
	var n: int = 0
	for entry: Dictionary in _lines:
		if entry["lang"] != key:
			continue
		var role: String = VOICE_ROLES.get(entry["voice"], "computer" if n % 2 == 0 else "npc")
		_queue.append({"kind": "free", "id": entry["id"], "text": entry["text"], "role": role})
		n += 1
	var spec: Dictionary = _closed["languages"][key]
	for s: Array in _stitched(spec):
		_queue.append({"kind": "stitched", "id": s[0], "args": s[1]})
	_next_us = now + int(lines_at * 1_000_000.0)
	_phase = Phase.FIRE


## Slotted lines of content/dialogue with closed-set names and numbers (S7b's templates).
static func _stitched(spec: Dictionary) -> Array:
	return [
		["computer.contact", {"callsign": spec["callsigns"][2], "bearing": 342, "range": 18}],
		["npc.hail_patrol", {"ship": spec["ships"][1], "npc": spec["npcs"][4]}],
		["npc.distress", {"npc": spec["npcs"][4]}],
		["computer.shields_low", {"pct": 40}],
		["computer.contact", {"callsign": spec["callsigns"][17], "bearing": 7, "range": 250}],
	]


## The sim event that needs a line: stamp it, then hand it to the voice service.
func _fire(item: Dictionary) -> void:
	var audience: PackedInt32Array = PackedInt32Array([_target])
	var event_us: int = _unix_us()
	var clip: int
	var role: String = ""
	if item["kind"] == "free":
		role = item["role"]
		clip = _voice.say_free(item["text"], role, 1, audience)
	else:
		clip = _voice.say(item["id"], item["args"], audience)
	var after_us: int = _unix_us()
	_note(
		"line",
		{
			"clip": clip,
			"kind": item["kind"],
			"lang": _voice.lang,
			"role": role,
			"id": item["id"],
			"event_us": event_us,
			"call_us": after_us - event_us,
			"free_queued": _voice.free_queued(),
		}
	)


func _lang_done(why: String) -> void:
	_note("lang_done", {"lang": _voice.lang, "why": why, "stats": _voice.stats.duplicate()})
	_next_lang()


func _summary() -> void:
	_note(
		"summary",
		{
			"sim_us": _stats(_sim_us),
			"frame_us": _stats(_frame_us),
			"net_tick_us_max": _server.tick_us_max,
			"start_ms": _voice.start_ms,
			"voice": _voice.stats,
		}
	)


static func _stats(values: PackedInt32Array) -> Dictionary:
	if values.is_empty():
		return {}
	var s: PackedInt32Array = values.duplicate()
	s.sort()
	var total: int = 0
	for v: int in s:
		total += v
	return {
		"n": s.size(),
		"mean": total / s.size(),
		"p50": s[s.size() / 2],
		"p99": s[mini(s.size() - 1, int(s.size() * 0.99))],
		"max": s[s.size() - 1],
	}


func _note(ev: String, fields: Dictionary) -> void:
	fields["ev"] = ev
	fields["us"] = _unix_us()
	_log.store_line(JSON.stringify(fields))
	_log.flush()


static func _unix_us() -> int:
	return int(Time.get_unix_time_from_system() * 1_000_000.0)


func _parse_args(args: PackedStringArray) -> bool:
	var i: int = 0
	while i + 1 < args.size():
		var value: String = args[i + 1]
		match args[i]:
			"--port":
				port = value.to_int()
			"--log":
				log_path = value
			"--langs":
				langs = PackedStringArray()
				for lang: String in value.split(","):
					# Session codes (pt_PT) or S7b's keys (pt).
					langs.append(LANGS.find_key(lang) if LANGS.find_key(lang) != null else lang)
			"--line-every":
				line_every = value.to_float()
			"--lines-at":
				lines_at = value.to_float()
			"--tail":
				tail = value.to_float()
			"--sim-ships":
				sim_ships = value.to_int()
			"--sim-proj":
				sim_proj = value.to_int()
			"--max-lang-s":
				max_lang_s = value.to_float()
			_:
				push_error("vl_server: unknown flag %s" % args[i])
				return false
		i += 2
	if i != args.size() or log_path == "":
		push_error("vl_server: --log PATH is required; flags take one value each")
		return false
	for key: String in langs:
		if not LANGS.has(key):
			push_error("vl_server: --langs takes en, it, pt")
			return false
	return true
