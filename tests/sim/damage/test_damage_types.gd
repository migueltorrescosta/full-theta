extends GdUnitTestSuite
## M2 strand C: damage types and resistances (FT-SIM-022), weak points revealed by scans
## (FT-SIM-023, P7). The shooter is a corvette of faction 1 at the origin; the target is
## a raider of faction 2, 2 km ahead, with shields zeroed. Hits are fed to the
## HitResolver directly. Raider and corvette share their subsystem files: sensors at
## (0, 6, -14), engines at (0, 0, 18), 2e7 J each; subsystem_damage_share is 0.5.

const SENSORS_POINT: Vector3 = Vector3(0, 6, -14)
const ENGINES_POINT: Vector3 = Vector3(0, 0, 18)
const SHOT: float = 1e6


## The raider with the given resistances and, when weak_id is set, that subsystem a weak
## point taking `share` of a hit.
func _target_def(
	resistances: Dictionary[StringName, float] = {}, weak_id: StringName = &"", share: float = 0.8
) -> ShipDef:
	var def: ShipDef = TestDefs.raider().duplicate()
	def.resistances = resistances
	var subs: Array[SubsystemDef] = []
	for s: SubsystemDef in def.subsystems:
		var copy: SubsystemDef = s.duplicate()
		if copy.id == weak_id:
			copy.weak_point = true
			copy.weak_point_share = share
		subs.append(copy)
	def.subsystems = subs
	return def


## [world, shooter, target], stepped once so faction 1 has detected the target.
func _world(target_def: ShipDef) -> Array:
	var world: SimWorld = SimWorld.new(5)
	var shooter: int = world.spawn_ship(TestDefs.corvette(), 1, 0)
	var target: int = world.spawn_ship(target_def, 2, 0, Vector3(0, 0, -2000))
	world.step()
	world.drain_events()
	world.shields.strength[target] = 0.0
	world.science_def = ScienceFixture.science()
	return [world, shooter, target]


## A full Science scan of the target by the faction (what reveals weak points and
## resistances, FT-SCI-003); false for a faction that never detected it.
func _scan(world: SimWorld, faction: int, target: int) -> bool:
	return ScienceKnowledge.record(world, faction, target, 1.0)


func _hit(
	world: SimWorld, shooter: int, target: int, point: Vector3, type: StringName = &"kinetic"
) -> void:
	var h: SimHit = SimHit.new()
	h.target_id = target
	h.source_id = shooter
	h.kind = &"projectile"
	h.point_local = point
	h.energy = SHOT
	h.damage_type = type
	world.hits.append(h)
	HitResolver.resolve(world)


## Energy the target lost, hull and subsystems together.
func _lost(world: SimWorld, target: int) -> float:
	var total: float = 0.0
	for r: int in world.damage.rows_of(target):
		var max_health: float = (
			world.defs[target].hull_max
			if r == world.damage.hull_row(target)
			else world.defs[target].subsystems[r - world.damage.hull_row(target) - 1].health_max
		)
		total += max_health - world.damage.health[r]
	return total


func _sub_health(world: SimWorld, target: int, id: StringName) -> float:
	return world.damage.health[world.damage.find_subsystem(target, id)]


# FT: FT-SIM-022
# Table: the energy a hit puts on the target is its energy times the target's resistance
# to the hit's damage type; a type the target doesn't list, or no resistances at all,
# count as 1.
func test_resistance_table() -> void:
	var cases: Array = [
		["no resistances", {}, &"kinetic", 1.0],
		["unlisted type", {&"thermal": 0.5}, &"kinetic", 1.0],
		["resisted", {&"thermal": 0.5}, &"thermal", 0.5],
		["resisted, two listed", {&"thermal": 0.5, &"kinetic": 0.25}, &"kinetic", 0.25],
		["weak to it", {&"explosive": 1.5}, &"explosive", 1.5],
		["immune", {&"thermal": 0.0}, &"thermal", 0.0],
	]
	for c: Array in cases:
		var resist: Dictionary[StringName, float] = {}
		resist.assign(c[1])
		var w: Array = _world(_target_def(resist))
		_hit(w[0], w[1], w[2], ENGINES_POINT, c[2])
		assert_float(_lost(w[0], w[2])).override_failure_message(c[0]).is_equal_approx(
			SHOT * c[3], 1e-6
		)


# FT: FT-SIM-022
# P7: against a target that resists one type, ammunition of the other type does more
# damage than the resisted one, shot for shot.
func test_correct_ammunition_beats_resisted_ammunition() -> void:
	var resist: Dictionary[StringName, float] = {&"kinetic": 0.25, &"thermal": 1.5}
	var w: Array = _world(_target_def(resist))
	_hit(w[0], w[1], w[2], ENGINES_POINT, &"kinetic")
	var resisted: float = _lost(w[0], w[2])
	var w2: Array = _world(_target_def(resist))
	_hit(w2[0], w2[1], w2[2], ENGINES_POINT, &"thermal")
	assert_float(_lost(w2[0], w2[2])).is_greater(resisted * 4.0)


# FT: FT-SIM-022
# The resistance applies before the shields, so a resisted hit is absorbed less in
# total: what reaches the hull and subsystems is (energy x resistance) minus the absorbed.
func test_resistance_applies_before_shields() -> void:
	var resist: Dictionary[StringName, float] = {&"thermal": 0.5}
	var w: Array = _world(_target_def(resist))
	var world: SimWorld = w[0]
	world.shields.strength[w[2]] = 1e12
	_hit(world, w[1], w[2], ENGINES_POINT, &"thermal")
	var events: Array[SimEvent] = SimFixture.of_kind(world.drain_events(), &"hit")
	assert_float(events[0].value).is_less(SHOT * 0.5)


