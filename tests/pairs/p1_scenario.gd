class_name P1Scenario
extends RefCounted
## P1 Engineering + Helm pair scenario (spec §7.4, FT-PAIR-015, FT-M1-010): the M1
## corvette, at rest with its bow on -Z, must turn 90 degrees to port and sprint 2 km to
## an intercept point while a raider abeam to starboard fires on it, so after the turn
## the fire comes from dead astern, a known direction.
## - Helm (both variants): selects the point, holds Face, throttles up once the bow is on
##   the point and points the shield focus at the raider by tracking it (D16, D48).
## - Engineering (co-op only): boosts engines and thrusters for 8 s (D117), takes the
##   weapons' 2 pips and the reactor's 2 spare ones to overcharge the engines (4 pips,
##   envelope 1.5 after the boost too) and the shields (4 pips, power 2), sets the
##   tightest focus (D118), and drops the engines back to nominal pips once their heat
##   passes HEAT_GUARD of the fault threshold, so no fault fires (FT-SIM-026).
## - Solo: Engineering sends nothing: nominal envelope, spread shields (FT-PAIR-004).
## Metrics: time (s) from start to within CAPTURE of the point, hull lost (J), and heat
## faults (count, for the co-op's no-fault check).

const SEED: int = 39
const PLAYER: int = 0
const RAIDER: int = 1
## The intercept point (m, site frame): 2 km to port of the start.
const POINT: Vector3 = Vector3(-2000.0, 0.0, 0.0)
## The raider's position (m, site frame): 3 km to starboard.
const RAIDER_AT: Vector3 = Vector3(3000.0, 0.0, 0.0)
## Distance to the point that counts as intercepting it (m).
const CAPTURE: float = 25.0
## Helm throttles up once the bow is within this angle of the point (rad, 5 deg).
const ON_POINT: float = PI / 36.0
## Engineering keeps the engines' heat below this share of the fault threshold.
const HEAT_GUARD: float = 0.9
const TICK_LIMIT: int = 60 * SimWorld.HZ

const ENG: int = SubsystemDef.Kind.ENGINES
const WPN: int = SubsystemDef.Kind.WEAPONS
const SHD: int = SubsystemDef.Kind.SHIELDS


static func harness() -> PairHarness:
	return PairHarness.new(build, raider, done, measure, TICK_LIMIT)


static func build() -> SimWorld:
	var w: SimWorld = SimWorld.new(SEED, "p1")
	w.set_relation(1, 2, SimWorld.Relation.HOSTILE)
	w.spawn_ship(TestDefs.corvette(), 1, 0)
	var facing_player: Quaternion = Quaternion(Vector3.UP, PI / 2.0)
	w.spawn_ship(TestDefs.raider(), 2, 0, RAIDER_AT, facing_player)
	return w


## The raider's gunner (both variants): the M1 scripted crew aimed at the corvette;
## it is stateless, so a fresh one per tick acts the same.
static func raider(w: SimWorld) -> void:
	ScriptedCrew.new(RAIDER, PLAYER).act(w)


static func done(w: SimWorld) -> bool:
	return w.kin.relative_to_point(PLAYER, POINT.x, POINT.y, POINT.z).length() < CAPTURE


static func measure(w: SimWorld) -> Dictionary:
	var hull_lost: float = (1.0 - DamageSystem.hull_fraction(w, PLAYER)) * w.defs[0].hull_max
	var is_fault: Callable = func(e: SimEvent) -> bool: return e.kind == &"fault"
	var faults: float = w.drain_events().filter(is_fault).size()
	return {"time": w.tick * SimWorld.DT, "hull_lost": hull_lost, "heat_faults": faults}


static func solo(w: SimWorld) -> void:
	helm(w)


static func coop(w: SimWorld) -> void:
	helm(w)
	engineering(w)


static func helm(w: SimWorld) -> void:
	if w.tick == 0:
		var select: SelectTargetCommand = SelectTargetCommand.new()
		select.site = 0
		select.x = POINT.x
		select.y = POINT.y
		select.z = POINT.z
		_submit(w, select)
		_submit(w, _helm_input(0.0))
		var focus: SetShieldFocusCommand = SetShieldFocusCommand.new()
		focus.track_id = RAIDER
		_submit(w, focus)
	var to_point: Vector3 = w.kin.relative_to_point(PLAYER, POINT.x, POINT.y, POINT.z)
	var on_point: bool = w.kin.forward(PLAYER).angle_to(to_point) < ON_POINT
	if on_point and w.helm.input_translation[PLAYER].z == 0.0:
		_submit(w, _helm_input(1.0))


static func engineering(w: SimWorld) -> void:
	if w.tick == 0:
		_submit(w, BoostCommand.new())
		_submit(w, _pips(WPN, 0))
		_submit(w, _pips(ENG, 4))
		var shields: SetShieldCommand = SetShieldCommand.new()
		shields.power = 4
		shields.tightness = w.defs[PLAYER].shields.tightness_max
		_submit(w, shields)
	var engines: int = PowerSystem.subsystem_index(w.defs[PLAYER], ENG)
	var threshold: float = w.defs[PLAYER].subsystems[engines].fault_heat_threshold
	var hot: bool = w.power.heat[PLAYER][engines] > HEAT_GUARD * threshold
	if hot and w.power.pips[PLAYER][engines] > 2:
		_submit(w, _pips(ENG, 2))


static func _helm_input(throttle: float) -> HelmInputCommand:
	var c: HelmInputCommand = HelmInputCommand.new()
	c.face = true
	c.throttle = throttle
	return c


static func _pips(kind: int, pips: int) -> SetPipsCommand:
	var c: SetPipsCommand = SetPipsCommand.new()
	c.subsystem_kind = kind
	c.pips = pips
	return c


static func _submit(w: SimWorld, c: SimCommand) -> void:
	c.ship_id = PLAYER
	w.submit(c)
