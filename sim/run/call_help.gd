class_name CallHelp
extends RefCounted
## Comms' call for help (gp-14, RunDef.call_help): once per encounter, while the ship is in
## an ACTIVE encounter with a hostile in play (an H contact, ProbeSystem.nearest_hostile),
## Comms calls a civil patrol. The call costs the CallHelpDef's reputation draw with the
## patrol's faction and makes that faction friendly to the caller's. After `delay` the
## patrol arrives `distance` off the ship's starboard side (&"help_arrived", other_id the
## first patrol ship), unless the encounter ended first; the NPC AI flies it against the
## ship's hostiles. When its encounter ends the patrol leaves: it is RETREATED and out of
## the world (&"patrol_left"). Runs after EncounterSystem, before OutcomeSystem.
##
## Events: &"help_called" (value the seconds to arrival), &"help_arrived", &"patrol_left".


static func step(world: SimWorld) -> void:
	var t: HelpTable = world.help
	for ship: int in t.size():
		if t.left[ship] > 0.0:
			_count_down(world, ship)
		elif t.patrol_for[ship] >= 0 and world.kin.is_alive(ship):
			if not _active(world, t.patrol_for[ship]):
				_leave(world, ship)


## Whether the ship may call for help now (what Comms' button shows on).
static func can_call(world: SimWorld, ship: int) -> bool:
	var def: CallHelpDef = world.run_def.call_help if world.run_def != null else null
	var e: int = world.ships.encounter[ship]
	return (
		def != null
		and world.is_crew_in_play(ship)
		and _active(world, e)
		and world.help.called[ship] != e
		and ProbeSystem.nearest_hostile(world, ship) >= 0
	)


## Calls the patrol; false when the ship can't call now (can_call).
static func call_help(world: SimWorld, ship: int) -> bool:
	if not can_call(world, ship):
		return false
	var def: CallHelpDef = world.run_def.call_help
	var t: HelpTable = world.help
	t.called[ship] = world.ships.encounter[ship]
	t.left[ship] = def.delay
	world.set_relation(def.faction, world.faction_of(ship), SimWorld.Relation.FRIENDLY)
	Reputation.change(world, ship, world.faction_of(ship), def.faction, def.rep_dist)
	world.emit(&"help_called", ship, -1, def.delay)
	return true


static func _count_down(world: SimWorld, ship: int) -> void:
	var t: HelpTable = world.help
	t.left[ship] = maxf(0.0, t.left[ship] - SimWorld.DT)
	if t.left[ship] > 0.0:
		return
	var e: int = t.called[ship]
	if not _active(world, e) or not world.kin.is_alive(ship):
		return
	var def: CallHelpDef = world.run_def.call_help
	var kin: Kinematics = world.kin
	var q: Quaternion = kin.rot[ship]
	var first: int = -1
	for i: int in def.count:
		var offset: Vector3 = q * Vector3(def.distance + 100.0 * i, 0.0, 0.0)
		var id: int = world.spawn_npc(def.npc, def.faction, kin.point_at(ship, offset), q)
		world.help.patrol_for[id] = e
		if first < 0:
			first = id
	world.emit(&"help_arrived", ship, first)


static func _leave(world: SimWorld, ship: int) -> void:
	world.help.patrol_for[ship] = -1
	world.ships.status[ship] = ShipStateTable.Status.RETREATED
	world.kin.alive[ship] = 0
	world.emit(&"patrol_left", ship)


static func _active(world: SimWorld, e: int) -> bool:
	var enc: EncounterTable = world.encounters
	return e >= 0 and e < enc.size() and enc.result[e] == EncounterTable.Result.ACTIVE
