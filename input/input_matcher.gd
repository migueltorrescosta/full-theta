class_name InputMatcher
extends RefCounted
## Devices to intents (FT-STN-005, D95): turns InputEvents into intent events using the
## live Bindings, with chords, tap versus long press on one button, button sequences,
## hold-to-toggle and axes. Pure logic with time passed in (no Node, no InputMap), so
## tests drive it with synthetic events. Grammar and semantics: input/README.md.
##
## Context: set_context(stations, focused) picks the active intents: common, live, the
## focused station's, and the other stations' intents that are live on the event's
## device (IntentTable.target). When two active bindings share a button or axis, the
## longer chord wins (View+X suppresses X, LB+LS_X suppresses LS_X); identical
## bindings on two active intents both fire, in table order.
##
## Intent event (Dictionary): {"id", "group", "target" (IntentTable.target), "kind",
## "pressed" (press: true; hold: the new held state, toggle-aware), "value" (1.0 or
## 0.0), "device"}. Axes are polled with axis(); feed() emits no axis events.
##
## Gestures (PROVISIONAL timings):
## - a button that is also a modifier or has a "long" binding in the active set fires
##   its plain press on release, if released before LONG_MS and no chord used it;
## - "long X" fires once X has been held LONG_MS;
## - "B,2": after B, a press of 2 within SEQUENCE_MS fires the sequence; B's own press
##   waits for the timeout when a sequence starting with B is active.
## Analog: stick dead zone 0.2, trigger 0.1, rescaled to 0..1 beyond it (S5). The mouse
## virtual stick (MouseStick, S5) feeds "MouseX"/"MouseY".

const LONG_MS: int = 400
const SEQUENCE_MS: int = 700
const STICK_DEAD_ZONE: float = 0.2
const TRIGGER_DEAD_ZONE: float = 0.1
## A stick counts as a button ("LS", "RS") past this deflection.
const STICK_BUTTON: float = 0.5
## Mouse motion shorter than this (px) doesn't switch the device to KB/M.
const MOUSE_NOISE_PX: float = 2.0

const _MOUSE_NAMES: Dictionary = {
	"LMB": MOUSE_BUTTON_LEFT,
	"RMB": MOUSE_BUTTON_RIGHT,
	"MMB": MOUSE_BUTTON_MIDDLE,
	"WheelUp": MOUSE_BUTTON_WHEEL_UP,
	"WheelDown": MOUSE_BUTTON_WHEEL_DOWN,
}
const _PAD_BUTTONS: Dictionary = {
	"A": JOY_BUTTON_A,
	"B": JOY_BUTTON_B,
	"X": JOY_BUTTON_X,
	"Y": JOY_BUTTON_Y,
	"LB": JOY_BUTTON_LEFT_SHOULDER,
	"RB": JOY_BUTTON_RIGHT_SHOULDER,
	"L3": JOY_BUTTON_LEFT_STICK,
	"R3": JOY_BUTTON_RIGHT_STICK,
	"View": JOY_BUTTON_BACK,
	"Menu": JOY_BUTTON_START,
	"Up": JOY_BUTTON_DPAD_UP,
	"Down": JOY_BUTTON_DPAD_DOWN,
	"Left": JOY_BUTTON_DPAD_LEFT,
	"Right": JOY_BUTTON_DPAD_RIGHT,
}
const _PAD_AXES: Dictionary = {
	"LS_X": JOY_AXIS_LEFT_X,
	"LS_Y": JOY_AXIS_LEFT_Y,
	"RS_X": JOY_AXIS_RIGHT_X,
	"RS_Y": JOY_AXIS_RIGHT_Y,
	"LT": JOY_AXIS_TRIGGER_LEFT,
	"RT": JOY_AXIS_TRIGGER_RIGHT,
}
## Pad axes that also act as buttons.
const _ANALOG_BUTTONS: Array[String] = ["p:LT", "p:RT", "p:LS", "p:RS"]
const _KBM_MODIFIERS: Array[String] = ["Shift", "Alt", "Ctrl"]

