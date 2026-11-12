class_name ControlsModel
extends RefCounted
## What the controls diagram shows for one device (FT-STN-011, D185): every binding of
## every intent in IntentTable, read through Bindings so a rebind shows at once, each
## with the parts of the hardware it lands on. Nothing here draws: ControlsDiagram does,
## and tests read this.
##
## An entry is {"id", "group", "binding", "keys", "label", "parts", "emphasis"}: one per
## binding string of an intent on the device; `parts` are ids of ControlsFigure (the
## last key of a chord, both sides of "S/W", the stick under "LS_X"), empty when the
## binding names something the drawing has no part for (a rebind to a punctuation key);
## `emphasis` is "station" (the intent belongs to a station of the screen), "common"
## (the common actions and the always-live set) or "other". An intent with nothing
## bound on the device is in `unbound` instead, so every intent appears once or more.

const STATION: String = "station"
const COMMON: String = "common"
const OTHER: String = "other"
## The binding the matcher accepts from any key that types it (input/README.md).
const TYPED: String = "?"

## Stick and click tokens that sit on one drawn stick, and spelled-out key names.
const ALIASES: Dictionary = {
	"L3": "LS",
	"R3": "RS",
	"LS_X": "LS",
	"LS_Y": "LS",
	"RS_X": "RS",
	"RS_Y": "RS",
	"MouseX": "Mouse",
	"MouseY": "Mouse",
}

var device: String = IntentTable.KBM
var entries: Array[Dictionary] = []
## Intent ids with no binding on the device.
var unbound: Array[String] = []

var _stations: Array = []


## Reads `bindings` for `device`; `stations` are the station ids of the screen.
func build(bindings: Bindings, stations: Array, p_device: String) -> void:
	device = p_device
	_stations = stations
	entries.clear()
	unbound.clear()
	var known: Dictionary = ControlsFigure.ids(device)
	for r: Dictionary in IntentTable.INTENTS:
		var id: String = r["id"]
		var list: PackedStringArray = bindings.bindings(id, device)
		if list.is_empty():
			unbound.append(id)
		for b: String in list:
			var keys: String = BindingText.describe(b)
			if bindings.is_toggle(id):
				keys += " " + _tr("overlay.toggle")
			var entry: Dictionary = {
				"id": id,
				"group": r["group"],
				"binding": b,
				"keys": keys,
				"label": _tr(IntentTable.label_key(id)),
				"parts": parts_of(b, known),
				"emphasis": emphasis_of(str(r["group"])),
			}
			entries.append(entry)


func emphasis_of(group: String) -> String:
	if group in _stations:
		return STATION
	return COMMON if group in [IntentTable.COMMON, IntentTable.LIVE] else OTHER


## The part ids `binding` lands on among `known`: the key of a chord, each side of a
## "/" pair, each item of a "," list, without "long ", "-" or modifiers. Tokens the
## drawing lacks are dropped.
static func parts_of(binding: String, known: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var b: String = binding.strip_edges().trim_prefix("long ")
	var items: PackedStringArray = b.split(",") if b.length() > 1 else PackedStringArray([b])
	for item: String in items:
		var main: String = item.strip_edges().split("+")[-1] if item.length() > 1 else item
		for token: String in main.split("/"):
			var t: String = token.strip_edges().trim_prefix("-")
			t = ALIASES.get(t, t)
			if known.has(t) and t not in out:
				out.append(t)
	return out


## Entries touching part `id`.
func on_part(id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in entries:
		if id in e["parts"]:
			out.append(e)
	return out


## Entries with no part on the drawing.
func unmapped() -> Array[Dictionary]:
	return entries.filter(
		func(e: Dictionary) -> bool: return e["parts"].is_empty() and e["binding"] != TYPED
	)


## Entries bound to the typed "?" (R25-14): any key that types it on the player's layout,
## so the drawing has no place for it and the note names it instead.
func typed() -> Array[Dictionary]:
	return entries.filter(func(e: Dictionary) -> bool: return e["binding"] == TYPED)


## Ids of the screen's stations' and the common intents that have no binding here and no
## other route either (`covered`).
func unbound_here() -> Array[String]:
	return unbound.filter(
		func(id: String) -> bool:
			return emphasis_of(IntentTable.row(id)["group"]) != OTHER and not covered(id)
	)


## True when the unbound intent `id` is reached another way on this device (D1, R25-12): an
## item of the Helm radial (pad), a sibling of the same family that is bound (alert_red by
## the alert cycle or the other levels; mount_3 by mount_prev / mount_next on a pad, and the
## other way round on a keyboard: `family`), a radial on a keyboard (its items have keys of
## their own), or an axis on a keyboard (the mouse drags it on the station's view).
func covered(id: String) -> bool:
	if id not in unbound:
		return false
	if device == IntentTable.PAD and id in HelmPanel.RADIAL:
		return "helm_radial" not in unbound
	if (
		device == IntentTable.KBM
		and (id.ends_with("_radial") or IntentTable.row(id)["kind"] == IntentTable.AXIS)
	):
		return true
	for other: String in family(id):
		if other != id and other not in unbound:
			return true
	return false


## The intents that reach the same things as `id`: the alert levels and cycle, or a numbered
## set with its previous / next ("mount_1" .. "mount_4", "mount_prev", "mount_next"); [] for
## any other intent.
static func family(id: String) -> Array[String]:
	var out: Array[String] = []
	var stem: String = "alert_" if id.begins_with("alert_") else ""
	if stem == "":
		var tail: String = id.get_slice("_", id.get_slice_count("_") - 1)
		if tail in ["prev", "next"] or tail.is_valid_int():
			stem = id.left(id.length() - tail.length())
	if stem == "":
		return out
	for r: Dictionary in IntentTable.INTENTS:
		var other: String = r["id"]
		if not other.begins_with(stem) or r["group"] != IntentTable.row(id)["group"]:
			continue
		var rest: String = other.substr(stem.length())
		if stem == "alert_" or rest in ["prev", "next"] or rest.is_valid_int():
			out.append(other)
	return out


## The screen's unbound intents that sit in the Helm radial, in the radial's order.
func radial_here() -> Array[String]:
	var out: Array[String] = []
	for id: String in HelmPanel.RADIAL:
		if id in unbound and covered(id) and emphasis_of("helm") != OTHER:
			out.append(id)
	return out


## The intents with a callout: the screen's stations and the common ones, on a drawn part.
func callouts() -> Array[Dictionary]:
	return entries.filter(
		func(e: Dictionary) -> bool: return e["emphasis"] != OTHER and not e["parts"].is_empty()
	)


static func _tr(key: String) -> String:
	return str(TranslationServer.translate(key))
