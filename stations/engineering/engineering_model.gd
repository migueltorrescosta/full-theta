# gdlint: disable=max-public-methods
class_name EngineeringModel
extends RefCounted
## Engineering's view-model (R13-6): reads the ENGINEERING block (ctx.snap.blocks) against
## the ship's ShipDef and sends the panel's commands, each checking what the sim would refuse
## and saying why. The panel, its board, cutaway and phone share one; it needs no scene.
## Hit marks come from `hit` events on the own ship (vector in the ship frame) and heat
## faults from `fault` events, through CrewState.sim_event (on_sim_event).

const S = StationCatalogue.Section
const KIND = SubsystemDef.Kind

## A sent pip or tightness value shows until the snapshot agrees, or for this long (ms).
const PENDING_MS: int = 1000
## Hit marks fade over this (ms) (FT-ENG-001: recent hit locations).
const HIT_MS: int = 15000
const MAX_HITS: int = 12
## A heat fault stays listed this long after its event (ms).
const FAULT_MS: int = 20000
## Heat share of the fault threshold from which a subsystem is listed as hot.
const HOT: float = 0.7
const TIGHTNESS_STEP: float = 0.5
const CREW_LETTERS: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

var ctx: StationContext
var ship_def: ShipDef = null
## Index in ship_def.subsystems of the subsystem pips, dispatch and the cursor act on.
var selected: int = 0
## The crew the common claim action (K, View+X) takes or releases.
var crew_pick: int = 0
## Recent hits on the own ship: {"pos": Vector3 (ship frame, m), "at_ms": int}.
var hits: Array[Dictionary] = []
## Subsystem index -> ms of its last heat fault event.
var faults: Dictionary = {}

## "pips:<i>" or "tightness" -> [value sent, at ms].
var _pending: Dictionary = {}


func _init(context: StationContext, def: ShipDef) -> void:
	ctx = context
	ship_def = def


# --- Reading the ENGINEERING block. ---


func block() -> Dictionary:
	return ctx.snap.blocks.get(S.ENGINEERING, {})


## The block row of subsystem i ({} before the first snapshot).
func row(i: int) -> Dictionary:
	var rows: Array = block().get("subsystems", [])
	return rows[i] if i >= 0 and i < rows.size() else {}


func count() -> int:
	return ship_def.subsystems.size() if ship_def != null else 0


func health_frac(i: int) -> float:
	var r: Dictionary = row(i)
	return clampf(float(r.get("health", 0.0)) / ship_def.subsystems[i].health_max, 0.0, 1.0)


## Heat as a share of the fault threshold (1 = faults).
func heat_frac(i: int) -> float:
	return float(row(i).get("heat", 0.0)) / ship_def.subsystems[i].fault_heat_threshold


## The pips set on subsystem i (a value just sent shows until the snapshot agrees).
func pips_of(i: int) -> int:
	return int(_pending_value("pips:%d" % i, int(row(i).get("pips", 0))))


func pips_used() -> int:
	var total: int = 0
	for i: int in count():
		total += pips_of(i)
	return total


func boosting() -> bool:
	return int(block().get("boost_ticks", 0)) > 0


func is_boosted(i: int) -> bool:
	return boosting() and ship_def.subsystems[i].kind in [KIND.ENGINES, KIND.THRUSTERS]


func tightness() -> float:
	return float(_pending_value("tightness", float(block().get("shield_tightness", 0.0))))


func shield_frac() -> float:
	var full: float = ship_def.shields.max_strength if ship_def.shields != null else 0.0
	return clampf(float(block().get("shield_strength", 0.0)) / full, 0.0, 1.0) if full > 0 else 0.0


func spare_parts() -> int:
	return int(block().get("spare_parts", 0))


func crew_count() -> int:
	return ship_def.repair_crews if ship_def != null else 0


## The subsystem crew c works on, or -1 when idle.
func crew_job(c: int) -> int:
	for i: int in count():
		if int(row(i).get("crews", 0)) & (1 << c):
			return i
	return -1


