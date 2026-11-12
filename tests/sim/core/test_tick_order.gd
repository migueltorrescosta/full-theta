# FT: FT-ARC-008
extends GdUnitTestSuite
## R09-13: the system order inside one SimWorld.step is part of the determinism contract
## (FT-ARC-008), and the golden replay alone pins it. Each test checks one dependency
## the comments in `step` state, behaviourally, and says why it would fail if the two
## systems were swapped. M1 corvette: 50 t, hull 1e8 J, subsystem share 0.5, engines
## envelope 1.5 at 4 pips, shields 3e7 J regenerating 5e5 J/s, repair 2e5 J/s per crew.

const ME: int = 0
const FOE: int = 1


func _world() -> SimWorld:
	var w: SimWorld = SimWorld.new(1, "test")
	w.spawn_ship(TestDefs.corvette(), 1, CubePoint.make())
	return w


func _submit(w: SimWorld, c: SimCommand) -> void:
	c.ship_id = ME
	w.submit(c)


## A hit on the corvette with ship-frame direction and point.
func _hit(w: SimWorld, energy: float, from_local: Vector3, point: Vector3 = Vector3.ZERO) -> void:
	var hit: SimHit = SimHit.new()
	hit.target_id = ME
	hit.kind = &"projectile"
	hit.from_local = from_local
	hit.point_local = point
	hit.energy = energy
	w.hits.append(hit)


## Speed gained in one tick of full decoupled forward thrust, with or without raising
## the engines to 4 pips in the same tick.
func _one_tick_dv(raise_engines: bool) -> float:
	var w: SimWorld = _world()
	_submit(w, DecoupledCommand.new())
	var helm: HelmInputCommand = HelmInputCommand.new()
	helm.throttle = 1.0
	_submit(w, helm)
	if raise_engines:
		var pips: SetPipsCommand = SetPipsCommand.new()
		pips.subsystem_kind = SubsystemDef.Kind.ENGINES
		pips.pips = 4
		_submit(w, pips)
	w.step()
	return w.kin.vel[ME].length()


# FT: FT-SIM-006, FT-SIM-026
# Power writes the envelope before Assist and the Integrator, so a SetPips moves the
# ship on the tick it applies: the first tick's speed gain is 1.5 times the nominal
# one. Swapped (Integrator before Power), that tick would still use the previous
# envelope (1.0) and the ratio would be 1.
func test_set_pips_reaches_the_same_ticks_motion() -> void:
	var nominal: float = _one_tick_dv(false)
	var raised: float = _one_tick_dv(true)
	assert_float(nominal).is_greater(0.0)
	assert_float(raised / nominal).is_equal_approx(1.5, 1e-6)


# FT: FT-SCI-008
# Science runs first, so a hack window open at the start of a tick scales that tick's
# power: the engines' hack factor is in the thrust envelope after one step. Swapped
# (Power before Science), the first tick would compute the envelope from the old
# hack_scale (1) and only the next tick would show the hack.
func test_hack_window_feeds_the_same_ticks_power() -> void:
	var w: SimWorld = _world()
	w.step()
	assert_float(w.kin.thrust_scale[ME]).is_equal(1.0)
	var engines: int = SimFixture.sub_index(w, ME, &"engines")
	w.hacks.open(ME, 2, engines, 0.5, w.tick + 60, FOE)
	w.damage.hack_dirty = true
	w.step()
	assert_float(w.kin.thrust_scale[ME]).is_less(1.0)


# FT: FT-SIM-028
# Knowledge runs before the AI, and the AI's commands apply on the next tick: the
# raider submits commands on its first tick (it already detects the corvette), they
# wait in the queue unapplied, and the next step applies them with its own tick.
# Swapped (AI before _apply_commands), they would apply on the tick they were made;
# swapped with Knowledge, the first tick would see no contact and stay in HOLD.
func test_ai_commands_apply_next_tick() -> void:
	var w: SimWorld = _world()
	w.spawn_npc(TestDefs.raider_enemy(), 2, CubePoint.make(0, 0, -3000.0))
	var first: int = w.tick
	w.step()
	assert_int(w.ai.mode[FOE]).is_not_equal(AiTable.Mode.HOLD)
	var ai: Array[SimCommand] = w.queued_commands().filter(
		func(c: SimCommand) -> bool: return c.source == SimCommand.Source.AI
	)
	assert_int(ai.size()).is_greater(0)
	for c: SimCommand in ai:
		assert_int(c.tick).is_equal(-1)
	w.step()
	for c: SimCommand in ai:
		assert_int(c.tick).is_equal(first + 1)


