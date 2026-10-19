extends GdUnitTestSuite
## T038: the headless 2-ship PvP simulation test (FT-TST-013, FT-M1-014). Two crewed M1
## corvettes of hostile factions (RED ship 0 at the origin, bow -Z; BLUE ship 2 at
## 5 km on -Z, bow +Z), no AI, fight with scripted crews; two raiders of a third
## faction, neutral to both, sit where the factions see them differently:
## - FAR (ship 1) at 17 km on +Z: in RED's 20 km sensor range, not in BLUE's (22 km).
## - NEAR (ship 3) at (7000, 0, 2000): RED identifies it (7.3 km, inside the 8 km
##   identify range), BLUE only detects it (9.9 km).
## Detection runs in contact id order, so RED numbers FAR 1, BLUE 2, NEAR 3 and BLUE
## numbers RED 1, NEAR 2: NEAR is "N3" to RED and "U2" to BLUE.
## Every wait loop is bounded by a tick limit and asserts it was not reached.

const HZ: int = SimWorld.HZ
const RED_FACTION: int = 1
const BLUE_FACTION: int = 2
const NEUTRAL_FACTION: int = 3
const SITE: int = 0
const RED: int = 0
const FAR: int = 1
const BLUE: int = 2
const NEAR: int = 3
const BLUE_OFFSET: Vector3 = Vector3(0.0, 0.0, -5000.0)
const SEED: int = 38
## Far above the fight's length (BLUE is destroyed at tick 8268 with seed SEED).
const MAX_FIGHT_TICKS: int = 300 * HZ


## BLUE's crew: the M1 scripted crew, skipping its turn every 2 * FIRE_EVERY ticks, so
## it fires every other volley. The asymmetry decides the fight: two equal crews would
## destroy each other on the same tick.
class HalfRateCrew:
	extends ScriptedCrew

	func act(world: SimWorld) -> void:
		if world.tick % (2 * FIRE_EVERY) != 0:
			super.act(world)


## The scenario world at tick 0.
static func build(world_seed: int = SEED) -> SimWorld:
	var w: SimWorld = SimWorld.new(world_seed, "test")
	w.set_relation(RED_FACTION, BLUE_FACTION, SimWorld.Relation.HOSTILE)
	w.set_relation(RED_FACTION, NEUTRAL_FACTION, SimWorld.Relation.NEUTRAL)
	w.set_relation(BLUE_FACTION, NEUTRAL_FACTION, SimWorld.Relation.NEUTRAL)
	w.spawn_ship(TestDefs.corvette(), RED_FACTION, SITE)
	w.spawn_ship(TestDefs.raider(), NEUTRAL_FACTION, SITE, Vector3(0.0, 0.0, 17000.0))
	w.spawn_ship(TestDefs.corvette(), BLUE_FACTION, SITE, BLUE_OFFSET, _facing_red())
	w.spawn_ship(TestDefs.raider(), NEUTRAL_FACTION, SITE, Vector3(7000.0, 0.0, 2000.0))
	return w


static func _facing_red() -> Quaternion:
	return Quaternion(Vector3.UP, PI)


## Both crews fire until a corvette leaves play; returns every event.
func fight(w: SimWorld) -> Array[SimEvent]:
	var red_crew: ScriptedCrew = ScriptedCrew.new(RED, BLUE)
	var blue_crew: ScriptedCrew = HalfRateCrew.new(BLUE, RED)
	var events: Array[SimEvent] = []
	while _both_in_play(w) and w.tick < MAX_FIGHT_TICKS:
		red_crew.act(w)
		blue_crew.act(w)
		w.step()
		events.append_array(w.drain_events())
	(
		assert_bool(_both_in_play(w))
		. override_failure_message("fight not over in %d ticks" % MAX_FIGHT_TICKS)
		. is_false()
	)
	return events


static func _both_in_play(w: SimWorld) -> bool:
	return (
		w.run.status[RED] == RunTable.Status.IN_PLAY
		and w.run.status[BLUE] == RunTable.Status.IN_PLAY
	)


## Copies of the table's columns over the rows keep(table, row) accepts: [name, values].
static func rows(t: SimTable, keep: Callable) -> Array:
	var out: Array = []
	for col: Array in t.columns():
		var values: Array = []
		for r: int in t.size():
			if keep.call(t, r):
				values.append(col[1][r])
		out.append([col[0], values])
	return out


## Every table's rows that are not BLUE's own run state: all rows of other ships, all
## knowledge rows except other factions' rows about BLUE as a contact.
static func not_blue(w: SimWorld) -> Array:
	var out: Array = []
	for t: SimTable in w.tables():
		out.append(rows(t, func(tt: SimTable, r: int) -> bool: return tt.ship_ids[r] != BLUE))
	return out


