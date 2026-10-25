extends GdUnitTestSuite
## The main screen's switch rule, the objectives list and what any number of viewers cost:
## one shared message per snapshot, however many watch (FT-MSC-004, FT-MSC-005,
## FT-MSC-006).

const ENEMY: int = M1Encounter.ENEMY_SHIP
const PLAYER: int = M1Encounter.PLAYER_SHIP


func _world() -> SimWorld:
	return M1Encounter.new(3, "test", TestDefs.corvette(), TestDefs.raider_enemy()).build()


# FT: FT-MSC-005, FT-RLY-010, FT-CPT-001
func test_only_the_captain_and_then_relay_switch() -> void:
	var views: int = MainScreen.NAMES.size()
	assert_int(views).is_equal(5)
	for v: int in views:
		assert_str(MainScreen.rule(CrewMarks.Role.CAPTAIN, v, true)).is_empty()
		assert_str(MainScreen.rule(CrewMarks.Role.CAPTAIN, v, false)).is_empty()
		assert_str(MainScreen.rule(CrewMarks.Role.RELAY, v, false)).is_empty()
		assert_str(MainScreen.rule(CrewMarks.Role.RELAY, v, true)).is_equal(
			MainScreen.CAPTAIN_SEATED
		)
		for role: CrewMarks.Role in [CrewMarks.Role.CREW, CrewMarks.Role.NONE]:
			for seated: bool in [true, false]:
				assert_str(MainScreen.rule(role, v, seated)).is_equal(CommandGate.NOT_ALLOWED)
	assert_str(MainScreen.rule(CrewMarks.Role.CAPTAIN, views, false)).is_equal(MainScreen.BAD_VIEW)
	assert_str(MainScreen.rule(CrewMarks.Role.CAPTAIN, -1, false)).is_equal(MainScreen.BAD_VIEW)


# FT: FT-MSC-006
# The encounter's objective is "stop the hostile ships" with how many are left, and
# is gone once the ship has its outcome.
func test_objectives_count_the_hostile_ships_in_play() -> void:
	var world: SimWorld = _world()
	assert_int(StationViews.OBJECTIVE_DESTROY_HOSTILES).is_equal(Objectives.Kind.DESTROY_HOSTILES)
	var rows: Array[Dictionary] = Objectives.of_ship(world, PLAYER)
	assert_int(rows.size()).is_equal(1)
	assert_int(rows[0]["kind"]).is_equal(Objectives.Kind.DESTROY_HOSTILES)
	assert_int(rows[0]["left"]).is_equal(1)
	world.run.status[ENEMY] = RunTable.Status.DESTROYED
	assert_int(Objectives.of_ship(world, PLAYER).size()).is_equal(0)
	world.run.status[ENEMY] = RunTable.Status.IN_PLAY
	world.run.outcome[PLAYER] = RunTable.Outcome.WIN
	assert_int(Objectives.of_ship(world, PLAYER).size()).is_equal(0)


# FT: FT-MSC-004, FT-MSC-006
# Viewer scaling: sixty viewers on a ship take one message per snapshot (the same
# buffers), and that message, status block included, stays small.
func test_sixty_viewers_share_one_small_message() -> void:
	var world: SimWorld = _world()
	var b: SnapshotBuilder = SnapshotBuilder.new()
	var key: String = StationViews.key(PLAYER, StationViews.VIEWER)
	world.step()
	world.step()
	world.drain_events()
	b.build(SimCopy.of(world), 1, [key])
	b.take_counts()
	var first: Array[PackedByteArray] = b.chunks(key, true)
	for i: int in 59:
		assert_bool(is_same(b.chunks(key, true), first)).is_true()
	assert_int(b.take_counts()["full_messages"]).is_equal(1)
	var bytes: int = 0
	for c: PackedByteArray in first:
		bytes += c.size()
	assert_int(bytes).is_less(2048)
	# The status block is in it: the viewer's view holds subsystem rows and an objective.
	var state: NetViewState = NetViewState.new(NetCodec.period_units(world.kin.period))
	var msg: PackedByteArray = b.message(key, true)
	assert_bool(state.apply(msg)).is_true()
	var block: Dictionary = state.blocks[StationViews.Section.CAPTAIN]
	assert_int((block["subsystems"] as Array).size()).is_greater(0)
	assert_int((block["objectives"] as Array).size()).is_equal(1)