# FT: FT-SIM-018, FT-SIM-019
# Hits resolve before ShieldSystem.step: a hit uses the focus of the previous tick's
# tracking (one-tick lag) and comes off strength before this tick's regeneration. The
# corvette tracks a ship that moves to starboard; a starboard hit that tick passes as
# much energy as with the old forward focus, and the focus turns starboard afterwards.
# From full strength, the regeneration after the hit adds back regen * DT. Swapped
# (Shield before hits), the hit would meet the starboard focus (absorbing more), and
# the regeneration would be capped at full before the hit, leaving max - absorbed.
func test_hits_resolve_before_shield_step() -> void:
	var w: SimWorld = _world()
	var other: int = w.spawn_ship(TestDefs.corvette(), 1, CubePoint.make(0, 0, -1000.0))
	var tight: SetShieldCommand = SetShieldCommand.new()
	tight.power = -1
	tight.tightness = 4.0
	_submit(w, tight)
	var focus: SetShieldFocusCommand = SetShieldFocusCommand.new()
	focus.track_id = other
	_submit(w, focus)
	w.step()
	assert_vector(w.shields.focus[ME]).is_equal_approx(Vector3.FORWARD, Vector3.ONE * 1e-6)
	var top: float = w.defs[ME].shields.max_strength
	w.shields.strength[ME] = top
	var energy: float = 1e6
	var expected: float = energy * (1.0 - ShieldSystem.absorb_fraction(w, ME, Vector3.RIGHT))
	w.kin.place(other, CubePoint.make(1000.0, 0.0, 0.0))
	_hit(w, energy, Vector3.RIGHT)
	w.drain_events()
	w.step()
	var hits: Array[SimEvent] = SimFixture.of_kind(w.drain_events(), &"hit")
	assert_int(hits.size()).is_equal(1)
	assert_float(hits[0].value).is_equal_approx(expected, 1e-6)
	assert_vector(w.shields.focus[ME]).is_equal_approx(Vector3.RIGHT, Vector3.ONE * 1e-6)
	var regen: float = w.defs[ME].shields.regen_rate * ShieldSystem.power(w, ME) * SimWorld.DT
	assert_float(regen).is_greater(0.0)
	assert_float(w.shields.strength[ME]).is_equal_approx(top - (energy - expected) + regen, 1e-6)


# FT: FT-SIM-020, FT-SIM-024
# DamageSystem.step (repairs) runs after the hits: a crew 1000 J short of finishing
# (one tick's repair is 3333 J) whose subsystem is hit that tick does not finish, stays
# on it, and the health is the damaged value plus one tick's repair. Swapped (repair
# before hits), the repair would finish first (repair_finished, crew freed) and the
# hit would then damage an unattended subsystem.
func test_repair_runs_after_hits() -> void:
	var w: SimWorld = _world()
	var row: int = w.damage.find_subsystem(ME, &"engines")
	var sd: SubsystemDef = w.defs[ME].subsystems[SimFixture.sub_index(w, ME, &"engines")]
	w.damage.health[row] = sd.health_max - 1e6
	var c: DispatchRepairCommand = DispatchRepairCommand.new()
	c.crew = 0
	c.subsystem_id = &"engines"
	_submit(w, c)
	w.step()
	assert_int(w.damage.crews[row]).is_not_equal(0)
	w.damage.health[row] = sd.health_max - 1000.0
	w.shields.strength[ME] = 0.0
	# Below the fault threshold (1.5 MJ), so no fault draw; half goes to the engines.
	var energy: float = 2e5
	_hit(w, energy, Vector3.FORWARD, sd.position)
	w.drain_events()
	w.step()
	var events: Array[SimEvent] = w.drain_events()
	assert_int(SimFixture.of_kind(events, &"repair_finished").size()).is_equal(0)
	assert_int(w.damage.crews[row]).is_not_equal(0)
	var gain: float = sd.repair_rate * SimWorld.DT
	assert_float(w.damage.health[row]).is_equal_approx(
		sd.health_max - 1000.0 - energy * w.defs[ME].subsystem_damage_share + gain, 1e-3
	)


# FT: FT-M1-012
# OutcomeSystem runs last, so it sees this tick's destructions: a crewed ship destroyed
# by a hit is DESTROYED with its LOSS outcome on the same tick. Swapped (Outcome before
# the hits), the status and the outcome would lag one tick.
func test_outcome_sees_this_ticks_destruction() -> void:
	var w: SimWorld = _world()
	w.shields.strength[ME] = 0.0
	_hit(w, 1e10, Vector3.FORWARD)
	w.step()
	assert_int(w.kin.alive[ME]).is_equal(0)
	assert_int(w.ships.status[ME]).is_equal(ShipStateTable.Status.DESTROYED)
	assert_int(w.ships.ship_outcome[ME]).is_equal(ShipStateTable.ShipOutcome.LOSS)
	var outcomes: Array[SimEvent] = SimFixture.of_kind(w.drain_events(), &"outcome")
	assert_int(outcomes.size()).is_equal(1)
	assert_int(outcomes[0].tick).is_equal(w.tick - 1)
