class_name StationAlerts
extends Node
## Event notifications on a station screen (T056, FT-STN-004, FT-SIM-032, FT-M1-011) in two
## tiers (C5, ux-12). The critical tier, a hull at or under 25 %, a subsystem fault, shields
## down and a missile lock, shows as the CriticalBanner with a screen-edge flash, and the ship
## computer says it (ServerVoice); nothing else flashes. The rest (hits, collision and lane
## warnings, alert-level changes) is a toast. Each sounds a tone (AlertTones, its own bus,
## FT-AUD-009) on the stations it affects. The tone audiences match the ship computer's
## spoken lines (ServerVoice.LINES, owner-approved in #7); a fault also shows, without a tone,
## on the station that depends on the failed subsystem (FT-SIM-032). Pings chime
## (FT-SPA-016) and an alert-level change sounds its level's tone, on every screen of the
## ship. "Shields down" is the sim's low-shield alert: the shield is one lobe, with no face
## of its own to fail. The server derives hull_critical and missile_lock (ServerVoice).

## Sim event kind -> [stations that see and hear it ([] for every screen), toast, banner and
## flash palette role, optionally the tone to play].
const ROUTES: Dictionary = {
	&"hit": [[], "danger"],
	&"proximity": [["helm"], "danger"],
	# Weapons is warned before a shot along a lane Relay flagged (FT-RLY-011), with the
	# proximity tone (the third entry is the tone, when it isn't the event's own).
	&"lane_warning": [["weapons"], "danger", &"proximity"],
	&"hull_critical": [[], "danger", &"alert_red"],
	&"missile_lock": [[], "danger", &"alert_red"],
	&"shield_low": [["helm", "engineering"], "danger"],
	&"fault": [["engineering"], "danger"],
	# Fail-forward and the economy (gp-09, gp-11): Helm and the Captain see a crippled ship's
	# countdown and its limp home; Comms and the Captain the bounties and salvage.
	&"crippled": [["helm", "captain"], "danger", &"alert_red"],
	&"limped_home": [["helm", "captain"], "ok"],
	&"bounty": [["comms", "captain"], "ok"],
	&"salvage": [["comms", "captain"], "ok"],
}
## The critical tier: banner and edge flash (ux-12).
const CRITICAL: Array[StringName] = [
	&"hull_critical", &"missile_lock", &"shield_low", &"fault", &"crippled"
]
## The own ship's events that end its crippled countdown (gp-09): it limped home, fled or was
## destroyed, or its encounter ended (encounter_end names the encounter's first ship).
const COUNTDOWN_ENDS: Array[StringName] = [&"limped_home", &"fled", &"destroyed", &"encounter_end"]
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
var banner: CriticalBanner
var tones: AlertTones

var _level: int = CrewState.ALERT_NORMAL
var _toast_ms: Dictionary = {}


func setup(
	context: StationContext,
	station_ids: Array[String],
	toast_box: Toasts,
	edge: AlertFlash,
	critical: CriticalBanner
) -> void:
	ctx = context
	stations = station_ids
	toasts = toast_box
	flash = edge
	banner = critical
	_level = ctx.crew.alert
	tones = AlertTones.new()
	add_child(tones)
	ctx.crew.sim_event.connect(on_sim_event)
	ctx.crew.pinged.connect(func(_p: Dictionary) -> void: tones.play(&"ping", ctx.now_ms()))
	ctx.crew.changed.connect(_on_crew_changed)


## A sim event (docs/protocol.md "Events": payload {ship, faction, other, value, vector,
## tag}); only the own ship's count.
func on_sim_event(kind: StringName, p: Dictionary) -> void:
	if int(p.get("ship", -1)) != ctx.crew.ship:
		return
	if kind in COUNTDOWN_ENDS:
		banner.stop_countdown()
	if not ROUTES.has(kind):
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
	if kind == &"crippled":
		# The banner counts the limp-home time down until the ship docks (gp-09).
		flash.flash(Palette.color(role), now)
		var until: int = now + int(float(p.get("value", 0)) * 1000.0)
		banner.show_countdown(tr("alerts.crippled"), now, until)
	elif CRITICAL.has(kind):
		flash.flash(Palette.color(role), now)
		banner.show_text(_text(kind, p), now)
	elif now - int(_toast_ms.get(kind, -TOAST_GAP_MS)) >= TOAST_GAP_MS:
		_toast_ms[kind] = now
		toasts.push(_text(kind, p), role, now)
	if audible:
		tones.play(route[2] if route.size() > 2 else kind, now)


func _on_crew_changed(what: StringName) -> void:
	if what == &"reset":
		_level = ctx.crew.alert
		banner.stop_countdown()
	if what != &"alert" or ctx.crew.alert == _level:
		return
	_level = ctx.crew.alert
	# The state sent after Welcome or a reset has no setter: no tone (docs/protocol.md).
	if ctx.crew.alert_by == "":
		return
	var style: Dictionary = Palette.alert(_level)
	toasts.push("%s · %s" % [tr(style["key"]), ctx.crew.alert_by], "info", ctx.now_ms())
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
			return tr("alerts.hit").format({"dir": CalloutText.clock_words(v)})
		&"shield_low":
			# An absent summary (Hard) arrives as 0: the alert without a number (D224).
			var pct: int = roundi(float(p.get("value", 0)) * 100.0)
			if pct <= 0:
				return tr("alerts.shield_low_plain")
			return tr("alerts.shield_low").format({"pct": pct})
		&"fault":
			var tag: String = str(p.get("tag", ""))
			return tr("alerts.fault." + tag if FAULT_KEYS.has(tag) else "alerts.fault")
		&"bounty", &"salvage":
			return tr("alerts." + String(kind)).format({"n": int(p.get("value", 0))})
	return tr("alerts." + String(kind))
