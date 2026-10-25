class_name StationAlerts
extends Node
## Event notifications on a station screen (T056, FT-STN-004, FT-SIM-032, FT-M1-011): the
## own ship's hits, subsystem faults, low shields and collision warnings show as a toast
## and a screen-edge flash, and sound a tone (AlertTones, its own bus, FT-AUD-009), on the
## stations they affect. The tone audiences match the ship computer's spoken lines
## (ServerVoice.LINES, owner-approved in #7); a fault also shows, without a tone, on the
## station that depends on the failed subsystem (FT-SIM-032). Pings chime (FT-SPA-016)
## and an alert-level change sounds its level's tone and flashes its colour, on every
## screen of the ship.

## Sim event kind -> [stations that see and hear it ([] for every screen), toast and
## flash palette role, optionally the tone to play].
const ROUTES: Dictionary = {
	&"hit": [[], "danger"],
	&"shield_low": [["helm", "engineering"], "warn"],
	&"fault": [["engineering"], "warn"],
	&"proximity": [["helm"], "danger"],
	# Weapons is warned before a shot along a lane Relay flagged (FT-RLY-011), with the
	# proximity tone (the third entry is the tone, when it isn't the event's own).
	&"lane_warning": [["weapons"], "danger", &"proximity"],
}
## Fault tag (the subsystem id, content/ships/) -> stations that depend on it and see
## its fault (FT-SIM-032). PROVISIONAL.
const DEPENDS: Dictionary = {
	&"engines": ["helm"],
	&"thrusters": ["helm"],
	&"shields": ["helm"],
	&"weapons": ["weapons"],
	&"sensors": ["science", "relay"],
}
## Subsystem ids with their own fault toast (alerts.fault.<id>); others say alerts.fault.
const FAULT_KEYS: Array[String] = [
	"engines", "thrusters", "weapons", "shields", "sensors", "reactor"
]
## A toast of the same kind within this gap is skipped (ms): hits and the repeating
## proximity warning still flash and sound, without filling the toast column.
const TOAST_GAP_MS: int = 2500

var ctx: StationContext
var stations: Array[String] = []
var toasts: Toasts
var flash: AlertFlash
var tones: AlertTones

var _level: int = CrewState.ALERT_NORMAL
var _toast_ms: Dictionary = {}


func setup(
	context: StationContext, station_ids: Array[String], toast_box: Toasts, edge: AlertFlash
) -> void:
	ctx = context
	stations = station_ids
	toasts = toast_box
	flash = edge
	_level = ctx.crew.alert
	tones = AlertTones.new()
	add_child(tones)
	ctx.crew.sim_event.connect(on_sim_event)
	ctx.crew.pinged.connect(func(_p: Dictionary) -> void: tones.play(&"ping", ctx.now_ms()))
	ctx.crew.changed.connect(_on_crew_changed)


## A sim event (docs/protocol.md "Events": payload {ship, faction, other, value, vector,
## tag}); only the own ship's count.
func on_sim_event(kind: StringName, p: Dictionary) -> void:
	if not ROUTES.has(kind) or int(p.get("ship", -1)) != ctx.crew.ship:
		return
	var route: Array = ROUTES[kind]
	var audible: bool = _covers(route[0])
	var visible_here: bool = audible
	if kind == &"fault":
		visible_here = audible or _covers(DEPENDS.get(StringName(str(p.get("tag", ""))), ["-"]))
	if not visible_here:
		return
	var now: int = ctx.now_ms()
	var role: String = route[1]
	flash.flash(Palette.color(role), now)
	if now - int(_toast_ms.get(kind, -TOAST_GAP_MS)) >= TOAST_GAP_MS:
		_toast_ms[kind] = now
		toasts.push(_text(kind, p), role, now)
	if audible:
		tones.play(route[2] if route.size() > 2 else kind, now)


func _on_crew_changed(what: StringName) -> void:
	if what == &"reset":
		_level = ctx.crew.alert
	if what != &"alert" or ctx.crew.alert == _level:
		return
	_level = ctx.crew.alert
	# The state sent after Welcome or a reset has no setter: no tone (docs/protocol.md).
	if ctx.crew.alert_by == "":
		return
	var style: Dictionary = Palette.alert(_level)
	flash.flash(Palette.color(style["role"]), ctx.now_ms())
	tones.play(StringName(style["role"]), ctx.now_ms())


## Whether this screen holds one of `who`'s stations ([] means every screen).
func _covers(who: Array) -> bool:
	if who.is_empty():
		return true
	for s: String in stations:
		if who.has(s):
			return true
	return false


func _text(kind: StringName, p: Dictionary) -> String:
	match kind:
		&"hit":
			var v: Vector3 = p.get("vector", Vector3.ZERO)
			return tr("alerts.hit").format({"dir": _direction(v)})
		&"shield_low":
			# An absent summary (Hard) arrives as 0: the alert without a number (D224).
			var pct: int = roundi(float(p.get("value", 0)) * 100.0)
			if pct <= 0:
				return tr("alerts.shield_low_plain")
			return tr("alerts.shield_low").format({"pct": pct})
		&"fault":
			var tag: String = str(p.get("tag", ""))
			return tr("alerts.fault." + tag if FAULT_KEYS.has(tag) else "alerts.fault")
	return tr("alerts." + String(kind))


## "4 high" in the session language (ship frame, FT-SPA-003).
static func _direction(local: Vector3) -> String:
	var words: PackedStringArray = Callout.clock_height(local).split(" ")
	words[-1] = String(TranslationServer.translate("callout." + words[-1]))
	return " ".join(words)
