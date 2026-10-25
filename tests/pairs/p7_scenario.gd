class_name P7Scenario
extends RefCounted
## P7 Weapons + Science pair scenario (spec §7.4, FT-PAIR-015, FT-SIM-022, FT-SIM-023):
## a raider at rest 2 km ahead, bow toward the corvette, resists kinetic fire (x0.25)
## and has a weak point on its weapons subsystem at the bow (revealed shots put 0.8 of
## their energy on it instead of the subsystem share). The corvette's mount takes two
## ammunition types: the mass driver (kinetic, type 0) and a thermal lance of the same
## numbers (type 1). Weapons must disable the raider's weapons (subsystem down to a
## quarter of its health, the effectiveness curve's 0.3 point).
## - Weapons (both variants): the gunner fires the mount whenever it is ready (Gunnery.gun).
## - Science (co-op only): scans the raider (ScienceHand, the average player's timing,
##   scan time included in the run); once the scan has revealed the weak points and the
##   resistances Weapons aims at the weak point and switches to the unresisted ammunition.
## - Solo: nobody scans: aim at the hull's centre with the default ammunition, nearest
##   subsystem hits (FT-PAIR-004).
## Metrics: time (s) until the raider's weapons are disabled, and weak-point hits (count,
## for the check that knowledge, not luck, lands them).

const SEED: int = 47
const PLAYER: int = 0
const RAIDER: int = 1
const BLUE: int = 1
const RAIDER_AT: Vector3 = Vector3(0.0, 0.0, -2000.0)
const WEAK_ID: StringName = &"weapons"
const WEAK_SHARE: float = 0.8
const KINETIC_RESISTANCE: float = 0.25
## Disabled at this share of the subsystem's health.
const DISABLED_AT: float = 0.25
const TICK_LIMIT: int = 240 * SimWorld.HZ
## Science starts its scan on this tick (the raider is a contact after tick 1).
const SCAN_AT: int = 2


static func harness() -> PairHarness:
	return PairHarness.new(build, PairHarness.no_environment, done, measure, TICK_LIMIT)


## The mass driver with a thermal lance as its second ammunition type.
static func lance() -> WeaponDef:
	var w: WeaponDef = TestDefs.corvette().mounts[0].weapon.duplicate()
	w.id = &"p7_lance"
	w.damage_type = &"thermal"
	return w


## The raider as a copy: weak point on its weapons, kinetic-resistant, no shields.
static func target_def() -> ShipDef:
	var def: ShipDef = Gunnery.raider_with_shields(0.0)
	var subs: Array[SubsystemDef] = []
	for s: SubsystemDef in def.subsystems:
		var copy: SubsystemDef = s.duplicate()
		if copy.id == WEAK_ID:
			copy.weak_point = true
			copy.weak_point_share = WEAK_SHARE
		subs.append(copy)
	def.subsystems = subs
	def.resistances = {&"kinetic": KINETIC_RESISTANCE}
	return def


static func build() -> SimWorld:
	var w: SimWorld = SimWorld.new(SEED, "p7")
	w.science_def = ScienceFixture.science()
	w.set_relation(1, 2, SimWorld.Relation.HOSTILE)
	var weapons: Array[WeaponDef] = [lance()]
	w.spawn_ship(Gunnery.gunship(1, weapons), BLUE, 0)
	var raider: int = w.spawn_ship(target_def(), 2, 0, RAIDER_AT, Quaternion(Vector3.UP, PI))
	w.shields.strength[raider] = 0.0
	return w


## Health of the raider's weapons subsystem as a share of its maximum.
static func weapons_health(w: SimWorld) -> float:
	var row: int = w.damage.find_subsystem(RAIDER, WEAK_ID)
	var index: int = row - w.damage.hull_row(RAIDER) - 1
	return w.damage.health[row] / w.defs[RAIDER].subsystems[index].health_max


static func done(w: SimWorld) -> bool:
	return weapons_health(w) <= DISABLED_AT


static func measure(w: SimWorld) -> Dictionary:
	var is_weak: Callable = func(e: SimEvent) -> bool: return e.kind == &"weak_point_hit"
	var weak_hits: float = w.drain_events().filter(is_weak).size()
	return {"time": w.tick * SimWorld.DT, "weak_hits": weak_hits}


## Solo crew: Weapons alone.
static func solo(w: SimWorld) -> void:
	if w.tick >= 2:
		Gunnery.gun(w, PLAYER, Gunnery.site_point(w, RAIDER, Vector3.ZERO))


## The co-op crew, a fresh one per run: Science scans, Weapons uses what it reveals.
static func coop_crew() -> Callable:
	var science: ScienceHand = ScienceHand.exact_from(PLAYER, RAIDER, SCAN_AT)
	return func(w: SimWorld) -> void:
		science.act(w)
		weapons_with_science(w)


static func weapons_with_science(w: SimWorld) -> void:
	if w.tick < 2:
		return
	var point: Vector3 = Vector3.ZERO
	var known: Array[int] = []
	known.assign(ScienceKnowledge.weak_points(w, BLUE, RAIDER))
	if not known.is_empty():
		point = w.defs[RAIDER].subsystems[known[0]].position
	if ScienceKnowledge.resistances_known(w, BLUE, RAIDER):
		_use_best_ammunition(w)
	Gunnery.gun(w, PLAYER, Gunnery.site_point(w, RAIDER, point))


## Switches the mount to the ammunition type the raider resists least (once).
static func _use_best_ammunition(w: SimWorld) -> void:
	var resist: Dictionary[StringName, float] = ScienceKnowledge.resistances(w, BLUE, RAIDER)
	var types: Array[WeaponDef] = w.defs[PLAYER].mounts[0].ammo_types()
	var best: int = 0
	for i: int in types.size():
		if resist.get(types[i].damage_type, 1.0) > resist.get(types[best].damage_type, 1.0):
			best = i
	if w.mounts.ammo_type[w.mounts.row_for(PLAYER, 0)] != best:
		var c: SetAmmoTypeCommand = SetAmmoTypeCommand.new()
		c.ship_id = PLAYER
		c.mount_index = 0
		c.ammo_type = best
		w.submit(c)
