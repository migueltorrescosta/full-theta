extends GdUnitTestSuite
## The stand-in bots (StandInCrew, #40 D1, gp-01): a novice crewman on a bot-held station acts
## only through the ApiCrew verbs (the command log records it, so a run replays), with the
## StandInDef's numbers.

const SHIP: int = M1Encounter.PLAYER_SHIP
const RAIDER: int = M1Encounter.ENEMY_SHIP


func _world() -> SimWorld:
	var m1: M1Encounter = M1Encounter.new(5, "test", TestDefs.corvette(), TestDefs.raider_enemy())
	return m1.build()


## Steps the world `ticks` ticks with the crew acting for `stations` before each.
func _run(world: SimWorld, crew: StandInCrew, stations: Array, ticks: int) -> ScenarioHost:
	var host: ScenarioHost = ScenarioHost.new(world)
	host.api().crew().record = true
	for i: int in ticks:
		host.advance(1.0 / SimRate.HZ, func(api: ScenarioApi) -> void: crew.act(api, stations))
	return host


## The ticks of the recorded commands of `kind`.
static func _ticks_of(host: ScenarioHost, kind: StringName) -> Array:
	return (
		host
		. api()
		. crew()
		. sent
		. filter(func(row: Array) -> bool: return row[1] == kind)
		. map(func(row: Array) -> int: return row[0])
	)


# FT: FT-NET-047
# A Weapons stand-in aims at the raider in sight at once and fires within a few seconds of
# its reaction time, never before it, and only Weapons commands go out for that station.
func test_weapons_stand_in_fires_after_its_reaction() -> void:
	var def: StandInDef = StandInDef.new()
	var world: SimWorld = _world()
	var start: int = world.tick
	var host: ScenarioHost = _run(
		world, StandInCrew.new(def, SHIP, 7), ["weapons"], 12 * SimRate.HZ
	)
	assert_array(_ticks_of(host, &"aim_mount")).is_not_empty()
	var shots: Array = _ticks_of(host, &"fire")
	assert_array(shots).is_not_empty()
	assert_int(int(shots[0]) - start).is_greater_equal(SimRate.ticks(def.reaction_s))
	assert_int(int(shots[0]) - start).is_less(SimRate.ticks(def.reaction_s + 2.0))
	for row: Array in host.api().crew().sent:
		assert_str(StationCatalogue.station_of_command(row[1])).is_equal("weapons")


# FT: FT-NET-047
# A Helm stand-in turns to face the nearest hostile (Face held on it, the contact selected)
# within its first look.
func test_helm_stand_in_faces_the_hostile() -> void:
	var def: StandInDef = StandInDef.new()
	var world: SimWorld = _world()
	var host: ScenarioHost = _run(
		world, StandInCrew.new(def, SHIP, 7), ["helm"], SimRate.ticks(def.look_s) + 2
	)
	assert_int(world.helm.face_held[SHIP]).is_equal(1)
	assert_array(_ticks_of(host, &"helm_select")).is_not_empty()
	for row: Array in host.api().crew().sent:
		assert_str(StationCatalogue.station_of_command(row[1])).is_equal("helm")


# FT: FT-NET-047
# The same seed gives the same commands (a run with stand-ins replays).
func test_stand_ins_are_deterministic() -> void:
	var sent: Array = []
	for i: int in 2:
		var host: ScenarioHost = _run(
			_world(), StandInCrew.new(StandInDef.new(), SHIP, 3), ["helm", "weapons"], 600
		)
		sent.append(host.api().crew().sent.duplicate(true))
	assert_array(sent[0]).is_not_empty()
	assert_array(sent[1]).is_equal(sent[0])


# FT: FT-DAT-002
# The shipped stand-in definition validates.
func test_stand_in_def_validates() -> void:
	var def: StandInDef = load("res://content/runs/stand_in.tres") as StandInDef
	assert_object(def).is_not_null()
	assert_array(def.validate()).is_empty()
	def.fire_skip = 2.0
	assert_array(def.validate()).is_not_empty()