## BLUE's rows in every table but knowledge (whose ship_ids are contacts).
static func blue_rows(w: SimWorld) -> Array:
	var out: Array = []
	for t: SimTable in w.tables():
		if t != w.knowledge:
			out.append(rows(t, func(tt: SimTable, r: int) -> bool: return tt.ship_ids[r] == BLUE))
	return out


static func relations_of(w: SimWorld) -> Array:
	return [
		w.relation(RED_FACTION, BLUE_FACTION),
		w.relation(RED_FACTION, NEUTRAL_FACTION),
		w.relation(BLUE_FACTION, NEUTRAL_FACTION),
	]


static func numbers_of(w: SimWorld, faction: int) -> Array:
	var keep: Callable = func(t: SimTable, r: int) -> bool: return t.factions[r] == faction
	return rows(w.knowledge, keep)


# FT: FT-TST-013, FT-ARC-013, FT-M1-014
# Knowledge is per faction: each sees only what its own ships sense, through the rows
# and through the KnowledgeSystem API. FAR is detected by RED only; NEAR is identified
# by RED only; contact events go to the observing faction only.
func test_knowledge_stays_separate_per_faction() -> void:
	var w: SimWorld = build()
	w.step()
	var events: Array[SimEvent] = w.drain_events()
	assert_bool(KnowledgeSystem.is_detected(w, RED_FACTION, FAR)).is_true()
	assert_bool(KnowledgeSystem.is_detected(w, BLUE_FACTION, FAR)).is_false()
	assert_int(w.knowledge.row_for(BLUE_FACTION, FAR)).is_equal(-1)
	assert_str(KnowledgeSystem.callsign(w, BLUE_FACTION, FAR)).is_equal("")
	assert_array(Array(KnowledgeSystem.contacts(w, RED_FACTION))).is_equal([FAR, BLUE, NEAR])
	assert_array(Array(KnowledgeSystem.contacts(w, BLUE_FACTION))).is_equal([RED, NEAR])
	assert_bool(KnowledgeSystem.is_identified(w, RED_FACTION, NEAR)).is_true()
	assert_bool(KnowledgeSystem.is_identified(w, BLUE_FACTION, NEAR)).is_false()
	assert_bool(KnowledgeSystem.is_identified(w, BLUE_FACTION, RED)).is_true()
	# Rows: (observer, contact) pairs; a faction never has rows for its own ships.
	var pairs: Array = []
	for r: int in w.knowledge.size():
		pairs.append([w.knowledge.factions[r], w.knowledge.ship_ids[r]])
	pairs.sort()
	(
		assert_array(pairs)
		. is_equal(
			[
				[RED_FACTION, FAR],
				[RED_FACTION, BLUE],
				[RED_FACTION, NEAR],
				[BLUE_FACTION, RED],
				[BLUE_FACTION, NEAR],
				[NEUTRAL_FACTION, RED],
				[NEUTRAL_FACTION, BLUE],
			]
		)
	)
	for e: SimEvent in events:
		if e.kind == &"contact_detected" and e.other_id == FAR:
			assert_int(e.faction).is_not_equal(BLUE_FACTION)
		if e.kind == &"contact_detected":
			assert_int(e.faction).is_equal(w.faction_of(e.ship_id))
			assert_bool(KnowledgeSystem.is_detected(w, e.faction, e.other_id)).is_true()


# FT: FT-TST-013, FT-SPA-002, FT-SPA-001, FT-M1-014
# Callsigns are per faction: the same contact has a different number in each faction,
# and one faction detecting more never shifts the other's numbers. When FAR moves from
# RED's range into BLUE's, BLUE gives it its next number (3) and RED keeps FAR as 1
# (now lost) with every other RED row unchanged.
func test_callsigns_independent_per_faction() -> void:
	var w: SimWorld = build()
	w.step()
	assert_str(KnowledgeSystem.callsign(w, RED_FACTION, FAR)).is_equal("U1")
	assert_str(KnowledgeSystem.callsign(w, RED_FACTION, BLUE)).is_equal("H2")
	assert_str(KnowledgeSystem.callsign(w, RED_FACTION, NEAR)).is_equal("N3")
	assert_str(KnowledgeSystem.callsign(w, BLUE_FACTION, RED)).is_equal("H1")
	assert_str(KnowledgeSystem.callsign(w, BLUE_FACTION, NEAR)).is_equal("U2")
	var red_before: Array = numbers_of(w, RED_FACTION)
	# 17 km behind BLUE: in BLUE's range, 22 km from RED.
	w.kin.place(FAR, SITE, 0.0, 0.0, -22000.0)
	w.step()
	assert_bool(KnowledgeSystem.is_detected(w, BLUE_FACTION, FAR)).is_true()
	assert_bool(KnowledgeSystem.is_detected(w, RED_FACTION, FAR)).is_false()
	assert_str(KnowledgeSystem.callsign(w, BLUE_FACTION, FAR)).is_equal("U3")
	assert_str(KnowledgeSystem.callsign(w, RED_FACTION, FAR)).is_equal("U1")
	var red_after: Array = numbers_of(w, RED_FACTION)
	# Only RED's "detected" flag for FAR changed (column 2: detected).
	var detected_before: Array = red_before[2][1]
	detected_before[0] = 0
	assert_array(red_after).is_equal(red_before)


