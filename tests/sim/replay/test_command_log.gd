extends GdUnitTestSuite
## T037: CommandLog records a world's accepted commands and round-trips them through
## text exactly (FT-ARC-008).

const SETUP: Dictionary = {"player": &"m1_corvette", "enemy": &"m1_raider"}
## Floats that a decimal round trip tends to lose: -0.0, non-terminating binary
## fractions, a subnormal, the largest double inside the site grid (aim points past
## Kinematics.MAX_OFFSET are rejected) and full-mantissa values.
const AWKWARD: Array[float] = [
	-0.0, 0.1, 1.0 / 3.0, 5e-324, 199999.99999999997, 4.0796475000000005e-12, 123456.789123
]


func _world_with_commands() -> SimWorld:
	var world: SimWorld = (
		M1Encounter.new(7, "test", TestDefs.corvette(), TestDefs.raider_enemy()).build()
	)
	world.step()
	for i: int in AWKWARD.size():
		var aim: AimMountCommand = AimMountCommand.new()
		aim.ship_id = M1Encounter.PLAYER_SHIP
		aim.aim_x = AWKWARD[i]
		aim.aim_y = -AWKWARD[i] / 7.0
		aim.aim_z = AWKWARD[(i + 1) % AWKWARD.size()]
		world.submit(aim)
		var helm: HelmInputCommand = HelmInputCommand.new()
		helm.ship_id = M1Encounter.PLAYER_SHIP
		helm.rotation = Vector3(0.1, -1.0 / 3.0, 0.7) * (i + 1) / 10.0
		helm.throttle = 1.0 / (i + 3.0)
		helm.face = i % 2 == 0
		world.submit(helm)
		world.step()
	var rejected: AimMountCommand = AimMountCommand.new()
	rejected.ship_id = M1Encounter.PLAYER_SHIP
	rejected.mount_index = 99
	world.submit(rejected)
	world.step()
	return world


# FT: FT-ARC-008
# The log holds the seed, build id, setup and each crew command with the tick it was
# applied on, in application order; a rejected command is kept, marked not accepted, so
# a replay reproduces its rejection.
func test_from_world_records_commands_with_ticks() -> void:
	var world: SimWorld = _world_with_commands()
	var record: CommandLog = CommandLog.from_world(world, SETUP)
	assert_int(record.seed_value).is_equal(7)
	assert_str(record.build_id).is_equal("test")
	assert_dict(record.setup).is_equal(SETUP)
	assert_int(record.entries.size()).is_equal(2 * AWKWARD.size() + 1)
	for i: int in 2 * AWKWARD.size():
		var d: Dictionary = record.entries[i]
		assert_int(d["tick"]).is_equal(1 + i / 2)
		assert_str(d["kind"]).is_equal("aim_mount" if i % 2 == 0 else "helm_input")
		assert_bool(d["accepted"]).is_true()
	assert_bool(record.entries[-1]["accepted"]).is_false()
	assert_int(world.accepted_commands().size()).is_equal(2 * AWKWARD.size())


# FT: FT-ARC-008
# to_text() then from_text() gives back every value bit for bit (64-bit floats,
# float32 Vector3 components, -0.0, a subnormal), and the text is stable.
func test_text_round_trip_is_exact() -> void:
	var record: CommandLog = CommandLog.from_world(_world_with_commands(), SETUP)
	var text: String = record.to_text()
	var back: CommandLog = CommandLog.from_text(text)
	assert_object(back).is_not_null()
	if is_failure():
		return
	assert_int(back.seed_value).is_equal(record.seed_value)
	assert_str(back.build_id).is_equal(record.build_id)
	assert_bool(var_to_bytes(back.setup) == var_to_bytes(record.setup)).is_true()
	assert_int(back.entries.size()).is_equal(record.entries.size())
	for i: int in record.entries.size():
		var same: bool = var_to_bytes(back.entries[i]) == var_to_bytes(record.entries[i])
		assert_bool(same).override_failure_message("entry %d" % i).is_true()
	assert_str(back.to_text()).is_equal(text)
	var neg_zero: float = back.entries[0]["aim_x"]
	assert_bool(is_zero_approx(neg_zero) and signf(1.0 / neg_zero) < 0.0).is_true()


# FT: FT-ARC-008
# Commands rebuilt from the log carry their recorded tick and parameters.
func test_commands_rebuild_with_recorded_ticks() -> void:
	var world: SimWorld = _world_with_commands()
	var cmds: Array[SimCommand] = CommandLog.from_world(world).commands()
	assert_int(cmds.size()).is_equal(world.command_log.size())
	for i: int in cmds.size():
		assert_object(cmds[i].get_script()).is_same(world.command_log[i].get_script())
		assert_int(cmds[i].tick).is_equal(world.command_log[i].tick)
		var same: bool = (
			var_to_bytes(cmds[i].to_dict()) == var_to_bytes(world.command_log[i].to_dict())
		)
		assert_bool(same).is_true()


