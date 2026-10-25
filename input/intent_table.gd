class_name IntentTable
extends RefCounted
## The one binding table (FT-JNT-002, FT-STN-009, D95): every intent of every station
## and view, with its group, kind, default KB/M and controller bindings and the
## translation key the Controls tab shows (FT-STN-011). Stations, joint views and
## the overlay all read this table; a station's bindings are the same in every view
## that contains it because there is only this table. Bindings (bindings.gd) layers the
## player's rebinds and hold-to-toggle choices on top (FT-STN-007, FT-STN-014).
##
## Row fields:
## - `id`: the intent (StringName-compatible String), unique.
## - `group`: "common" (the §5.0 common actions: the screen's selection, marks, pings,
##   requests, claims, overlay), "live" (the always-live set that has no station: alert,
##   ping, panel switch), or a station or seat id (helm, weapons, engineering, science,
##   relay, comms, viewer): the panel of that station handles it.
## - `kind`: "press" (one-shot), "hold" (active while held; a player may switch it to
##   a toggle, FT-STN-014) or "axis" (a value in -1..1, polled).
## - `kbm`, `pad`: default bindings, grammar in input/README.md ("Alt+A", "Shift+MMB",
##   "long RB", "View+X", "B,2", "S/W", "LB+LS_X", "-RS_Y", "MouseX").
## - `live`: devices ("kbm", "pad") on which a station intent ignores panel focus
##   (§5.0 always-live: Helm translation on KB/M only, face and all-stop on both,
##   FT-JNT-007). Rows of group "live" are live on every device.
## - `pitch`: true for the pitch axis the "invert pitch" setting flips.
## - `via`: focused station -> devices on which this station intent still reaches its
##   own panel when that station has the focus (§5.9, FT-JNT-008: in Tactical's cockpit
##   the KB/M fire buttons fire the claimed mounts at the selected target).
## Translation key: "intent.<id>" (content/i18n/strings.json).
##
## Adding an intent: one row here, its "intent.<id>" key in every language of
## strings.json, and a handler in the panel of its group (StationPanel.handle_intent).

const KBM: String = "kbm"
const PAD: String = "pad"
const DEVICES: Array[String] = [KBM, PAD]

const PRESS: String = "press"
const HOLD: String = "hold"
const AXIS: String = "axis"

const COMMON: String = "common"
const LIVE: String = "live"
const GROUPS: Array[String] = [
	COMMON, LIVE, "helm", "weapons", "engineering", "science", "relay", "comms", "captain", "viewer"
]