# FT: FT-TST-013, FT-ARC-012, FT-M1-014
# Mid-fight, with projectiles of both corvettes in flight, every state container holds
# rows keyed by both ships' ids with their factions; knowledge rows are keyed by the
# contact's id and the observing faction, so RED's knowledge of BLUE and BLUE's of RED
# both exist.
func test_every_container_keys_both_ships() -> void:
	var w: SimWorld = build()
	var red_crew: ScriptedCrew = ScriptedCrew.new(RED, BLUE)
	var blue_crew: ScriptedCrew = HalfRateCrew.new(BLUE, RED)
	for i: int in 200:
		red_crew.act(w)
		blue_crew.act(w)
		w.step()
	for t: SimTable in w.tables():
		var name: String = t.get_script().get_global_name()
		for ship: int in [RED, BLUE]:
			assert_int(t.rows_of(ship).size()).override_failure_message(name).is_greater(0)
		for r: int in t.size():
			var own: int = w.faction_of(t.ship_ids[r])
			if t == w.knowledge:
				assert_int(t.factions[r]).is_not_equal(own)
			else:
				assert_int(t.factions[r]).override_failure_message(name).is_equal(own)
	assert_int(w.knowledge.row_for(RED_FACTION, BLUE)).is_greater_equal(0)
	assert_int(w.knowledge.row_for(BLUE_FACTION, RED)).is_greater_equal(0)


## Resets BLUE (destroyed) and checks the per-ship run reset (FT-GEN-002). Scope:
## - BLUE's own rows (kinematics, helm, power, shields, mounts, damage, AI, run) equal
##   a fresh world's BLUE rows; its projectiles in flight are dropped.
## - Other factions' knowledge rows about BLUE keep their callsign number and
##   identification (FT-SPA-001: a number never changes) and drop to undetected until
##   the next knowledge step.
## - BLUE's faction's knowledge (rows observed by BLUE_FACTION) is faction state shared
##   by allies (FT-ARC-018), not one ship's run state: kept.
## - Everything else is unchanged: every row of RED and the neutrals, RED's projectiles
##   in flight, RED's WIN, the tick, the RNG states and the relations.
func reset_blue_and_check(w: SimWorld) -> void:
	var is_blue: Callable = func(t: SimTable, r: int) -> bool: return t.ship_ids[r] == BLUE
	var others: Array = not_blue(w)
	var about_blue: Array = rows(w.knowledge, is_blue)
	var tick: int = w.tick
	var rng_states: Array = w.rng.states()
	var relations: Array = relations_of(w)
	var hash_before: String = w.state_hash()
	w.reset_ship(BLUE, SITE, BLUE_OFFSET, _facing_red())
	assert_array(blue_rows(w)).is_equal(blue_rows(build()))
	assert_int(w.projectiles.rows_of(BLUE).size()).is_equal(0)
	assert_array(not_blue(w)).is_equal(others)
	# Knowledge about BLUE: [ship_ids, factions, detected, identified, numbers].
	(about_blue[2][1] as Array).fill(0)
	assert_array(rows(w.knowledge, is_blue)).is_equal(about_blue)
	assert_int(w.tick).is_equal(tick)
	assert_array(w.rng.states()).is_equal(rng_states)
	assert_array(relations_of(w)).is_equal(relations)
	assert_str(w.state_hash()).is_not_equal(hash_before)
	# BLUE is back in play, RED keeps its WIN and re-detects BLUE under the same callsign.
	w.step()
	assert_int(w.run.status[BLUE]).is_equal(RunTable.Status.IN_PLAY)
	assert_int(w.run.outcome[BLUE]).is_equal(RunTable.Outcome.NONE)
	assert_int(w.run.outcome[RED]).is_equal(RunTable.Outcome.WIN)
	assert_bool(KnowledgeSystem.is_detected(w, RED_FACTION, BLUE)).is_true()
	assert_str(KnowledgeSystem.callsign(w, RED_FACTION, BLUE)).is_equal("H2")


