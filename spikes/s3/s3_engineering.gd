extends Control
## S3 minimal Engineering panel (T021): power pips per system within the
## reactor cap and a heat readout, from snapshots over WebSocket; +/- send
## commands. "Tap to enable audio" unlocks Web Audio (FT-AUD-017), starts the
## keep-awake (FT-NET-046) and asks the server for a clip on the voice lane.
##
## Web: http://HOST:47820/?ws=47821&name=NAME (ws defaults to the page port
## plus one). The token lives in localStorage, so a reload rejoins the seat.
## Native: godot --path . res://spikes/s3/s3_engineering.tscn -- --url ws://...
## Prints "S3 <kind> <json>" lines to the console for the Playwright harness.

const TOKEN_KEY: String = "ft_s3_token"
const TOKEN_FILE: String = "user://s3_token.txt"
const PIP_ON: String = "#"
const PIP_OFF: String = "·"

var _link: S3Link
var _title: Label
var _status: Label
var _tap: Button
var _reactor: Label
var _note_label: Label
var _pips: Array[Label] = []
var _heat: Array[ProgressBar] = []
var _plus: Array[Button] = []
var _player: AudioStreamPlayer
var _first_snapshot: bool = true
var _welcomed: bool = false
var _cmd_pending: Dictionary = {}
var _boot_ms: float = 0.0
var _fps_frames: int = 0
var _fps_next_ms: int = 0
var _status_next_ms: int = 0
var _closed_reported: bool = false
var _seq_shown: int = -1


func _ready() -> void:
	_boot_ms = _page_ms()
	_build_ui()
	_player = AudioStreamPlayer.new()
	# Sample playback (the web default) needs an AudioWorklet, which an
	# http:// page doesn't have; stream playback goes through the mixer.
	_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(_player)
	_player.finished.connect(func() -> void: _say("voice_done", {}))
	var cfg: Dictionary = _config()
	_link = S3Link.new(cfg["url"], cfg["token"], cfg["name"])
	_say("boot", {"url": cfg["url"], "token": cfg["token"] != "", "name": cfg["name"]})
	var err: Error = _link.open()
	if err != OK:
		_say("connect_error", {"err": error_string(err)})
	_fps_next_ms = Time.get_ticks_msec() + 1000
	_status_next_ms = Time.get_ticks_msec() + 10000
	_report_layout.call_deferred()


func _process(_delta: float) -> void:
	_fps_frames += 1
	var now: int = Time.get_ticks_msec()
	if now >= _fps_next_ms:
		_say("fps", {"fps": _fps_frames, "engine": Engine.get_frames_per_second()})
		_fps_frames = 0
		_fps_next_ms += 1000
	if now >= _status_next_ms:
		_status_next_ms += 10000
		_say(
			"status",
			{
				"open": _link.is_open(),
				"seq": _link.last_seq,
				"snapshots": _link.snapshots,
				"events": _link.events,
				"keep_awake": S3KeepAwake.status(),
			}
		)
	for m: Dictionary in _link.poll():
		match m["t"]:
			"welcome":
				_on_welcome(m)
			"snap":
				_on_snapshot(m)
			"voice":
				_on_voice(m)
			"reject":
				_say("rejected", {"reason": m["reason"]})
			"closed":
				if not _closed_reported:
					_closed_reported = true
					S3KeepAwake.stop()
					_status.text = "disconnected"
					_say("closed", {"code": m["code"]})


func _on_welcome(m: Dictionary) -> void:
	_welcomed = true
	_store_token(_link.token)
	_title.text = "ENGINEERING · Ship %d" % int(_link.seat["ship"])
	_say("welcome", {"resumed": m["resumed"], "seat": m["seat"], "client": m["client"]})


func _on_snapshot(m: Dictionary) -> void:
	if _first_snapshot:
		_first_snapshot = false
		_say(
			"first_snapshot",
			{"seq": m["seq"], "full": m["full"], "resumed": _link.resumed, "seat": _link.seat}
		)
	var ship: Dictionary = _link.my_ship()
	if ship.is_empty():
		return
	var pips: PackedInt32Array = ship.get("pips", PackedInt32Array())
	var heat: PackedFloat32Array = ship.get("heat", PackedFloat32Array())
	var used: int = 0
	for i: int in range(mini(pips.size(), _pips.size())):
		used += pips[i]
		_pips[i].text = (
			PIP_ON.repeat(pips[i]) + PIP_OFF.repeat(S3EngineeringModel.MAX_PIPS - pips[i])
		)
		_heat[i].value = heat[i] * 100.0
		if _cmd_pending.has(i) and pips[i] == int(_cmd_pending[i][0]):
			var rtt: float = _page_ms() - float(_cmd_pending[i][1])
			_say("cmd_applied", {"sys": i, "pips": pips[i], "rtt_ms": rtt})
			_cmd_pending.erase(i)
	_reactor.text = "Reactor %d / %d" % [used, S3EngineeringModel.REACTOR_CAP]
	_seq_shown = m["seq"]
	_status.text = "snap %d" % _seq_shown