# gdlint: disable=max-line-length
const INTENTS: Array[Dictionary] = [
	# §5.0 common actions (D95): the same binding on every station.
	{"id": "select", "group": COMMON, "kind": PRESS, "kbm": ["LMB"], "pad": ["A"]},
	{"id": "cycle_target", "group": COMMON, "kind": PRESS, "kbm": ["T"], "pad": ["RB"]},
	{"id": "select_pinged", "group": COMMON, "kind": PRESS, "kbm": ["Y"], "pad": ["long RB"]},
	{"id": "mark", "group": COMMON, "kind": PRESS, "kbm": ["Shift+MMB"], "pad": ["long R3"]},
	{"id": "accept", "group": COMMON, "kind": PRESS, "kbm": ["Enter"], "pad": ["X"]},
	{"id": "decline", "group": COMMON, "kind": PRESS, "kbm": ["Backspace"], "pad": ["Y"]},
	# A request chip (§7.4).
	{"id": "request", "group": COMMON, "kind": PRESS, "kbm": ["B"], "pad": ["View+Y"]},
	# Share the screen's data shortcuts with their partner stations (§7.2, D210).
	{"id": "share", "group": COMMON, "kind": PRESS, "kbm": ["Alt+S"], "pad": ["View+RT"]},
	# The radar's elevation side strip (FT-SPA-009; off B, owner decision in #7).
	{"id": "radar_strip", "group": COMMON, "kind": PRESS, "kbm": ["Z"], "pad": ["View+Left"]},
	{"id": "claim", "group": COMMON, "kind": PRESS, "kbm": ["K"], "pad": ["View+X"]},
	{"id": "overlay", "group": COMMON, "kind": PRESS, "kbm": ["?"], "pad": ["View"]},
	{"id": "menu", "group": COMMON, "kind": PRESS, "kbm": ["Escape"], "pad": ["Menu"]},
	# Always-live set (§5.0, FT-JNT-007).
	{"id": "ping", "group": LIVE, "kind": PRESS, "kbm": ["MMB"], "pad": ["R3"]},
	{"id": "alert_cycle", "group": LIVE, "kind": PRESS, "kbm": ["Alt+A"], "pad": []},
	{"id": "alert_red", "group": LIVE, "kind": PRESS, "kbm": [], "pad": ["View+Up"]},
	{"id": "alert_yellow", "group": LIVE, "kind": PRESS, "kbm": [], "pad": ["View+Right"]},
	{"id": "alert_normal", "group": LIVE, "kind": PRESS, "kbm": [], "pad": ["View+Down"]},
	# Panel 1 / 2; with more panels (the dev entry) previous / next.
	{"id": "focus_1", "group": LIVE, "kind": PRESS, "kbm": ["F1"], "pad": ["View+LB"]},
	{"id": "focus_2", "group": LIVE, "kind": PRESS, "kbm": ["F2"], "pad": ["View+RB"]},
	# Helm (§5.1). Translation is live on KB/M only; face and all-stop on both.
	{
		"id": "helm_surge",
		"group": "helm",
		"kind": AXIS,
		"kbm": ["S/W"],
		"pad": ["LT/RT"],
		"live": [KBM]
	},
	{
		"id": "helm_sway",
		"group": "helm",
		"kind": AXIS,
		"kbm": ["A/D"],
		"pad": ["RS_X"],
		"live": [KBM]
	},
	{
		"id": "helm_heave",
		"group": "helm",
		"kind": AXIS,
		"kbm": ["V/R"],
		"pad": ["-RS_Y"],
		"live": [KBM]
	},
	{
		"id": "helm_pitch",
		"group": "helm",
		"kind": AXIS,
		"kbm": ["MouseY"],
		"pad": ["LS_Y"],
		"pitch": true
	},
	{"id": "helm_yaw", "group": "helm", "kind": AXIS, "kbm": ["MouseX"], "pad": ["LS_X"]},
	{"id": "helm_roll", "group": "helm", "kind": AXIS, "kbm": ["Q/E"], "pad": ["LB+LS_X"]},
	{
		"id": "all_stop",
		"group": "helm",
		"kind": PRESS,
		"kbm": ["Space"],
		"pad": ["View+B"],
		"live": [KBM, PAD]
	},
	{"id": "face", "group": "helm", "kind": HOLD, "kbm": ["F"], "pad": ["L3"], "live": [KBM, PAD]},
	{"id": "approach", "group": "helm", "kind": HOLD, "kbm": ["X"], "pad": ["B"]},
	{"id": "decoupled", "group": "helm", "kind": PRESS, "kbm": ["Tab"], "pad": []},
	{"id": "align", "group": "helm", "kind": PRESS, "kbm": ["L"], "pad": []},
	{"id": "chase_camera", "group": "helm", "kind": PRESS, "kbm": ["C"], "pad": []},
	{"id": "dock", "group": "helm", "kind": PRESS, "kbm": ["H"], "pad": []},
	{"id": "jump", "group": "helm", "kind": PRESS, "kbm": ["J"], "pad": []},
	{"id": "shield_track", "group": "helm", "kind": PRESS, "kbm": ["G"], "pad": []},
	# Hold View + right stick: dock, jump, ping, chase camera, Align, decoupled, shield
	# track (the Helm panel reads the stick while it is held).
	{"id": "helm_radial", "group": "helm", "kind": HOLD, "kbm": [], "pad": ["View+RS"]},
	# While held, the mouse stops steering and shows the pointer (shield ring, radar).
	{"id": "helm_pointer", "group": "helm", "kind": HOLD, "kbm": ["Ctrl"], "pad": []},
	{"id": "shield_fore", "group": "helm", "kind": PRESS, "kbm": ["Kp 1"], "pad": ["Up"]},
	{"id": "shield_aft", "group": "helm", "kind": PRESS, "kbm": ["Kp 2"], "pad": ["Down"]},
	{"id": "shield_port", "group": "helm", "kind": PRESS, "kbm": ["Kp 3"], "pad": ["Left"]},
	{"id": "shield_starboard", "group": "helm", "kind": PRESS, "kbm": ["Kp 4"], "pad": ["Right"]},
	{"id": "shield_dorsal", "group": "helm", "kind": PRESS, "kbm": ["Kp 5"], "pad": ["LB+Up"]},
	{"id": "shield_ventral", "group": "helm", "kind": PRESS, "kbm": ["Kp 6"], "pad": ["LB+Down"]},
	# Weapons (§5.2).
	{
		"id": "fire",
		"group": "weapons",
		"kind": HOLD,
		"kbm": ["LMB"],
		"pad": ["RT"],
		"via": {"helm": [KBM]}
	},
	{
		"id": "fire_all",
		"group": "weapons",
		"kind": HOLD,
		"kbm": ["RMB"],
		"pad": ["LT"],
		"via": {"helm": [KBM]}
	},
	{"id": "aim_x", "group": "weapons", "kind": AXIS, "kbm": ["MouseX"], "pad": ["RS_X"]},
	{
		"id": "aim_y",
		"group": "weapons",
		"kind": AXIS,
		"kbm": ["MouseY"],
		"pad": ["RS_Y"],
		"pitch": true
	},
	{"id": "mount_1", "group": "weapons", "kind": PRESS, "kbm": ["1"], "pad": []},
	{"id": "mount_2", "group": "weapons", "kind": PRESS, "kbm": ["2"], "pad": []},
	{"id": "mount_3", "group": "weapons", "kind": PRESS, "kbm": ["3"], "pad": []},
	{"id": "mount_4", "group": "weapons", "kind": PRESS, "kbm": ["4"], "pad": []},
	{"id": "mount_prev", "group": "weapons", "kind": PRESS, "kbm": [], "pad": ["Left"]},
	{"id": "mount_next", "group": "weapons", "kind": PRESS, "kbm": [], "pad": ["Right"]},
	{"id": "ammo_next", "group": "weapons", "kind": PRESS, "kbm": ["Q"], "pad": ["Up"]},
	{"id": "ammo_prev", "group": "weapons", "kind": PRESS, "kbm": [], "pad": ["Down"]},
	{"id": "fire_guided", "group": "weapons", "kind": PRESS, "kbm": ["G"], "pad": ["LB"]},
	# Engineering (§5.3).
	{"id": "subsystem_1", "group": "engineering", "kind": PRESS, "kbm": ["1"], "pad": []},
	{"id": "subsystem_2", "group": "engineering", "kind": PRESS, "kbm": ["2"], "pad": []},
	{"id": "subsystem_3", "group": "engineering", "kind": PRESS, "kbm": ["3"], "pad": []},
	{"id": "subsystem_4", "group": "engineering", "kind": PRESS, "kbm": ["4"], "pad": []},
	{"id": "subsystem_5", "group": "engineering", "kind": PRESS, "kbm": ["5"], "pad": []},
	{"id": "subsystem_6", "group": "engineering", "kind": PRESS, "kbm": ["6"], "pad": []},
	{"id": "subsystem_prev", "group": "engineering", "kind": PRESS, "kbm": [], "pad": ["Left"]},
	{"id": "subsystem_next", "group": "engineering", "kind": PRESS, "kbm": [], "pad": ["Right"]},
	{
		"id": "pip_add",
		"group": "engineering",
		"kind": PRESS,
		"kbm": ["Equal", "Kp Add", "WheelUp"],
		"pad": ["RT"]
	},
	{
		"id": "pip_remove",
		"group": "engineering",
		"kind": PRESS,
		"kbm": ["Minus", "Kp Subtract", "WheelDown"],
		"pad": ["LT"]
	},
	{"id": "harden", "group": "engineering", "kind": PRESS, "kbm": ["H"], "pad": ["LB"]},
	{"id": "fabricate_probe", "group": "engineering", "kind": PRESS, "kbm": ["P"], "pad": ["Up"]},
	{"id": "dispatch_nearest", "group": "engineering", "kind": PRESS, "kbm": [], "pad": ["B"]},
	# Cycle the cause picked for the selected subsystem's unknown fault (FT-ENG-006).
	{
		"id": "cause_next",
		"group": "engineering",
		"kind": PRESS,
		"kbm": ["Semicolon"],
		"pad": ["Down"]
	},
	{
		"id": "shield_tighter",
		"group": "engineering",
		"kind": PRESS,
		"kbm": ["Period"],
		"pad": ["LB+Up"]
	},
	{
		"id": "shield_wider",
		"group": "engineering",
		"kind": PRESS,
		"kbm": ["Comma"],
		"pad": ["LB+Down"]
	},
	{"id": "boost", "group": "engineering", "kind": PRESS, "kbm": ["O"], "pad": ["LB+RT"]},
	{"id": "eng_cursor_x", "group": "engineering", "kind": AXIS, "kbm": [], "pad": ["LS_X"]},
	{"id": "eng_cursor_y", "group": "engineering", "kind": AXIS, "kbm": [], "pad": ["LS_Y"]},
	{"id": "cutaway_yaw", "group": "engineering", "kind": AXIS, "kbm": [], "pad": ["RS_X"]},
	{"id": "cutaway_pitch", "group": "engineering", "kind": AXIS, "kbm": [], "pad": ["RS_Y"]},
	# Science (§5.4, E01). The dials turn the open axes of a scan and the arrows move a
	# hack's route; outside a minigame the left stick is the cursor and the right stick
	# orbits the radar (the panel reads the same axes by state). The d-pad also moves a
	# hack's route. Drags on the radar and the minigames are their own pointer handling.
	{"id": "sci_scan", "group": "science", "kind": PRESS, "kbm": ["E"], "pad": ["RT"]},
	{"id": "sci_hack", "group": "science", "kind": PRESS, "kbm": ["H"], "pad": ["LT"]},
	{"id": "sci_ping", "group": "science", "kind": PRESS, "kbm": ["P"], "pad": ["Up"]},
	{"id": "sci_scan_mark", "group": "science", "kind": PRESS, "kbm": ["M"], "pad": ["Down"]},
	{"id": "sci_mode", "group": "science", "kind": PRESS, "kbm": ["Q"], "pad": ["LB"]},
	{"id": "sci_self_scan", "group": "science", "kind": PRESS, "kbm": ["Home"], "pad": ["LB+Down"]},
	{
		"id": "sci_sub_prev",
		"group": "science",
		"kind": PRESS,
		"kbm": ["BracketLeft"],
		"pad": ["Left"]
	},
	{
		"id": "sci_sub_next",
		"group": "science",
		"kind": PRESS,
		"kbm": ["BracketRight"],
		"pad": ["Right"]
	},
	{"id": "sci_up", "group": "science", "kind": PRESS, "kbm": ["Up"], "pad": []},
	{"id": "sci_down", "group": "science", "kind": PRESS, "kbm": ["Down"], "pad": []},
	{"id": "sci_left", "group": "science", "kind": PRESS, "kbm": ["Left"], "pad": []},
	{"id": "sci_right", "group": "science", "kind": PRESS, "kbm": ["Right"], "pad": []},
	{"id": "sci_dial_1", "group": "science", "kind": AXIS, "kbm": ["Left/Right"], "pad": ["LS_X"]},
	{"id": "sci_dial_2", "group": "science", "kind": AXIS, "kbm": ["Down/Up"], "pad": ["LS_Y"]},
	{"id": "sci_dial_3", "group": "science", "kind": AXIS, "kbm": ["Minus/Equal"], "pad": ["RS_X"]},
	{"id": "sci_orbit_y", "group": "science", "kind": AXIS, "kbm": [], "pad": ["RS_Y"]},
	# Relay (§5.5); drags on the map (place, Shift+drag depth, right-drag rotate) are
	# the map's own pointer handling.
	{"id": "route", "group": "relay", "kind": PRESS, "kbm": ["G"], "pad": ["LB+Up"]},
	{"id": "route_clear", "group": "relay", "kind": PRESS, "kbm": ["Shift+G"], "pad": []},
	{"id": "flag_lanes", "group": "relay", "kind": PRESS, "kbm": ["L"], "pad": ["LB+Down"]},
	# Probes and hazards: with something selected they go to it, else the next click on
	# the map places them (strand B of #9).
	{"id": "probe_launch", "group": "relay", "kind": PRESS, "kbm": ["P"], "pad": ["Right"]},
	{"id": "hazard_add", "group": "relay", "kind": PRESS, "kbm": ["H"], "pad": ["LB+Right"]},
	{"id": "mark_delete", "group": "relay", "kind": PRESS, "kbm": ["Delete"], "pad": ["Down"]},
	{"id": "mark_rename", "group": "relay", "kind": PRESS, "kbm": ["N"], "pad": []},
	# Attach the selected mark to the nearest contact, or free it where it is.
	{"id": "mark_attach", "group": "relay", "kind": PRESS, "kbm": ["M"], "pad": ["Up"]},
	# Centre the map on the selection, or back on the ship.
	{"id": "map_centre", "group": "relay", "kind": PRESS, "kbm": ["C"], "pad": ["Left"]},
	{"id": "mark_send", "group": "relay", "kind": PRESS, "kbm": ["X"], "pad": ["LB+Left"]},
	{"id": "relay_radial", "group": "relay", "kind": HOLD, "kbm": [], "pad": ["long B"]},
	{"id": "relay_cursor_x", "group": "relay", "kind": AXIS, "kbm": [], "pad": ["LS_X"]},
	{"id": "relay_cursor_y", "group": "relay", "kind": AXIS, "kbm": [], "pad": ["LS_Y"]},
	{"id": "relay_depth", "group": "relay", "kind": AXIS, "kbm": [], "pad": ["LT/RT"]},
	{"id": "relay_rotate_x", "group": "relay", "kind": AXIS, "kbm": [], "pad": ["RS_X"]},
	{"id": "relay_rotate_y", "group": "relay", "kind": AXIS, "kbm": [], "pad": ["RS_Y"]},
	{"id": "main_view_1", "group": "relay", "kind": PRESS, "kbm": ["Alt+1"], "pad": []},
	{"id": "main_view_2", "group": "relay", "kind": PRESS, "kbm": ["Alt+2"], "pad": []},
	{"id": "main_view_3", "group": "relay", "kind": PRESS, "kbm": ["Alt+3"], "pad": []},
	{"id": "main_view_4", "group": "relay", "kind": PRESS, "kbm": ["Alt+4"], "pad": []},
	{"id": "main_view_5", "group": "relay", "kind": PRESS, "kbm": ["Alt+5"], "pad": []},
	# Captain (§5.7, strand F): the main screen's view, 1 to 5 or the d-pad.
	{"id": "captain_view_1", "group": "captain", "kind": PRESS, "kbm": ["1"], "pad": []},
	{"id": "captain_view_2", "group": "captain", "kind": PRESS, "kbm": ["2"], "pad": []},
	{"id": "captain_view_3", "group": "captain", "kind": PRESS, "kbm": ["3"], "pad": []},
	{"id": "captain_view_4", "group": "captain", "kind": PRESS, "kbm": ["4"], "pad": []},
	{"id": "captain_view_5", "group": "captain", "kind": PRESS, "kbm": ["5"], "pad": []},
	{
		"id": "captain_view_next",
		"group": "captain",
		"kind": PRESS,
		"kbm": ["Tab"],
		"pad": ["Right"]
	},
	{"id": "captain_view_prev", "group": "captain", "kind": PRESS, "kbm": [], "pad": ["Left"]},
	# Science and Comms are placeholders in M1 (FT-M1-005): no bindings yet (#9, #10).
]
# gdlint: enable=max-line-length