## Whether another player holds crew c's claim (FT-NET-023).
func crew_taken(c: int) -> bool:
	var holder: Variant = ctx.snap.ownership.get("claims", {}).get("crew:%d" % c)
	return holder is Array and int(holder[0]) != ctx.crew.session


## Short subsystem name ("ENG") and full name, from its kind.
func short_name(i: int) -> String:
	return tr("eng.short." + _kind_key(i))


func full_name(i: int) -> String:
	return tr("eng.name." + _kind_key(i))


static func crew_letter(c: int) -> String:
	return CREW_LETTERS[c % CREW_LETTERS.length()]


# --- Actions (each checks what the sim would refuse and says why). ---


## Why action `id` (an Engineering touch action) can't act on subsystem i now: the suffix of
## its `eng.reason.*` string, or "" when it can (C4). The rail greys a button with it before
## the tap and the actions refuse with the toast of the same name (`toast.eng_<reason>`).
## Two reasons are hints only, left to the server (D380, FT-ENG-008): "cap" (the reactor's
## pips now, STATUS.pip_cap, are all used) and Probe's "no_parts".
func why_not(id: String, i: int = selected) -> String:
	if ship_def == null or i < 0 or i >= count():
		return ""
	var sd: SubsystemDef = ship_def.subsystems[i]
	var why: String = ""
	match id:
		"pip_add", "pip_remove":
			why = _pip_reason(i, id == "pip_add")
		"shield_tighter", "shield_wider":
			why = _tightness_reason(id == "shield_tighter")
		"boost":
			why = "boosting" if boosting() else ""
		"harden":
			if hardened_ticks(i) > 0:
				why = "hardened"
			elif spare_parts() < sd.harden_parts:
				why = "no_parts"
		"dispatch_nearest":
			if health_frac(i) >= 1.0:
				why = "whole"
			elif _free_crew_for(i) < 0:
				why = "no_crew"
			elif spare_parts() < sd.parts_per_repair:
				why = "no_parts"
		"cause_next":
			why = "" if has_fault(i) and not sd.fault_causes.is_empty() else "no_fault"
		"fabricate_probe":
			why = "no_parts" if spare_parts() < ship_def.probe_parts else ""
		"claim":
			why = "no_crew" if crew_count() == 0 else ""
	return why


## Whether rail action `id` shows now (C3): the rare actions hide while they can't matter
## and the others always show, in a fixed order. Cause shows while a part has a fault of
## unknown cause, Probe while the spare parts pay for one, Claim while the ship has repair
## crews and a second player shares this station (or this player still holds a crew).
## A shown action that can't act on the picked part still greys with its why_not reason.
func shown(id: String) -> bool:
	if ship_def == null:
		return true
	match id:
		"cause_next":
			return any_fault()
		"fabricate_probe":
			return spare_parts() >= ship_def.probe_parts
		"claim":
			return crew_count() > 0 and (players_here() >= 2 or holds_crew())
	return true


## Whether any part has a fault of unknown cause to guess (FT-ENG-006).
func any_fault() -> bool:
	for i: int in count():
		if has_fault(i) and not ship_def.subsystems[i].fault_causes.is_empty():
			return true
	return false


## The players seated at Engineering on this ship (a joint view holding it counts), from the
## lobby's seats.
func players_here() -> int:
	var n: int = 0
	for seat: Variant in ctx.crew.ship_state(ctx.crew.ship).get("seats", []):
		var def: Dictionary = ctx.crew.def_of(str((seat as Dictionary).get("seat", "")))
		if "engineering" in def.get("stations", []):
			n += 1
	return n


## Whether this player holds a repair crew's claim (FT-NET-023).
func holds_crew() -> bool:
	for c: int in crew_count():
		var item: String = "%s:%d" % [StationCatalogue.CLAIM_CREW, c]
		if int(ctx.crew.claims.get(item, {}).get("session", -1)) == ctx.crew.session:
			return true
	return false