## BLUE destroyed: DESTROYED with LOSS, RED in play with WIN, the neutrals without an
## outcome (no faction is hostile to them); one &"outcome" event each for the corvettes.
func check_outcomes(w: SimWorld, events: Array[SimEvent]) -> void:
	assert_bool(w.kin.is_alive(RED)).is_true()
	assert_int(w.run.status[BLUE]).is_equal(RunTable.Status.DESTROYED)
	assert_int(w.run.outcome[BLUE]).is_equal(RunTable.Outcome.LOSS)
	assert_int(w.run.status[RED]).is_equal(RunTable.Status.IN_PLAY)
	assert_int(w.run.outcome[RED]).is_equal(RunTable.Outcome.WIN)
	for n: int in [FAR, NEAR]:
		assert_int(w.run.status[n]).is_equal(RunTable.Status.IN_PLAY)
		assert_int(w.run.outcome[n]).is_equal(RunTable.Outcome.NONE)
	var outcomes: Array = []
	for e: SimEvent in events:
		if e.kind == &"outcome":
			outcomes.append([e.ship_id, e.faction, e.tag])
	assert_array(outcomes).contains_exactly_in_any_order(
		[[BLUE, BLUE_FACTION, &"loss"], [RED, RED_FACTION, &"win"]]
	)


# FT: FT-TST-013, FT-GEN-002, FT-M1-014
# The crews fight until BLUE is destroyed (its weapons go first, so it has no shots left
# in flight; RED's are): outcomes as in check_outcomes, then the reset of BLUE alone as
# in reset_blue_and_check.
func test_destroyed_in_combat_loses_and_resets_alone() -> void:
	var w: SimWorld = build()
	var events: Array[SimEvent] = fight(w)
	check_outcomes(w, events)
	assert_float(w.damage.health[w.damage.hull_row(RED)]).is_less(w.defs[RED].hull_max)
	assert_int(w.projectiles.rows_of(RED).size()).is_greater(0)
	reset_blue_and_check(w)


# FT: FT-TST-013, FT-GEN-002, FT-M1-014
# BLUE destroyed by a forced hit (DamageSystem.apply_hit) while both corvettes have
# shots in flight: the same outcomes; the reset drops BLUE's shots and keeps RED's.
func test_destroyed_by_forced_hit_resets_alone() -> void:
	var w: SimWorld = build()
	var red_crew: ScriptedCrew = ScriptedCrew.new(RED, BLUE)
	var blue_crew: ScriptedCrew = HalfRateCrew.new(BLUE, RED)
	var events: Array[SimEvent] = []
	while (
		(w.projectiles.rows_of(RED).is_empty() or w.projectiles.rows_of(BLUE).is_empty())
		and w.tick < 10 * HZ
	):
		red_crew.act(w)
		blue_crew.act(w)
		w.step()
		events.append_array(w.drain_events())
	assert_int(w.tick).override_failure_message("no shots in flight").is_less(10 * HZ)
	var hit: SimHit = SimHit.new()
	hit.target_id = BLUE
	hit.source_id = RED
	hit.kind = &"projectile"
	# Twice the hull: the hull takes (1 - subsystem_damage_share) of it.
	var def: ShipDef = w.defs[BLUE]
	DamageSystem.apply_hit(w, hit, 2.0 * def.hull_max / (1.0 - def.subsystem_damage_share))
	w.step()
	events.append_array(w.drain_events())
	check_outcomes(w, events)
	assert_int(w.projectiles.rows_of(BLUE).size()).is_greater(0)
	assert_int(w.projectiles.rows_of(RED).size()).is_greater(0)
	reset_blue_and_check(w)


## The whole scenario: fight, reset BLUE, 300 more ticks of fire. Returns the state
## hashes after the fight, after the reset and at the end.
func scenario_hashes(world_seed: int) -> PackedStringArray:
	var w: SimWorld = build(world_seed)
	fight(w)
	var out: PackedStringArray = [w.state_hash()]
	w.reset_ship(BLUE, SITE, BLUE_OFFSET, _facing_red())
	out.append(w.state_hash())
	var red_crew: ScriptedCrew = ScriptedCrew.new(RED, BLUE)
	var blue_crew: ScriptedCrew = HalfRateCrew.new(BLUE, RED)
	for i: int in 300:
		red_crew.act(w)
		blue_crew.act(w)
		w.step()
	out.append(w.state_hash())
	out.append(str(w.tick))
	return out


# FT: FT-TST-013, FT-M1-014
# The PvP scenario (fight, reset, more fire) run twice with the same seed gives equal
# state hashes at every checkpoint.
func test_pvp_scenario_deterministic() -> void:
	var first: PackedStringArray = scenario_hashes(SEED)
	assert_array(Array(scenario_hashes(SEED))).is_equal(Array(first))
