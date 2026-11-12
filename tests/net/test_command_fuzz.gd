extends GdUnitTestSuite
## A fuzz of every station command field through the command gate and the sim (#45 B2,
## R11-5): extreme and wrongly typed values for each field of each kind in
## StationViews.STATION_COMMANDS are either refused with a known reason or applied without
## breaking the world.

const PLAYER: int = NetHarness.PLAYER
const REASONS: Array[String] = [
	CommandGate.BAD_FIELD,
	CommandGate.BAD_VALUE,
	CommandGate.CLAIMED,
	CommandGate.NOT_YOUR_STATION,
]


func _world() -> SimWorld:
	return M1Encounter.new(5, "test", TestDefs.corvette(), TestDefs.raider_enemy()).build()


## The values to try in a field, by the template's Variant type.
func _extremes(want: int) -> Array:
	var table: Dictionary = {
		TYPE_INT:
		[
			0,
			-1,
			1,
			255,
			65536,
			2147483647,
			-2147483648,
			9223372036854775807,
			-9223372036854775807 - 1
		],
		TYPE_FLOAT: [0.0, -1.0, 1e30, -1e30, 1e-30, INF, -INF, NAN],
		TYPE_BOOL: [true, false],
		TYPE_STRING: ["", "x".repeat(100000), "a\u0000b", "../../x"],
		TYPE_STRING_NAME: ["", "x".repeat(100000), "a\u0000b", "../../x"],
		TYPE_VECTOR3:
		[Vector3.ZERO, Vector3(1e30, -1e30, 0.0), Vector3(INF, 0.0, 0.0), Vector3(0.0, NAN, 0.0)],
		TYPE_QUATERNION:
		[Quaternion.IDENTITY, Quaternion(0.0, 0.0, 0.0, 0.0), Quaternion(NAN, 0.0, 0.0, 1.0)],
	}
	return table.get(want, [])


func _session(entry: String) -> NetSession:
	var s: NetSession = NetSession.new(1, 1.0e9, 1.0e9)
	s.ship = PLAYER
	s.entry = entry
	return s


func _alive_and_finite(world: SimWorld) -> bool:
	for id: int in world.ship_count():
		var k: Kinematics = world.kin
		if not (is_finite(k.pos_x[id]) and is_finite(k.pos_y[id]) and is_finite(k.pos_z[id])):
			return false
		if not (k.vel[id].is_finite() and k.ang_vel[id].is_finite()):
			return false
	return true


# FT: FT-NET-006
# Every field of every station command takes each extreme of its type, and a value of the
# wrong type, through the gate; what passes is submitted, and one sim step afterwards leaves
# finite positions and velocities. A refusal is one of the gate's reasons.
func test_every_station_command_field_survives_extreme_values() -> void:
	var world: SimWorld = _world()
	var tried: int = 0
	var accepted: int = 0
	var problems: Array[String] = []
	for station: String in StationViews.STATION_COMMANDS:
		var entry: String = station
		var session: NetSession = _session(entry)
		for kind: StringName in StationViews.STATION_COMMANDS[station]:
			var template: Dictionary = SimCommands.make(kind).to_dict()
			# Next names the seat that presses it.
			var base: Dictionary = {"kind": kind}
			if kind == &"training_next":
				base["station"] = station
			var batch: Array[Dictionary] = [base]
			for key: String in template:
				if CommandGate.SERVER_FIELDS.has(key):
					continue
				for value: Variant in _extremes(typeof(template[key])):
					batch.append(base.merged({key: value}, true))
				var text: bool = template[key] is String or template[key] is StringName
				var wrong: Variant = 7 if text else "x"
				var out: Array = CommandGate.check(session, base.merged({key: wrong}, true), 0)
				# (Next's seat is checked before its fields.)
				if out[1] != CommandGate.BAD_FIELD and key != "station":
					problems.append("%s.%s wrong type: %s" % [kind, key, out[1]])
			for cmd: Dictionary in batch:
				var result: Array = CommandGate.check(session, cmd, 0)
				tried += 1
				if result[0] == null:
					if not REASONS.has(result[1]):
						problems.append("%s: %s" % [cmd, result[1]])
					continue
				accepted += 1
				world.submit(result[0])
			world.step()
			world.drain_events()
			(
				assert_bool(_alive_and_finite(world))
				. override_failure_message("world broken after %s" % kind)
				. is_true()
			)
	assert_array(problems).is_empty()
	assert_int(tried).is_greater(500)
	assert_int(accepted).is_greater(100)