## Power + and - on subsystem i (why_not).
func _pip_reason(i: int, add: bool) -> String:
	if ship_def.subsystems[i].kind == KIND.REACTOR:
		return "reactor"
	if not add:
		return "no_pips" if pips_of(i) <= 0 else ""
	if pips_of(i) >= ship_def.power.max_pips_per_subsystem:
		return "max"
	return "cap" if pips_used() >= ctx.pip_cap() else ""


## Tighter and Wider at the ship's focus range (why_not).
func _tightness_reason(tighter: bool) -> String:
	var def: ShieldDef = ship_def.shields
	if def == null:
		return "limit"
	var t: float = tightness()
	var at_end: bool = t >= def.tightness_max - 0.001 if tighter else t <= def.tightness_min + 0.001
	return "limit" if at_end else ""


## Shows the toast of refusal `why` (why_not's) and says whether there was one.
func _refused(why: String) -> bool:
	if why != "":
		_toast("toast.eng_" + why)
	return why != ""


func select(i: int) -> bool:
	if i < 0 or i >= count():
		return false
	selected = i
	return true


## Sets subsystem i's pips (FT-ENG-002): within 0..max per subsystem and the reactor cap,
## overcharge included; the reactor supplies pips and takes none (D117).
func set_pips(i: int, n: int) -> bool:
	if i < 0 or i >= count():
		return false
	var sd: SubsystemDef = ship_def.subsystems[i]
	# Only the reactor is refused here: the pip range is clamped, and over the reactor cap
	# the server refuses (below).
	if why_not("pip_add", i) == "reactor" and _refused("reactor"):
		return false
	var p: int = clampi(n, 0, ship_def.power.max_pips_per_subsystem)
	var now: int = pips_of(i)
	if p == now:
		return false
	# Over the reactor cap the sim refuses, and the server's command_rejected{eng_cap} is the
	# toast (F5, R12-7).
	ctx.intents.command({"kind": "set_pips", "subsystem_kind": int(sd.kind), "pips": p})
	_pending["pips:%d" % i] = [p, ctx.now_ms()]
	return true


## Focus tightness in TIGHTNESS_STEP steps over the ship's range (FT-ENG-003, D118).
func set_tightness(t: float) -> bool:
	var def: ShieldDef = ship_def.shields
	var v: float = clampf(snappedf(t, TIGHTNESS_STEP), def.tightness_min, def.tightness_max)
	if is_equal_approx(v, tightness()):
		return false
	ctx.intents.command({"kind": "set_shield", "power": -1, "tightness": v})
	_pending["tightness"] = [v, ctx.now_ms()]
	return true


func boost() -> bool:
	if _refused(why_not("boost")):
		return false
	ctx.intents.command({"kind": "boost"})
	return true


## Sends crew c to subsystem i (FT-ENG-004, D115).
func dispatch(c: int, i: int) -> bool:
	if c < 0 or c >= crew_count() or i < 0 or i >= count() or crew_job(c) == i:
		return false
	var sd: SubsystemDef = ship_def.subsystems[i]
	# Crew c is named, so "no crew free" is not this dispatch's to say.
	var why: String = why_not("dispatch_nearest", i)
	if why != "no_crew" and _refused(why):
		return false
	crew_pick = c
	ctx.intents.command({"kind": "dispatch_repair", "crew": c, "subsystem_id": String(sd.id)})
	return true


func recall(c: int) -> bool:
	if crew_job(c) < 0:
		return false
	crew_pick = c
	ctx.intents.command({"kind": "recall_repair", "crew": c})
	return true


## Controller B: an idle crew to the selected subsystem, else the first crew working
## elsewhere; crews another player holds are skipped.
func dispatch_nearest() -> bool:
	if _refused(why_not("dispatch_nearest")):
		return false
	return dispatch(_free_crew_for(selected), selected)


## The crew dispatch_nearest sends to subsystem i: an idle one, else the first working
## elsewhere, skipping crews another player holds; -1 for none.
func _free_crew_for(i: int) -> int:
	var other: int = -1
	for c: int in crew_count():
		if crew_taken(c) or crew_job(c) == i:
			continue
		if crew_job(c) < 0:
			return c
		if other < 0:
			other = c
	return other