## The player's bindings; replacing it re-reads every binding.
var bindings: Bindings:
	set = _set_bindings
## Device of the last input that mattered: IntentTable.KBM or PAD (the overlay and aim
## assist follow it, FT-SIM-015).
var device: String = IntentTable.KBM
## Flips intents marked "pitch" (Settings: invert pitch, S5).
var invert_pitch: bool = false
var mouse_stick: MouseStick = MouseStick.new()

var _stations: Array = []
var _focused: String = ""
## Device -> parsed active bindings in table order (entries built by _parse).
var _active: Dictionary = {}
var _dirty: bool = true
## Input name ("k:<keycode>", "m:LMB", "p:A", ...) -> press time (ms), while down.
var _down: Dictionary = {}
## KB/M modifiers held per the last KB/M event's flags: name -> true.
var _flag_mods: Dictionary = {}
## Raw pad axes: "p:LS_X" -> value.
var _raw: Dictionary = {}
## Buttons whose plain press waits for release (tap) or LONG_MS: name -> {"t", "dev"}.
var _deferred: Dictionary = {}
## Buttons already used by a chord, long press or sequence until released: name -> true.
var _spent: Dictionary = {}
## A sequence's first button waiting for the second: {"name", "t", "dev"} or {}.
var _seq: Dictionary = {}
## Hold intents held by inputs: id -> {"inputs": Array[String], "dev"}.
var _holding: Dictionary = {}
## Hold intents toggled on (FT-STN-014): id -> device.
var _toggled: Dictionary = {}
## Physical key that produced the "?" currently down.
var _question_key: String = ""
## Events waiting for the next feed() or update() (released by set_context).
var _queue: Array[Dictionary] = []


func _init(p_bindings: Bindings = null) -> void:
	bindings = p_bindings if p_bindings != null else Bindings.new()


## The screen's stations and the focused one; held and toggled states of intents that
## leave the active set are released (with a released event on the next update()).
func set_context(stations: Array, focused: String) -> void:
	_stations = stations.duplicate()
	_focused = focused
	_dirty = true
	for id: String in _holding.keys():
		var dev: String = _holding[id]["dev"]
		if IntentTable.target(id, dev, _focused, _stations) == "":
			_holding.erase(id)
			_queue.append(_event(id, dev, false))
	for id: String in _toggled.keys():
		var dev: String = _toggled[id]
		if IntentTable.target(id, dev, _focused, _stations) == "":
			_toggled.erase(id)
			_queue.append(_event(id, dev, false))


