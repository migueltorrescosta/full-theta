extends GdUnitTestSuite
## T037: the golden replay of the M1 encounter (FT-TST-009, FT-ARC-008). The command
## log in tests/golden/m1_encounter.cmdlog is replayed on a world rebuilt from its seed,
## build id and setup (definitions looked up by id), and the result is compared with
## tests/golden/m1_encounter.expected.cfg. Run with FT_UPDATE_GOLDEN=1 to record both
## files again instead (tests/README.md); a normal run never writes.

const LOG_PATH: String = "res://tests/golden/m1_encounter.cmdlog"
const EXPECTED_PATH: String = "res://tests/golden/m1_encounter.expected.cfg"
const SEED: int = 9
const SETUP: Dictionary = {"player": &"m1_corvette", "enemy": &"m1_raider"}
## The recording stops at the encounter's outcome or after 120 s.
const MAX_TICKS: int = 120 * SimWorld.HZ
## Diagnostic tolerances for the readable values when the state hash differs, or the
## only check when the golden was recorded on another platform (FT-TST-009): 1 m of
## position (float differences between platforms grow over a fight of thousands of
## ticks, but stay far below a ship length) and 1 % of hull.
const POSITION_TOLERANCE: float = 1.0
const HULL_TOLERANCE: float = 0.01


## The readable final values: per ship position (m), hull fraction and alive, and the
## encounter outcome.
static func readable(world: SimWorld) -> Dictionary:
	var out: Dictionary = {"outcome": OutcomeSystem.encounter_outcome(world)}
	for id: int in world.ship_count():
		out["ship%d_position" % id] = [world.kin.px[id], world.kin.py[id], world.kin.pz[id]]
		out["ship%d_hull" % id] = DamageSystem.hull_fraction(world, id)
		out["ship%d_alive" % id] = world.kin.is_alive(id)
	return out


## Engine version, OS, CPU architecture and, on Linux, the C library version: the hash
## must match exactly only here. libm results for transcendental functions differ
## between glibc versions, so another glibc counts as another platform.
static func platform() -> String:
	var out: String = (
		"%s %s %s"
		% [Engine.get_version_info()["string"], OS.get_name(), Engine.get_architecture_name()]
	)
	if OS.get_name() == "Linux":
		var lines: Array = []
		var libc: String = ""
		if OS.execute("getconf", ["GNU_LIBC_VERSION"], lines) == 0 and not lines.is_empty():
			libc = String(lines[0]).strip_edges()
		out += " " + (libc if not libc.is_empty() else "unknown-libc")
	return out


# FT: FT-TST-009, FT-ARC-008
# The golden log replays with every command accepted on its recorded tick and reaches
# the recorded tick and state hash (same build and platform), or the readable values
# within tolerance (another platform).
func test_golden_replay_matches() -> void:
	if OS.get_environment("FT_UPDATE_GOLDEN") == "1":
		_record()
		return
	var record: CommandLog = CommandLog.from_text(FileAccess.get_file_as_string(LOG_PATH))
	var expected: ConfigFile = ConfigFile.new()
	assert_int(expected.load(EXPECTED_PATH)).is_equal(OK)
	assert_object(record).override_failure_message("cannot parse " + LOG_PATH).is_not_null()
	if is_failure():
		return
	var end_tick: int = expected.get_value("final", "tick")
	var problems: PackedStringArray = PackedStringArray()
	var world: SimWorld = LiveRun.replay(record, end_tick, problems).world
	assert_array(Array(problems)).is_empty()
	assert_int(world.tick).is_equal(end_tick)
	var diffs: PackedStringArray = _readable_diffs(expected, readable(world))
	var same_platform: bool = expected.get_value("final", "platform") == platform()
	if same_platform:
		(
			assert_str(world.state_hash())
			. override_failure_message(
				(
					(
						"state hash differs from the golden (regenerate with FT_UPDATE_GOLDEN=1 only "
						+ "for an intended sim change); readable values: %s"
					)
					% ("within tolerance" if diffs.is_empty() else ", ".join(diffs))
				)
			)
			. is_equal(expected.get_value("final", "state_hash"))
		)
	else:
		assert_array(Array(diffs)).is_empty()


func _readable_diffs(expected: ConfigFile, got: Dictionary) -> PackedStringArray:
	var diffs: PackedStringArray = PackedStringArray()
	for key: String in got:
		var want: Variant = expected.get_value("readable", key)
		var have: Variant = got[key]
		var ok: bool = want == have
		if key.ends_with("_position") and want is Array and want.size() == 3:
			ok = (
				Vector3(want[0], want[1], want[2]).distance_to(Vector3(have[0], have[1], have[2]))
				<= POSITION_TOLERANCE
			)
		elif key.ends_with("_hull") and want is float:
			ok = absf(want - have) <= HULL_TOLERANCE
		if not ok:
			diffs.append("%s %s (golden %s)" % [key, have, want])
	return diffs


func _record() -> void:
	var build: String = "godot " + Engine.get_version_info()["string"]
	var live: LiveRun = LiveRun.new(LiveRun.encounter(SEED, SETUP, build).build())
	live.run_steps(MAX_TICKS)
	var world: SimWorld = live.world
	var record: CommandLog = CommandLog.from_world(world, SETUP)
	var file: FileAccess = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	file.store_string(record.to_text())
	file.close()
	var expected: ConfigFile = ConfigFile.new()
	expected.set_value("final", "tick", world.tick)
	expected.set_value("final", "state_hash", world.state_hash())
	expected.set_value("final", "platform", platform())
	expected.set_value("final", "commands", record.entries.size())
	var values: Dictionary = readable(world)
	for key: String in values:
		expected.set_value("readable", key, values[key])
	assert_int(expected.save(EXPECTED_PATH)).is_equal(OK)
	print("golden replay recorded: tick %d, %d commands" % [world.tick, record.entries.size()])