## Pre-hardens subsystem i (FT-ENG-008): the sim takes its parts and refuses a repeat.
func harden(i: int) -> bool:
	if i < 0 or i >= count():
		return false
	if _refused(why_not("harden", i)):
		return false
	ctx.intents.command({"kind": "harden", "subsystem_id": String(ship_def.subsystems[i].id)})
	return true


## Asks for a probe fabricated from spare parts (FT-ENG-008, P11): the command is Relay's
## sim (`fabricate_probe`), which takes the parts and adds the probe.
func fabricate_probe() -> bool:
	ctx.intents.command({"kind": "fabricate_probe"})
	return true


## Ticks of hardening left on subsystem i (the block row).
func hardened_ticks(i: int) -> int:
	return int(row(i).get("hardened", 0))


## Whether subsystem i has a fault of unknown cause (FT-SIM-025).
func has_fault(i: int) -> bool:
	return bool(row(i).get("fault", false))


## Index plus 1 in the subsystem's fault_causes of the cause Science's scan found (0:
## not found yet).
func known_cause(i: int) -> int:
	return int(row(i).get("fault_cause", 0))


## Index plus 1 of the cause Engineering picked (0: none), as sent, until the snapshot
## agrees.
func picked_cause(i: int) -> int:
	return int(_pending_value("cause:%d" % i, int(row(i).get("fault_pick", 0))))


## Picks the next cause in the subsystem's list for its fault (FT-ENG-006).
func cycle_cause(i: int) -> bool:
	if i < 0 or i >= count():
		return false
	var causes: Array[StringName] = ship_def.subsystems[i].fault_causes
	if _refused(why_not("cause_next", i)):
		return false
	var next: int = picked_cause(i) % causes.size() + 1
	ctx.intents.command(
		{
			"kind": "pick_fault_cause",
			"subsystem_id": String(ship_def.subsystems[i].id),
			"cause": String(causes[next - 1])
		}
	)
	_pending["cause:%d" % i] = [next, ctx.now_ms()]
	return true


## A cause's name: its strings entry `eng.cause.<id>`, else the id as words.
func cause_name(i: int, index_plus_one: int) -> String:
	var id: String = String(ship_def.subsystems[i].fault_causes[index_plus_one - 1])
	var text: String = tr("eng.cause." + id)
	return text if text != "eng.cause." + id else id.replace("_", " ")


# --- Faults, queue, parts (FT-ENG-005). ---


## Seconds until the ship meets a hazard, or -1 when the countdown toggle is off for this
## view or none is coming (P11): the soonest forecast of the sim hazards the faction
## knows (the RELAY block, D208).
func hazard_eta() -> float:
	if not ctx.crew.filter().grants(ShortcutFilter.HAZARD_COUNTDOWNS):
		return -1.0
	return HazardEta.forecast(
		ctx.snap.blocks.get(StationCatalogue.Section.RELAY, {}).get("hazards", [])
	)


## [text, palette role] lines of the faults list, worst first: the danger lines (a part down,
## overheated, a fault to diagnose), then the warnings; the most damaged first in each.
func fault_lines() -> Array:
	var out: Array = []
	var now: int = ctx.now_ms()
	var order: Array = range(count())
	order.sort_custom(func(a: int, b: int) -> bool: return health_frac(a) < health_frac(b))
	for i: int in order:
		var h: float = health_frac(i)
		if h <= 0.0:
			out.append([tr("eng.fault_down") % full_name(i), "danger_text"])
		elif faults.has(i) and now - int(faults[i]) < FAULT_MS:
			out.append([tr("eng.fault_heat") % [full_name(i), roundi(h * 100)], "danger_text"])
		elif has_fault(i):
			out.append(_fault_line(i, h))
		elif h < 1.0:
			out.append([tr("eng.fault_damaged") % [full_name(i), roundi(h * 100)], "warn"])
		elif heat_frac(i) >= HOT:
			out.append([tr("eng.fault_hot") % full_name(i), "warn"])
	var danger: Array = out.filter(func(l: Array) -> bool: return l[1] == "danger_text")
	var warn: Array = out.filter(func(l: Array) -> bool: return l[1] != "danger_text")
	return danger + warn


