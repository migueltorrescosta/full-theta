class_name P2Scenario
extends RefCounted
## P2 Helm + Weapons pair scenario (spec §7.4, FT-PAIR-015): a raider crosses the bow
## 1.5 km to port, 1 km ahead at the start, at 30 m/s, and Weapons must put DAMAGE_GOAL
## joules into it. The corvette's one mass driver has a 15 degree half-arc.
## - Weapons (both variants): the gunner aims at the raider's lead point and fires
##   whenever the mount is ready and the raider is inside its arc (Gunnery.gun).
## - Helm (co-op only): selects the raider and holds Face, so the bow follows it and
##   Weapons has the target in arc from the first seconds.
## - Solo: nobody turns the ship, so the raider is in arc only while it crosses the bow
##   line (FT-PAIR-004).
## Metric: time (s) until the raider has lost DAMAGE_GOAL.

const SEED: int = 41
const PLAYER: int = 0
const RAIDER: int = 1
const START: Vector3 = Vector3(-1500.0, 0.0, -1000.0)
const VELOCITY: Vector3 = Vector3(30.0, 0.0, 0.0)
## Damage the raider must take (J): ten mass-driver hits.
const DAMAGE_GOAL: float = 20000000.0
const TICK_LIMIT: int = 120 * SimWorld.HZ


static func harness() -> PairHarness:
	return PairHarness.new(build, raider, done, measure, TICK_LIMIT)


static func build() -> SimWorld:
	var w: SimWorld = SimWorld.new(SEED, "p2")
	w.set_relation(1, 2, SimWorld.Relation.HOSTILE)
	w.spawn_ship(TestDefs.corvette(), 1, 0)
	var raider: int = w.spawn_ship(
		Gunnery.raider_with_shields(0.0), 2, 0, START, Quaternion.IDENTITY, VELOCITY
	)
	w.shields.strength[raider] = 0.0
	return w


## The raider (both variants): coasts on past the corvette, flight assist off.
static func raider(w: SimWorld) -> void:
	if w.tick == 0:
		var coast: DecoupledCommand = DecoupledCommand.new()
		coast.ship_id = RAIDER
		w.submit(coast)


static func done(w: SimWorld) -> bool:
	return Gunnery.lost(w, RAIDER) >= DAMAGE_GOAL


static func measure(w: SimWorld) -> Dictionary:
	return {"time": w.tick * SimWorld.DT}


static func solo(w: SimWorld) -> void:
	weapons(w)


static func coop(w: SimWorld) -> void:
	helm(w)
	weapons(w)


## Helm: select the raider (a contact after the first tick's sweep) and hold Face.
static func helm(w: SimWorld) -> void:
	if w.tick == 1:
		var select: SelectTargetCommand = SelectTargetCommand.new()
		select.ship_id = PLAYER
		select.target_ship = RAIDER
		w.submit(select)
		var input: HelmInputCommand = HelmInputCommand.new()
		input.ship_id = PLAYER
		input.face = true
		w.submit(input)


## Weapons: the lead point of the raider for the mass driver, from tick 2 on.
static func weapons(w: SimWorld) -> void:
	if w.tick < 2:
		return
	var aim: Vector3 = EnemyAi.lead_aim(w, PLAYER, 0, RAIDER, 0)
	if not aim.is_finite():
		return
	var at: Vector3 = Vector3(w.kin.px[PLAYER], w.kin.py[PLAYER], w.kin.pz[PLAYER])
	Gunnery.gun(w, PLAYER, at + aim)