func _on_voice(m: Dictionary) -> void:
	var pcm: PackedByteArray = m["pcm"]
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(pcm)
	var ok: bool = ctx.finish().hex_encode() == m["sha"]
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(m.get("rate", 22050))
	wav.stereo = false
	wav.data = pcm
	_player.stream = wav
	_player.play()
	_note_label.text = "Chime received (%d kB)" % (pcm.size() / 1024)
	_say("voice_play", {"sha_ok": ok, "bytes": pcm.size()})


func _on_tap() -> void:
	var mode: String = S3KeepAwake.start()
	_link.send({"t": "voice_req"})
	_tap.text = "Audio on"
	_say("tap", {"keep_awake": mode})


func _on_pip(system: int, change: int) -> void:
	var ship: Dictionary = _link.my_ship()
	var pips: PackedInt32Array = ship.get("pips", PackedInt32Array())
	if system >= pips.size():
		return
	var target: int = clampi(pips[system] + change, 0, S3EngineeringModel.MAX_PIPS)
	_cmd_pending[system] = [target, _page_ms()]
	_link.send({"t": "cmd", "sys": system, "pips": target})


func _build_ui() -> void:
	var theme_res: Theme = Theme.new()
	theme_res.default_font_size = 26
	theme = theme_res
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	margin.add_child(col)
	var header: HBoxContainer = HBoxContainer.new()
	col.add_child(header)
	_title = Label.new()
	_title.text = "ENGINEERING · joining"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	_status = Label.new()
	_status.text = "connecting"
	header.add_child(_status)
	_tap = Button.new()
	_tap.text = "Tap to enable audio"
	_tap.custom_minimum_size = Vector2(0, 80)
	_tap.pressed.connect(_on_tap)
	col.add_child(_tap)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)
	col.add_child(grid)
	for i: int in range(S3EngineeringModel.SYSTEMS.size()):
		var name_label: Label = Label.new()
		name_label.text = S3EngineeringModel.SYSTEMS[i]
		grid.add_child(name_label)
		grid.add_child(_pip_button("-", i, -1))
		var pips: Label = Label.new()
		pips.text = PIP_OFF.repeat(S3EngineeringModel.MAX_PIPS)
		pips.custom_minimum_size = Vector2(140, 0)
		grid.add_child(pips)
		_pips.append(pips)
		var plus: Button = _pip_button("+", i, 1)
		grid.add_child(plus)
		_plus.append(plus)
		var heat: ProgressBar = ProgressBar.new()
		heat.custom_minimum_size = Vector2(240, 40)
		heat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heat.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(heat)
		_heat.append(heat)
	_reactor = Label.new()
	_reactor.text = "Reactor - / %d" % S3EngineeringModel.REACTOR_CAP
	col.add_child(_reactor)
	_note_label = Label.new()
	col.add_child(_note_label)


func _pip_button(text: String, system: int, change: int) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(72, 64)
	b.pressed.connect(_on_pip.bind(system, change))
	return b


## Logs the centres of the tap and "+" buttons, so a harness can click them.
func _report_layout() -> void:
	await get_tree().process_frame
	var plus: Array = []
	for b: Button in _plus:
		plus.append(_centre(b))
	_say("layout", {"tap": _centre(_tap), "plus": plus, "size": [size.x, size.y]})


static func _centre(c: Control) -> Array:
	var r: Rect2 = c.get_global_rect()
	return [r.get_center().x, r.get_center().y]


func _config() -> Dictionary:
	if OS.has_feature("web"):
		var raw: String = str(
			(
				JavaScriptBridge
				. eval(
					(
						"""
(function () {
  var q = new URLSearchParams(location.search);
  var port = q.get('ws') || String(parseInt(location.port || '80', 10) + 1);
  return JSON.stringify({
    url: 'ws://' + location.hostname + ':' + port,
    token: (q.get('fresh') ? '' : (localStorage.getItem('%s') || '')),
    name: q.get('name') || 'web'
  });
})()
"""
						% TOKEN_KEY
					),
					true
				)
			)
		)
		return JSON.parse_string(raw)
	var opts: Dictionary = {"url": "ws://127.0.0.1:47821", "name": "native"}
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i: int in range(0, args.size() - 1, 2):
		opts[args[i].trim_prefix("--")] = args[i + 1]
	var token: String = ""
	if FileAccess.file_exists(TOKEN_FILE):
		token = FileAccess.get_file_as_string(TOKEN_FILE).strip_edges()
	return {"url": opts["url"], "token": token, "name": opts["name"]}


func _store_token(value: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("localStorage.setItem('%s', '%s')" % [TOKEN_KEY, value], true)
	else:
		var f: FileAccess = FileAccess.open(TOKEN_FILE, FileAccess.WRITE)
		f.store_string(value)


## Milliseconds since the page's navigation started (performance.now()), or
## since the process started off the web.
static func _page_ms() -> float:
	if OS.has_feature("web"):
		return float(JavaScriptBridge.eval("performance.now()", true))
	return Time.get_ticks_usec() / 1000.0


static func _wall_ms() -> float:
	if OS.has_feature("web"):
		return float(JavaScriptBridge.eval("Date.now()", true))
	return Time.get_unix_time_from_system() * 1000.0


func _say(kind: String, data: Dictionary) -> void:
	data["page_ms"] = snappedf(_page_ms(), 0.1)
	data["wall_ms"] = _wall_ms()
	print("S3 %s %s" % [kind, JSON.stringify(data)])
