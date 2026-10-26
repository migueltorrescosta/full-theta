class_name DataToggles
extends RefCounted
## The data-shortcut toggle set of a session (spec §7.2, FT-PAIR-017 to FT-PAIR-020, D84,
## D90, D92): one value per toggle of content/toggles/toggles.tres, taken from a preset and
## changed one toggle at a time in the lobby. The set is locked once a run starts and
## applies to every ship of the session; it is the view key's toggle part
## (StationViews.key), so it travels as a short string, its code:
##   "easy" | "normal" | "hard"      an unedited preset
##   "normal:1011000"                the preset the host started from, then one digit per
##                                   toggle in file order (summaries 0 absent, 1 banded, 2
##                                   exact; the others 0 off, 1 on)
## A set whose digits equal its preset's encodes as the bare preset name. The lobby shows an
## edited set as "<Preset> (custom)"; the threat budget follows the preset (D92).
## Instances are immutable; with_value() returns a changed copy.

const PRESETS: Array[String] = ["easy", "normal", "hard"]

## The toggle file, loaded once when the class loads (read-only after, so both threads read it).
static var _def: DataTogglesDef = load("res://content/toggles/toggles.tres") as DataTogglesDef

## The preset the set started from, and one value per toggle in file order.
var preset: String = "easy"
var values: PackedInt32Array = PackedInt32Array()


## The catalogue of toggles (read-only).
static func def() -> DataTogglesDef:
	return _def


## The ids of the toggles in display order.
static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for t: DataToggleDef in _def.toggles:
		out.append(t.id)
	return out


## The ids of the shortcuts that need a press on their source station (D210): the SHORTCUT
## toggles that move a station's data to another one (not the request chips). Comms' are
## among them since #10 (PROVISIONAL (Q10): the same press as every other shortcut): lanes
## and contract flags from Comms, the verify chip from Science, the mission icon from Relay.
## Engineering and Comms have none (D68).
static func shareable() -> Array[StringName]:
	var out: Array[StringName] = []
	for t: DataToggleDef in _def.toggles:
		if t.kind == DataToggleDef.Kind.SHORTCUT and t.source != &"":  # strand F (Q10)
			out.append(t.id)
	return out


## How long a press keeps the data on the partner (s).
static func share_seconds() -> float:
	return _def.share_seconds


## The toggle's definition, or null.
static func toggle_def(id: StringName) -> DataToggleDef:
	for t: DataToggleDef in _def.toggles:
		if t.id == id:
			return t
	return null


## An unedited preset; an unknown name gives the default preset.
static func of_preset(name: String) -> DataToggles:
	var out: DataToggles = DataToggles.new()
	out.preset = name if PRESETS.has(name) else String(_def.default_preset)
	for t: DataToggleDef in _def.toggles:
		out.values.append(t.value_of(StringName(out.preset)))
	return out


## The set a code names, or null when the code is malformed (an unknown preset, a wrong
## number of digits, a digit above the toggle's maximum).
static func parse(code: String) -> DataToggles:
	var head: String = code.get_slice(":", 0)
	if not PRESETS.has(head):
		return null
	var out: DataToggles = of_preset(head)
	if not code.contains(":"):
		return out
	var digits: String = code.get_slice(":", 1)
	if code.count(":") != 1 or digits.length() != out.values.size():
		return null
	for i: int in digits.length():
		var ch: String = digits[i]
		if not ch.is_valid_int() or ch.to_int() > _def.toggles[i].max_value():
			return null
		out.values[i] = ch.to_int()
	return out


static func is_valid(code: String) -> bool:
	return parse(code) != null


## The code: the bare preset when nothing was edited.
func encode() -> String:
	if not is_custom():
		return preset
	var digits: String = ""
	for v: int in values:
		digits += str(v)
	return "%s:%s" % [preset, digits]


## Whether any toggle differs from the preset's value.
func is_custom() -> bool:
	for i: int in values.size():
		if values[i] != _def.toggles[i].value_of(StringName(preset)):
			return true
	return false


## The value of a toggle, or -1 for an unknown id.
func value(id: StringName) -> int:
	for i: int in _def.toggles.size():
		if _def.toggles[i].id == id:
			return values[i]
	return -1


## Whether a toggle is on (a SUMMARY toggle: not absent).
func on(id: StringName) -> bool:
	return value(id) > 0


## The summaries toggle: 0 absent, 1 banded, 2 exact (FT-PAIR-019).
func summaries() -> int:
	return maxi(0, value(&"summaries"))


## A copy with one toggle set; the same set for an unknown id or an out-of-range value.
func with_value(id: StringName, v: int) -> DataToggles:
	var out: DataToggles = DataToggles.new()
	out.preset = preset
	out.values = values.duplicate()
	for i: int in _def.toggles.size():
		if _def.toggles[i].id == id and v >= 0 and v <= _def.toggles[i].max_value():
			out.values[i] = v
	return out