# FT: FT-ARC-008
# Malformed text, another format or an unknown command kind loads as null.
func test_from_text_rejects_bad_input() -> void:
	var good: String = CommandLog.from_world(_world_with_commands(), SETUP).to_text()
	assert_object(CommandLog.from_text(good)).is_not_null()
	assert_object(CommandLog.from_text("")).is_null()
	assert_object(CommandLog.from_text(good + "nonsense\n")).is_null()
	assert_object(CommandLog.from_text(good + "extra=AAAA\n")).is_null()
	var other_format: String = good.replace(
		CommandLog._line("format", CommandLog.FORMAT), CommandLog._line("format", 1)
	)
	assert_object(CommandLog.from_text(other_format)).is_null()
	var bogus: CommandLog = CommandLog.from_text(good)
	bogus.entries.append({"kind": &"no_such_command", "tick": 9})
	assert_object(CommandLog.from_text(bogus.to_text())).is_null()


# FT: FT-ARC-008, FT-TST-009
# replay() applies each command on its recorded tick and reproduces the world; a
# command the replayed world rejects is reported.
func test_replay_applies_on_recorded_ticks_and_reports_rejections() -> void:
	var world: SimWorld = _world_with_commands()
	var record: CommandLog = CommandLog.from_world(world, SETUP)
	var fresh: SimWorld = (
		M1Encounter.new(7, "test", TestDefs.corvette(), TestDefs.raider_enemy()).build()
	)
	assert_array(Array(record.replay(fresh, world.tick))).is_empty()
	assert_str(fresh.state_hash()).is_equal(world.state_hash())
	for i: int in fresh.command_log.size():
		assert_int(fresh.command_log[i].tick).is_equal(world.command_log[i].tick)
	record.entries[2]["mount_index"] = 99
	var other: SimWorld = (
		M1Encounter.new(7, "test", TestDefs.corvette(), TestDefs.raider_enemy()).build()
	)
	var problems: PackedStringArray = record.replay(other, world.tick)
	assert_int(problems.size()).is_equal(1)


# FT: FT-ARC-008
# Every registered command class round-trips through to_dict()/from_dict() with each
# parameter set away from its default (per property type).
func test_every_command_round_trips() -> void:
	for kind: StringName in SimCommands.kinds():
		var c: SimCommand = SimCommands.make(kind)
		assert_str(String(c.kind())).is_equal(String(kind))
		for p: Dictionary in c.get_property_list():
			var name: String = p["name"]
			if not p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE or name == "source":
				continue
			var value: Variant = _non_default(c.get(name))
			assert_bool(value != null).override_failure_message("%s.%s" % [kind, name]).is_true()
			c.set(name, value)
		var back: SimCommand = SimCommands.from_dict(c.to_dict())
		assert_object(back.get_script()).override_failure_message(kind).is_same(c.get_script())
		var same: bool = var_to_bytes(back.to_dict()) == var_to_bytes(c.to_dict())
		assert_bool(same).override_failure_message(kind).is_true()


## A value of the same type unlike the default, or null for an unhandled type.
func _non_default(v: Variant) -> Variant:
	match typeof(v):
		TYPE_BOOL:
			return not v
		TYPE_INT:
			return v + 3
		TYPE_FLOAT:
			return 1.0 / 3.0 + v
		TYPE_STRING_NAME:
			return StringName(String(v) + "_x")
		TYPE_VECTOR3:
			return v + Vector3(0.5, -1.0 / 3.0, 0.25)
	return null


# FT: FT-ARC-008, FT-TST-009, FT-SIM-030
# A rejected crew command is logged, so the replay re-emits its rejection event
# (&"repair_no_parts": damaged engines, no spare parts).
func test_replay_reproduces_rejection_events() -> void:
	var live: SimWorld = _no_parts_world()
	var dispatch: DispatchRepairCommand = DispatchRepairCommand.new()
	dispatch.ship_id = M1Encounter.PLAYER_SHIP
	dispatch.crew = 0
	dispatch.subsystem_id = &"engines"
	live.submit(dispatch)
	live.step()
	live.step()
	var live_events: Array = SimFixture.of_kind(live.drain_events(), &"repair_no_parts")
	assert_int(live_events.size()).is_equal(1)
	var replayed: SimWorld = _no_parts_world()
	var record: CommandLog = CommandLog.from_text(CommandLog.from_world(live).to_text())
	assert_array(record.replay(replayed, live.tick)).is_empty()
	var events: Array = SimFixture.of_kind(replayed.drain_events(), &"repair_no_parts")
	assert_int(events.size()).is_equal(1)
	assert_int(events[0].tick).is_equal(live_events[0].tick)
	assert_str(replayed.state_hash()).is_equal(live.state_hash())


func _no_parts_world() -> SimWorld:
	var w: SimWorld = (
		M1Encounter.new(3, "test", TestDefs.corvette(), TestDefs.raider_enemy()).build()
	)
	DamageSystem.damage_subsystem(w, M1Encounter.PLAYER_SHIP, &"engines", 1.0e6, &"test")
	w.damage.spare_parts[w.damage.hull_row(M1Encounter.PLAYER_SHIP)] = 0
	w.drain_events()
	return w