## The glyph before a fault line by its role: "!!" danger, "!" warning (colour is not the
## only signal, C4).
static func severity_glyph(role: String) -> String:
	return "!! " if role == "danger_text" else "! "


## The faults-list line of a subsystem with a fault of unknown cause: the cause is
## unknown until Science's scan found it (FT-SIM-025); Engineering's pick is shown.
func _fault_line(i: int, h: float) -> Array:
	var name: String = full_name(i)
	var pick: int = picked_cause(i)
	var known: int = known_cause(i)
	var pct: int = roundi(h * 100)
	if known > 0:
		if pick == known:
			return [tr("eng.fault_right") % [name, pct, cause_name(i, known)], "warn"]
		return [tr("eng.fault_diagnosed") % [name, pct, cause_name(i, known)], "danger_text"]
	if pick > 0:
		return [tr("eng.fault_guess") % [name, pct, cause_name(i, pick)], "warn"]
	return [tr("eng.fault_unknown") % [name, pct], "danger_text"]


## The repair queue: damaged subsystems, most damaged first, with their crews.
func queue_lines() -> Array:
	var out: Array = []
	var order: Array = range(count()).filter(func(i: int) -> bool: return health_frac(i) < 1.0)
	order.sort_custom(func(a: int, b: int) -> bool: return health_frac(a) < health_frac(b))
	for i: int in order:
		var crews: PackedStringArray = []
		for c: int in crew_count():
			if crew_job(c) == i:
				crews.append(crew_letter(c))
		var who: String = ", ".join(crews) if not crews.is_empty() else tr("eng.waiting")
		out.append(
			[
				(
					"%d. %s %d%%  %s"
					% [out.size() + 1, short_name(i), roundi(health_frac(i) * 100), who]
				),
				"text"
			]
		)
	for c: int in crew_count():
		var j: int = crew_job(c)
		var text: String = tr("eng.crew") % crew_letter(c)
		text += ": " + (short_name(j) if j >= 0 else tr("eng.idle"))
		var holder: String = ctx.snap.claimer("crew:%d" % c)
		if holder != "":
			text += " (%s)" % holder
		out.append([text, "text_dim"])
	return out


# --- Events. ---


## Drops the hit marks older than HIT_MS (once a frame).
func expire_hits() -> void:
	var now: int = ctx.now_ms()
	while not hits.is_empty() and now - int(hits[0]["at_ms"]) > HIT_MS:
		hits.pop_front()


func on_sim_event(kind: StringName, p: Dictionary) -> void:
	if int(p.get("ship", -1)) != ctx.crew.ship or ship_def == null:
		return
	match String(kind):
		"hit":
			var v: Variant = p.get("vector")
			if v is Vector3:
				hits.append({"pos": v, "at_ms": ctx.now_ms()})
				if hits.size() > MAX_HITS:
					hits.pop_front()
		"fault":
			var i: int = _index_of(StringName(str(p.get("tag", ""))))
			if i >= 0:
				faults[i] = ctx.now_ms()


func _pending_value(key: String, actual: Variant) -> Variant:
	if not _pending.has(key):
		return actual
	var p: Array = _pending[key]
	var agrees: bool = is_equal_approx(float(p[0]), float(actual))
	if agrees or ctx.now_ms() - int(p[1]) > PENDING_MS:
		_pending.erase(key)
		return actual
	return p[0]


func _toast(key: String) -> void:
	ctx.crew.toast.emit(key, {})


func _kind_key(i: int) -> String:
	return str(KIND.find_key(ship_def.subsystems[i].kind)).to_lower()


func _index_of(id: StringName) -> int:
	for i: int in count():
		if ship_def.subsystems[i].id == id:
			return i
	return -1
