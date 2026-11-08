class_name EngineeringRail
extends RefCounted
## Why an Engineering rail button can't act now (C4): the suffix of its `eng.reason.*`
## string, or "" when it can. It mirrors what the panel's actions refuse (whose toasts say
## the same after the tap), so a greyed button names its reason before the tap.

## Rail buttons that act on the picked part: their second line names it (ENG), so the rail
## says what Harden or Repair will touch; a button that can't act shows its reason there.
const ON_PART: Array[String] = ["pip_add", "pip_remove", "harden", "dispatch_nearest", "cause_next"]


## The label of rail button `id`.
static func text(id: String) -> String:
	for a: Array in EngineeringPanel.TOUCH_ACTIONS:
		if a[0] == id:
			return TouchText.of(a[1], a[2])
	return id


## The rail buttons' texts and states, once a frame.
static func update(p: EngineeringPanel) -> void:
	var sets: Array[Dictionary] = [p.touch_buttons, p.grid_buttons]
	if p.tablet_ui != null:
		sets.append(p.tablet_ui.buttons)
	for buttons: Dictionary in sets:
		for id: String in buttons:
			var b: RailButton = buttons[id]
			if p.ship_def == null:
				b.disabled = true
				continue
			var why: String = reason(p, id)
			var second: String = ""
			if why != "":
				second = p.tr("eng.reason." + why)
			elif id in ON_PART:
				second = p.short_name(p.selected)
			var base: String = p.claim_text() if id == "claim" else text(id)
			var label: String = base if second == "" else "%s\n%s" % [base, second]
			if b.text != label:
				b.text = label
			b.disabled = why != ""


static func reason(p: EngineeringPanel, id: String) -> String:
	if p.ship_def == null:
		return ""
	var sd: SubsystemDef = p.ship_def.subsystems[p.selected]
	match id:
		"pip_add":
			return _pips(p, sd, true)
		"pip_remove":
			return _pips(p, sd, false)
		"shield_tighter", "shield_wider":
			return _tightness(p, id == "shield_tighter")
		"boost":
			return "boosting" if p.boosting() else ""
		"harden":
			return _harden(p, sd)
		"dispatch_nearest":
			return _repair(p, sd)
		"cause_next":
			return "" if p.has_fault(p.selected) and not sd.fault_causes.is_empty() else "no_fault"
		"fabricate_probe":
			return "no_parts" if p.spare_parts() < p.ship_def.probe_parts else ""
		"claim":
			return "no_crew" if p.crew_count() == 0 else ""
	return ""


static func _pips(p: EngineeringPanel, sd: SubsystemDef, add: bool) -> String:
	if sd.kind == SubsystemDef.Kind.REACTOR:
		return "reactor"
	var pips: int = p.pips_of(p.selected)
	if not add:
		return "no_pips" if pips <= 0 else ""
	if pips >= p.ship_def.power.max_pips_per_subsystem:
		return "max"
	return "cap" if p.pips_used() >= p.ctx.pip_cap() else ""


static func _tightness(p: EngineeringPanel, tighter: bool) -> String:
	var def: ShieldDef = p.ship_def.shields
	if def == null:
		return "limit"
	var t: float = p.tightness()
	var at_end: bool = t >= def.tightness_max - 0.001 if tighter else t <= def.tightness_min + 0.001
	return "limit" if at_end else ""


static func _harden(p: EngineeringPanel, sd: SubsystemDef) -> String:
	if p.hardened_ticks(p.selected) > 0:
		return "hardened"
	return "no_parts" if p.spare_parts() < sd.harden_parts else ""


static func _repair(p: EngineeringPanel, sd: SubsystemDef) -> String:
	if p.health_frac(p.selected) >= 1.0:
		return "whole"
	if not _crew_free_for(p, p.selected):
		return "no_crew"
	return "no_parts" if p.spare_parts() < sd.parts_per_repair else ""


## True when some crew another player doesn't hold could go to subsystem i.
static func _crew_free_for(p: EngineeringPanel, i: int) -> bool:
	for c: int in p.crew_count():
		if not p.crew_taken(c) and p.crew_job(c) != i:
			return true
	return false