# FT: FT-SIM-022, FT-SCI-003
# A faction learns a contact's resistance by a scan: the setter needs a detected contact
# and a resistance the contact has, the faction then knows it (others don't), and a
# faction knows its own ships' resistances.
func test_resistance_knowledge() -> void:
	var resist: Dictionary[StringName, float] = {&"thermal": 0.5}
	var w: Array = _world(_target_def(resist))
	var world: SimWorld = w[0]
	assert_bool(KnowledgeSystem.knows_resistance(world, 1, w[2], &"thermal")).is_false()
	assert_bool(KnowledgeSystem.knows_resistance(world, 1, w[2], &"kinetic")).is_false()
	assert_bool(_scan(world, 3, w[2])).is_false()
	assert_bool(_scan(world, 1, w[2])).is_true()
	assert_bool(KnowledgeSystem.knows_resistance(world, 1, w[2], &"thermal")).is_true()
	assert_bool(KnowledgeSystem.knows_resistance(world, 3, w[2], &"thermal")).is_false()
	assert_bool(KnowledgeSystem.knows_resistance(world, 2, w[2], &"thermal")).is_true()


# FT: FT-SIM-023
# A hit on a revealed weak point puts the weak point's share of the energy on that
# subsystem (the named one), more than the ship's ordinary share, and emits
# &"weak_point_hit"; unrevealed, or revealed to another faction, it is an ordinary hit.
func test_revealed_weak_point_takes_the_larger_share() -> void:
	var def: ShipDef = _target_def({}, &"sensors", 0.8)
	var plain: Array = _world(def)
	_hit(plain[0], plain[1], plain[2], SENSORS_POINT)
	var ordinary: float = 2e7 - _sub_health(plain[0], plain[2], &"sensors")
	assert_float(ordinary).is_equal_approx(SHOT * 0.5, 1e-6)
	var other: Array = _world(def)
	assert_bool(_scan(other[0], 3, other[2])).is_false()
	var w: Array = _world(def)
	var world: SimWorld = w[0]
	assert_bool(_scan(world, 1, w[2])).is_true()
	_hit(world, w[1], w[2], SENSORS_POINT)
	var events: Array[SimEvent] = world.drain_events()
	assert_float(2e7 - _sub_health(world, w[2], &"sensors")).is_equal_approx(SHOT * 0.8, 1e-6)
	var marker: Array[SimEvent] = SimFixture.of_kind(events, &"weak_point_hit")
	assert_int(marker.size()).is_equal(1)
	assert_str(String(marker[0].tag)).is_equal("sensors")
	assert_int(marker[0].other_id).is_equal(w[1])
	# The energy is conserved: the rest goes to the hull.
	assert_float(_lost(world, w[2])).is_equal_approx(SHOT, 1e-6)


# FT: FT-SIM-023
# Table: the weak point is only hit when it is the subsystem nearest the impact; a hit
# elsewhere is ordinary even though the weak point is revealed. A revealed subsystem that
# isn't a weak point can't be revealed, and a destroyed weak point is passed over.
func test_weak_point_needs_the_hit_on_it() -> void:
	var def: ShipDef = _target_def({}, &"sensors", 0.8)
	var w: Array = _world(def)
	var world: SimWorld = w[0]
	_scan(world, 1, w[2])
	assert_bool(KnowledgeSystem.knows_weak_point(world, 1, w[2], &"engines")).is_false()
	_hit(world, w[1], w[2], ENGINES_POINT)
	assert_float(2e7 - _sub_health(world, w[2], &"sensors")).is_equal(0.0)
	assert_float(2e7 - _sub_health(world, w[2], &"engines")).is_equal_approx(SHOT * 0.5, 1e-6)
	world.damage.health[world.damage.find_subsystem(w[2], &"sensors")] = 0.0
	_hit(world, w[1], w[2], SENSORS_POINT)
	assert_int(SimFixture.of_kind(world.drain_events(), &"weak_point_hit").size()).is_equal(0)


# FT: FT-SIM-023
# Time to disable: identical shots on the weak point destroy the subsystem in fewer hits
# once the weak point is revealed than before.
func test_knowing_the_weak_point_shortens_time_to_disable() -> void:
	var counts: Array[int] = []
	for revealed: bool in [false, true]:
		var w: Array = _world(_target_def({}, &"sensors", 0.8))
		if revealed:
			_scan(w[0], 1, w[2])
		var shots: int = 0
		while _sub_health(w[0], w[2], &"sensors") > 0.0 and shots < 100:
			_hit(w[0], w[1], w[2], SENSORS_POINT)
			shots += 1
		counts.append(shots)
	assert_int(counts[1]).is_less(counts[0])


# FT: FT-SIM-023
# Collisions have no aim: a ramming hit never counts as a weak-point hit.
func test_collisions_never_hit_a_weak_point() -> void:
	var w: Array = _world(_target_def({}, &"sensors", 0.8))
	var world: SimWorld = w[0]
	_scan(world, 1, w[2])
	var h: SimHit = SimHit.new()
	h.target_id = w[2]
	h.source_id = w[1]
	h.kind = &"collision"
	h.point_local = SENSORS_POINT
	h.energy = SHOT
	world.hits.append(h)
	HitResolver.resolve(world)
	assert_float(2e7 - _sub_health(world, w[2], &"sensors")).is_equal_approx(SHOT * 0.5, 1e-6)
