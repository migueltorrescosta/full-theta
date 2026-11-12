extends GdUnitTestSuite
## Review 2026-11-08 B1 and E6 (R09-8, R18-1): which target the enemy AI picks, what it does
## when the target dies, and that it sends its face point and aim only when they change.
## The M1 raider enemy (faction 2) at the origin; M1 corvettes (faction 1) a few km away.

const HZ: int = SimWorld.HZ


## World recording every submitted command, to inspect the AI's.
class RecordingWorld:
	extends SimWorld

	var submitted: Array[SimCommand] = []

	func _init(world_seed: int = 0) -> void:
		super(world_seed)

	func submit(command: SimCommand) -> void:
		submitted.append(command)
		super(command)


func _tough() -> ShipDef:
	var def: ShipDef = TestDefs.corvette().duplicate()
	def.hull_max = 1e12
	return def


# FT: FT-SIM-027
# The AI targets the nearest detected hostile; at equal distance the lower id wins.
func test_picks_the_nearest_hostile_and_ties_go_to_the_lower_id() -> void:
	var world: SimWorld = SimWorld.new(3)
	world.spawn_ship(_tough(), 1, CubePoint.make(3000.0, 0.0, 0.0))
	world.spawn_ship(_tough(), 1, CubePoint.make(0.0, 0.0, -2000.0))
	var raider: int = world.spawn_npc(TestDefs.raider_enemy(), 2)
	SimFixture.run(world, 5)
	assert_int(world.ai.target[raider]).is_equal(1)
	var tie: SimWorld = SimWorld.new(3)
	tie.spawn_ship(_tough(), 1, CubePoint.make(0.0, 0.0, -2500.0))
	tie.spawn_ship(_tough(), 1, CubePoint.make(0.0, 0.0, 2500.0))
	var other: int = tie.spawn_npc(TestDefs.raider_enemy(), 2)
	SimFixture.run(tie, 5)
	assert_int(tie.ai.target[other]).is_equal(0)


# FT: FT-SIM-027
# When the target is destroyed the AI returns to HOLD, drops its selection and all-stops.
func test_target_destroyed_returns_to_hold_and_stops() -> void:
	var world: SimWorld = SimWorld.new(5)
	world.spawn_ship(_tough(), 1, CubePoint.make(0.0, 0.0, 4000.0))
	var raider: int = world.spawn_npc(TestDefs.raider_enemy(), 2)
	SimFixture.run(world, 20 * HZ)
	assert_int(world.ai.mode[raider]).is_not_equal(AiTable.Mode.HOLD)
	DamageSystem.damage_hull(world, 0, 1e13)
	SimFixture.run(world, 3 * HZ)
	assert_int(world.ai.mode[raider]).is_equal(AiTable.Mode.HOLD)
	assert_int(world.ai.target[raider]).is_equal(-1)
	assert_int(world.helm.sel_kind[raider]).is_equal(HelmTable.Selection.NONE)
	SimFixture.run(world, 30 * HZ)
	assert_float(world.kin.vel[raider].length()).is_less(0.5)


# FT: FT-SIM-029
# Against a still target that it has settled on, the AI does not resend its face point or
# mount aims every tick: far fewer than one command per tick (R18-1).
func test_ai_resends_face_point_and_aim_only_when_they_change() -> void:
	var world: RecordingWorld = RecordingWorld.new(11)
	world.spawn_ship(_tough(), 1, CubePoint.make(0.0, 0.0, -5000.0))
	world.spawn_npc(TestDefs.raider_enemy(), 2)
	SimFixture.run(world, 60 * HZ)
	world.submitted.clear()
	SimFixture.run(world, 10 * HZ)
	var sent: int = 0
	for c: SimCommand in world.submitted:
		if c.source == SimCommand.Source.AI and (c is HelmSelectCommand or c is AimMountCommand):
			sent += 1
	assert_int(sent).override_failure_message("sent %d" % sent).is_less(60)