## Feeds one input event at `now_ms`; returns the intent events it completes.
func feed(event: InputEvent, now_ms: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = _take_queue()
	_tick(now_ms, out)
	if event.is_echo():
		return out
	if event is InputEventMouseMotion:
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		mouse_stick.move(rel)
		if rel.length() >= MOUSE_NOISE_PX:
			device = IntentTable.KBM
	elif event is InputEventJoypadMotion:
		_motion(event as InputEventJoypadMotion, now_ms, out)
	elif event is InputEventKey:
		_key(event as InputEventKey, now_ms, out)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		_flags(mb)
		var name: Variant = _MOUSE_NAMES.find_key(mb.button_index)
		if name != null:
			_button("m:" + str(name), mb.pressed, IntentTable.KBM, now_ms, out)
	elif event is InputEventJoypadButton:
		var jb: InputEventJoypadButton = event
		var pad_name: Variant = _PAD_BUTTONS.find_key(jb.button_index)
		if pad_name != null:
			_button("p:" + str(pad_name), jb.pressed, IntentTable.PAD, now_ms, out)
	return out


## Advances timers (long presses, sequence timeouts, the mouse stick's re-centring);
## returns the intent events they complete. Call every frame.
func update(now_ms: int, delta: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = _take_queue()
	_tick(now_ms, out)
	mouse_stick.decay(delta)
	return out


## Current value of an axis intent (-1..1; 0 when inactive or not an axis): the
## largest deflection over the active bindings of both devices.
func axis(id: String) -> float:
	var r: Dictionary = IntentTable.row(id)
	if r.get("kind", "") != IntentTable.AXIS:
		return 0.0
	_refresh()
	var best: float = 0.0
	for dev: String in IntentTable.DEVICES:
		for e: Dictionary in _active[dev]:
			if e["id"] == id:
				var v: float = _axis_value(e, dev)
				if absf(v) > absf(best):
					best = v
	if invert_pitch and r.get("pitch", false):
		best = -best
	return clampf(best, -1.0, 1.0)


## True while a hold intent is held, or toggled on (FT-STN-014).
func is_held(id: String) -> bool:
	return _holding.has(id) or _toggled.has(id)


## Releases every held and toggled intent and forgets pressed buttons and pending
## gestures (focus loss, screen change).
func release_all() -> Array[Dictionary]:
	var out: Array[Dictionary] = _take_queue()
	for id: String in _holding:
		out.append(_event(id, _holding[id]["dev"], false))
	for id: String in _toggled:
		out.append(_event(id, _toggled[id], false))
	_holding.clear()
	_toggled.clear()
	_down.clear()
	_flag_mods.clear()
	_raw.clear()
	_deferred.clear()
	_spent.clear()
	_seq = {}
	_question_key = ""
	mouse_stick.value = Vector2.ZERO
	return out


func _set_bindings(b: Bindings) -> void:
	if bindings != null and bindings.changed.is_connected(_on_bindings_changed):
		bindings.changed.disconnect(_on_bindings_changed)
	bindings = b
	bindings.changed.connect(_on_bindings_changed)
	_dirty = true


func _on_bindings_changed() -> void:
	_dirty = true


func _take_queue() -> Array[Dictionary]:
	_refresh()
	var out: Array[Dictionary] = _queue
	_queue = []
	return out


# --- Active set -------------------------------------------------------------------


func _refresh() -> void:
	if not _dirty:
		return
	_dirty = false
	for dev: String in IntentTable.DEVICES:
		var list: Array[Dictionary] = []
		for r: Dictionary in IntentTable.INTENTS:
			if IntentTable.target(r["id"], dev, _focused, _stations) == "":
				continue
			for b: String in bindings.bindings(r["id"], dev):
				var e: Dictionary = _parse(b, dev, r["kind"])
				if not e.is_empty():
					e["id"] = r["id"]
					e["kind"] = r["kind"]
					list.append(e)
		_active[dev] = list


## One binding string as an entry: {"type": "button" | "long" | "seq" | "axis" |
## "pair", "mods": Array[String], "main", "second" (seq), "neg"/"pos" (pair), "sign"
## (axis), "src": the physical inputs it reads}. {} when a name is unknown.
func _parse(binding: String, dev: String, kind: String) -> Dictionary:
	var b: String = binding.strip_edges()
	var e: Dictionary = {"type": "button", "mods": [] as Array[String], "sign": 1.0}
	if b.begins_with("long "):
		e["type"] = "long"
		b = b.substr(5).strip_edges()
	elif kind != IntentTable.AXIS and "," in b and b.length() > 1:
		var steps: PackedStringArray = b.split(",")
		e["type"] = "seq"
		e["main"] = _name(steps[0].strip_edges(), dev)
		e["second"] = _name(steps[1].strip_edges(), dev)
		e["src"] = [e["main"]] as Array[String]
		return e if e["main"] != "" and e["second"] != "" else {}
	var parts: PackedStringArray = b.split("+")
	var main: String = parts[parts.size() - 1].strip_edges()
	for i: int in parts.size() - 1:
		var m: String = _name(parts[i].strip_edges(), dev)
		if m == "":
			return {}
		e["mods"].append(m)
	if kind == IntentTable.AXIS and "/" in main:
		var sides: PackedStringArray = main.split("/")
		e["type"] = "pair"
		e["neg"] = _name(sides[0].strip_edges(), dev)
		e["pos"] = _name(sides[1].strip_edges(), dev)
		e["src"] = _sources(e["neg"]) + _sources(e["pos"])
		return e if e["neg"] != "" and e["pos"] != "" else {}
	if kind == IntentTable.AXIS:
		e["type"] = "axis"
		if main.begins_with("-"):
			e["sign"] = -1.0
			main = main.substr(1)
	e["main"] = _name(main, dev)
	e["src"] = _sources(e["main"])
	return e if e["main"] != "" else {}


## The input name of a binding token on `dev`, or "" when unknown.
func _name(token: String, dev: String) -> String:
	if dev == IntentTable.PAD:
		if _PAD_BUTTONS.has(token) or _PAD_AXES.has(token) or token in ["LS", "RS"]:
			return "p:" + token
		return ""
	if _MOUSE_NAMES.has(token) or token in ["MouseX", "MouseY"]:
		return "m:" + token
	if token == "?":
		return "k:?"
	var code: Key = OS.find_keycode_from_string(token)
	return "" if code == KEY_NONE else "k:%d" % code


## The physical inputs behind a name: a whole stick covers both of its axes.
func _sources(name: String) -> Array[String]:
	if name == "p:LS" or name == "p:RS":
		return [name + "_X", name + "_Y"] as Array[String]
	return [name] as Array[String]


# --- Buttons ----------------------------------------------------------------------


## Keys match on the physical key (layout-independent positions, named after the US
## layout); "?" matches any key press typing "?".
func _key(k: InputEventKey, now_ms: int, out: Array[Dictionary]) -> void:
	_flags(k)
	var code: Key = k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode
	var name: String = "k:%d" % code
	_button(name, k.pressed, IntentTable.KBM, now_ms, out)
	if k.pressed and k.unicode == "?".unicode_at(0):
		_question_key = name
		_button("k:?", true, IntentTable.KBM, now_ms, out)
	elif not k.pressed and name == _question_key:
		_question_key = ""
		_button("k:?", false, IntentTable.KBM, now_ms, out)


func _flags(ev: InputEventWithModifiers) -> void:
	_flag_mods.clear()
	var held: Array[bool] = [ev.shift_pressed, ev.alt_pressed, ev.ctrl_pressed]
	for i: int in _KBM_MODIFIERS.size():
		if held[i]:
			_flag_mods[_name(_KBM_MODIFIERS[i], IntentTable.KBM)] = true


func _held(name: String) -> bool:
	return _down.has(name) or _flag_mods.has(name)


func _all_held(names: Array) -> bool:
	return names.all(func(n: String) -> bool: return _held(n))


func _button(name: String, pressed: bool, dev: String, now_ms: int, out: Array[Dictionary]) -> void:
	device = dev
	if pressed and not _down.has(name):
		_press(name, dev, now_ms, out)
	elif not pressed and _down.has(name):
		_release(name, now_ms, out)


func _press(name: String, dev: String, now_ms: int, out: Array[Dictionary]) -> void:
	_down[name] = now_ms
	_spent.erase(name)
	if not _seq.is_empty():
		var done: Array[Dictionary] = _entries(dev, "seq", _seq["name"], name)
		if not done.is_empty():
			for e: Dictionary in done:
				_tap(e, dev, out)
			_spent[name] = true
			_seq = {}
			return
		_flush_seq(out)
	# Longest chord wins: the matches holding the most modifiers.
	var best: Array[Dictionary] = []
	var most: int = 0
	for e: Dictionary in _entries(dev, "button", name):
		var n: int = e["mods"].size()
		if _all_held(e["mods"]) and n >= most:
			if n > most:
				best.clear()
				most = n
			best.append(e)
	if most > 0:
		for e: Dictionary in best:
			_fire(e, dev, out)
			for m: String in e["mods"]:
				_spent[m] = true
		_spent[name] = true
	elif not _entries(dev, "seq", name).is_empty():
		_seq = {"name": name, "t": now_ms, "dev": dev}
	elif _is_modifier(name, dev) or not _entries(dev, "long", name).is_empty():
		_deferred[name] = {"t": now_ms, "dev": dev}
	else:
		for e: Dictionary in best:
			_fire(e, dev, out)


func _release(name: String, now_ms: int, out: Array[Dictionary]) -> void:
	_down.erase(name)
	if _deferred.has(name):
		var d: Dictionary = _deferred[name]
		_deferred.erase(name)
		if not _spent.has(name) and now_ms - int(d["t"]) < LONG_MS:
			for e: Dictionary in _plain(d["dev"], name):
				_tap(e, d["dev"], out)
	# A hold bound to a chord ends when any of its inputs is released.
	for id: String in _holding.keys():
		if name in _holding[id]["inputs"]:
			out.append(_event(id, _holding[id]["dev"], false))
			_holding.erase(id)
	_spent.erase(name)


## Long presses that came due and sequences that timed out.
func _tick(now_ms: int, out: Array[Dictionary]) -> void:
	for name: String in _deferred:
		var d: Dictionary = _deferred[name]
		if _spent.has(name) or now_ms - int(d["t"]) < LONG_MS:
			continue
		var longs: Array[Dictionary] = _entries(d["dev"], "long", name)
		for e: Dictionary in longs:
			_fire(e, d["dev"], out)
		if not longs.is_empty():
			_spent[name] = true
	if not _seq.is_empty() and now_ms - int(_seq["t"]) > SEQUENCE_MS:
		_flush_seq(out)


## The waiting first button of a sequence fires its own plain bindings.
func _flush_seq(out: Array[Dictionary]) -> void:
	var name: String = _seq["name"]
	var dev: String = _seq["dev"]
	_seq = {}
	for e: Dictionary in _plain(dev, name):
		if _down.has(name):
			_fire(e, dev, out)
		else:
			_tap(e, dev, out)


## Active entries of `type` on `dev` whose main input is `main` (and second step
## `second` for sequences).
func _entries(dev: String, type: String, main: String, second: String = "") -> Array[Dictionary]:
	_refresh()
	var out: Array[Dictionary] = []
	for e: Dictionary in _active[dev]:
		if e["type"] == type and e["main"] == main and (second == "" or e["second"] == second):
			out.append(e)
	return out


func _plain(dev: String, name: String) -> Array[Dictionary]:
	return _entries(dev, "button", name).filter(
		func(e: Dictionary) -> bool: return e["mods"].is_empty()
	)


func _is_modifier(name: String, dev: String) -> bool:
	return _active[dev].any(func(e: Dictionary) -> bool: return name in e["mods"])


## A press or hold starts: press fires once; hold is held until one of the binding's
## inputs is released, or flips when it is a toggle (FT-STN-014).
func _fire(e: Dictionary, dev: String, out: Array[Dictionary]) -> void:
	var id: String = e["id"]
	if e["kind"] == IntentTable.PRESS:
		out.append(_event(id, dev, true))
	elif bindings.is_toggle(id):
		_flip(id, dev, out)
	elif not _holding.has(id):
		var inputs: Array[String] = [e["main"]]
		inputs.append_array(e["mods"])
		_holding[id] = {"inputs": inputs, "dev": dev}
		out.append(_event(id, dev, true))


## A press or hold that fires after its button is already up: a hold pulses.
func _tap(e: Dictionary, dev: String, out: Array[Dictionary]) -> void:
	var id: String = e["id"]
	if e["kind"] == IntentTable.PRESS:
		out.append(_event(id, dev, true))
	elif bindings.is_toggle(id):
		_flip(id, dev, out)
	else:
		out.append(_event(id, dev, true))
		out.append(_event(id, dev, false))


func _flip(id: String, dev: String, out: Array[Dictionary]) -> void:
	if _toggled.has(id):
		_toggled.erase(id)
		out.append(_event(id, dev, false))
	else:
		_toggled[id] = dev
		out.append(_event(id, dev, true))


func _event(id: String, dev: String, pressed: bool) -> Dictionary:
	var r: Dictionary = IntentTable.row(id)
	return {
		"id": id,
		"group": r["group"],
		"target": IntentTable.target(id, dev, _focused, _stations),
		"kind": r["kind"],
		"pressed": pressed,
		"value": 1.0 if pressed else 0.0,
		"device": dev,
	}


# --- Analog -----------------------------------------------------------------------


func _motion(m: InputEventJoypadMotion, now_ms: int, out: Array[Dictionary]) -> void:
	var axis_name: Variant = _PAD_AXES.find_key(m.axis)
	if axis_name == null:
		return
	var name: String = "p:" + str(axis_name)
	_raw[name] = m.axis_value
	# Noise inside the dead zone doesn't switch the device.
	if _analog(name) != 0.0:
		device = IntentTable.PAD
	for b: String in _ANALOG_BUTTONS:
		var on: bool
		if b == "p:LS" or b == "p:RS":
			on = _stick(b).length() > STICK_BUTTON
		else:
			on = float(_raw.get(b, 0.0)) > TRIGGER_DEAD_ZONE
		if on != _down.has(b):
			_button(b, on, IntentTable.PAD, now_ms, out)


## A whole stick ("p:LS"), raw (no dead zone).
func _stick(stick: String) -> Vector2:
	return Vector2(float(_raw.get(stick + "_X", 0.0)), float(_raw.get(stick + "_Y", 0.0)))


## An analog input after its dead zone, rescaled to 0..1 beyond it (S5): sticks use a
## radial dead zone, triggers a linear one.
func _analog(name: String) -> float:
	if name == "p:LT" or name == "p:RT":
		var t: float = float(_raw.get(name, 0.0))
		if t <= TRIGGER_DEAD_ZONE:
			return 0.0
		return (t - TRIGGER_DEAD_ZONE) / (1.0 - TRIGGER_DEAD_ZONE)
	var v: Vector2 = _stick(name.left(4))
	var length: float = v.length()
	if length <= STICK_DEAD_ZONE:
		return 0.0
	var scale: float = minf(1.0, (length - STICK_DEAD_ZONE) / (1.0 - STICK_DEAD_ZONE))
	var scaled: Vector2 = v / length * scale
	return scaled.x if name.ends_with("_X") else scaled.y


## The value of one input as an axis: analog inputs, the mouse stick, or 1/0 for a
## button.
func _value(name: String) -> float:
	if name == "m:MouseX":
		return mouse_stick.value.x
	if name == "m:MouseY":
		return mouse_stick.value.y
	if name.begins_with("p:") and _PAD_AXES.has(name.substr(2)):
		return _analog(name)
	return 1.0 if _held(name) else 0.0


func _axis_value(e: Dictionary, dev: String) -> float:
	if not _all_held(e["mods"]):
		return 0.0
	var n: int = e["mods"].size()
	if e["type"] == "pair":
		var v: float = 0.0
		if not _suppressed(_sources(e["pos"]), n, dev):
			v += _value(e["pos"])
		if not _suppressed(_sources(e["neg"]), n, dev):
			v -= _value(e["neg"])
		return v
	if e["type"] != "axis" or _suppressed(e["src"], n, dev):
		return 0.0
	return e["sign"] * _value(e["main"])


## True when an active binding with more modifiers than `mods`, all held, reads one of
## `src` (longest chord wins: LB+LS_X suppresses LS_X while LB is held).
func _suppressed(src: Array, mods: int, dev: String) -> bool:
	for e: Dictionary in _active[dev]:
		if e["mods"].size() > mods and _all_held(e["mods"]):
			for s: String in e["src"]:
				if s in src:
					return true
	return false