static var _by_id: Dictionary = _index()


## The row of `id`, or {} for an unknown id. Read-only.
static func row(id: String) -> Dictionary:
	return _by_id.get(id, {})


static func has(id: String) -> bool:
	return _by_id.has(id)


## Ids of a group, in table order.
static func ids_of(group: String) -> Array[String]:
	var out: Array[String] = []
	for r: Dictionary in INTENTS:
		if r["group"] == group:
			out.append(r["id"])
	return out


## The overlay's translation key of an intent.
static func label_key(id: String) -> String:
	return "intent." + id


## Default bindings of `id` on `device` (a copy).
static func defaults(id: String, device: String) -> PackedStringArray:
	return PackedStringArray(row(id).get(device, []))


## True when `id` acts whatever panel has focus on `device` (FT-JNT-007).
static func is_live(id: String, device: String) -> bool:
	var r: Dictionary = row(id)
	if r.is_empty():
		return false
	return r["group"] == LIVE or device in r.get("live", [])


## Who handles intent `id` from `device` on a screen holding `stations` with
## `focused` focused (D95, FT-JNT-001, FT-JNT-007, FT-JNT-008): "screen" for common and
## station-less live intents, the station id for a station intent that is live on the
## device (whatever the focus), reaches it `via` the focused station, or belongs to the
## focused panel, "" when nobody does.
static func target(id: String, device: String, focused: String, stations: Array) -> String:
	var r: Dictionary = row(id)
	if r.is_empty():
		return ""
	var group: String = r["group"]
	if group == COMMON or group == LIVE:
		return "screen"
	if group not in stations:
		return ""
	if group == focused or device in r.get("live", []):
		return group
	if device in r.get("via", {}).get(focused, []):
		return group
	return ""


static func _index() -> Dictionary:
	var out: Dictionary = {}
	for r: Dictionary in INTENTS:
		out[r["id"]] = r
	return out
