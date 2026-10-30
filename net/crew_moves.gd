class_name CrewMoves
extends RefCounted
## What a scripted crewman does at a station, as commands (FT-TST-022, D303): the moves the
## bot batch (tools/bots/bot_crew.gd) and the bots of a solo lesson (TrainingCrew) share.
## Each returns a command for the caller to stamp with a ship and submit, or null when
## there is nothing to do. Reads true state, as a crew with a radar lock would.


## The nearest living hostile of the ship's faction that it detects within `range_m`
## (any, or only armed ones), or -1.
static func nearest_hostile(
	world: SimWorld, ship: int, range_m: float, armed_only: bool = false
) -> int:
	var faction: int = world.faction_of(ship)
	var best: int = -1
	var best_d: float = INF
	for id: int in world.ship_count():
		if id == ship or not world.ai.is_enabled(id) or not world.kin.is_alive(id):
			continue
		if world.run.status[id] != RunTable.Status.IN_PLAY:
			continue
		if world.relation(faction, world.faction_of(id)) != SimWorld.Relation.HOSTILE:
			continue
		if not KnowledgeSystem.is_detected(world, faction, id):
			continue
		if armed_only and world.defs[id].mounts.is_empty():
			continue
		var d: float = world.kin.relative(ship, id).length()
		if d <= range_m and d < best_d:
			best = id
			best_d = d
	return best


## Engineering: sends the first idle repair crew to the most damaged subsystem no crew is
## working on (below 80 % health), or null.
static func repair(world: SimWorld, ship: int) -> DispatchRepairCommand:
	var def: ShipDef = world.defs[ship]
	var table: DamageTable = world.damage
	var busy: int = 0
	var worst: StringName = &""
	var worst_frac: float = 0.8
	for sub: SubsystemDef in def.subsystems:
		var row: int = table.find_subsystem(ship, sub.id)
		busy |= table.crews[row]
		var frac: float = table.health[row] / sub.health_max
		if frac < worst_frac and table.crews[row] == 0:
			worst = sub.id
			worst_frac = frac
	if worst == &"":
		return null
	for crew: int in def.repair_crews:
		if busy & (1 << crew) == 0:
			var dispatch: DispatchRepairCommand = DispatchRepairCommand.new()
			dispatch.crew = crew
			dispatch.subsystem_id = worst
			return dispatch
	return null


## Weapons: aims mount 0 at the target's lead point. `aim_error` (rad, a random direction
## drawn from `rng`) spoils the aim; 0 is a perfect lead.
static func aim(
	world: SimWorld,
	ship: int,
	target: int,
	aim_error: float = 0.0,
	rng: RandomNumberGenerator = null
) -> AimMountCommand:
	var kin: Kinematics = world.kin
	var lead: Vector3 = EnemyAi.lead_aim(world, ship, 0, target, 0)
	if not lead.is_finite():
		lead = kin.relative(ship, target)
	if aim_error > 0.0 and rng != null:
		var miss: Vector3 = Vector3(
			rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0)
		)
		lead += miss * (aim_error * lead.length())
	var c: AimMountCommand = AimMountCommand.new()
	c.aim_x = kin.px[ship] + lead.x
	c.aim_y = kin.py[ship] + lead.y
	c.aim_z = kin.pz[ship] + lead.z
	return c
