class_name P6Scenario
extends RefCounted
## P6 Weapons + Engineering pair scenario (spec §7.4, FT-PAIR-015): a gunship (the M1
## corvette with MOUNTS mass drivers on the bow) fires at a raider at rest 2 km dead
## ahead and must destroy it. Eight mounts want 8 MJ/s of weapons energy
## (one 0.5 MJ shot per mount every 0.5 s), more than the 3.3 MJ/s two pips on the
## weapons recharge, so the energy store, not the cooldown, limits the fire.
## - Weapons (both variants): the gunner aims every mount at the raider and fires each
##   mount that is ready and has the energy (Gunnery.gun).
## - Engineering (co-op only): puts the reactor's 2 spare pips on the weapons (4 pips,
##   6.7 MJ/s, PowerDef.max_pips_per_subsystem) and drops them back to nominal once
##   their heat passes HEAT_GUARD of the fault threshold, so no fault fires (FT-SIM-026).
## - Solo: Engineering sends nothing: nominal pips (FT-PAIR-004).
## Metrics: time (s) until the raider is destroyed, and heat faults (count, for
## the co-op's no-fault check).

const SEED: int = 43
const PLAYER: int = 0
const RAIDER: int = 1
const MOUNTS: int = 8
const RAIDER_AT: Vector3 = Vector3(0.0, 0.0, -2000.0)
const HEAT_GUARD: float = 0.9
const TICK_LIMIT: int = 60 * SimWorld.HZ

const WPN: int = SubsystemDef.Kind.WEAPONS


static func harness() -> PairHarness:
	return PairHarness.new(build, no_environment, done, measure, TICK_LIMIT)


static func build() -> SimWorld:
	var w: SimWorld = SimWorld.new(SEED, "p6")
	w.set_relation(1, 2, SimWorld.Relation.HOSTILE)
	w.spawn_ship(Gunnery.gunship(MOUNTS), 1, 0)
	var raider: int = w.spawn_ship(Gunnery.raider_with_shields(0.0), 2, 0, RAIDER_AT)
	w.shields.strength[raider] = 0.0
	return w


static func no_environment(_w: SimWorld) -> void:
	pass


static func done(w: SimWorld) -> bool:
	return not w.kin.is_alive(RAIDER)


static func measure(w: SimWorld) -> Dictionary:
	var is_fault: Callable = func(e: SimEvent) -> bool: return e.kind == &"fault"
	var faults: float = w.drain_events().filter(is_fault).size()
	return {"time": w.tick * SimWorld.DT, "heat_faults": faults}


static func solo(w: SimWorld) -> void:
	weapons(w)


static func coop(w: SimWorld) -> void:
	weapons(w)
	engineering(w)


## Weapons: all mounts on the raider, from tick 2 on (it is a contact after the first
## tick's sweep).
static func weapons(w: SimWorld) -> void:
	if w.tick >= 2:
		Gunnery.gun(w, PLAYER, Gunnery.site_point(w, RAIDER, Vector3.ZERO))


## Engineering: all spare pips to the weapons, back to nominal when they run hot.
static func engineering(w: SimWorld) -> void:
	var index: int = PowerSystem.subsystem_index(w.defs[PLAYER], WPN)
	var row: int = w.damage.subsystem_row(PLAYER, index)
	var threshold: float = w.defs[PLAYER].subsystems[index].fault_heat_threshold
	var hot: bool = w.damage.heat[row] > HEAT_GUARD * threshold
	var pips: int = w.defs[PLAYER].subsystems[index].nominal_pips
	if w.tick == 0:
		pips = w.defs[PLAYER].power.max_pips_per_subsystem
	elif hot:
		pips = w.defs[PLAYER].subsystems[index].nominal_pips
	else:
		return
	var c: SetPipsCommand = SetPipsCommand.new()
	c.ship_id = PLAYER
	c.subsystem_kind = WPN
	c.pips = pips
	w.submit(c)
