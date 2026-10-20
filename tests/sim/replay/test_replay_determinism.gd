extends GdUnitTestSuite
## T037: determinism under wall time (FT-ARC-008, FT-TST-009, FT-SIM-030). A live M1
## encounter is driven by world.advance() with irregular, seeded frame deltas while the
## scripted crew submits commands between frames; its command log, replayed on a fresh
## world with plain step() calls, reaches the same state and events on the same tick.

const HZ: int = SimWorld.HZ
const DT: float = SimWorld.DT
const SEED: int = 9
const BUILD: String = "test"
const SETUP: Dictionary = {"player": &"m1_corvette", "enemy": &"m1_raider"}
## 40 s of the fight: the crew fires from tick 60 every 30 ticks and hits land.
const END_TICK: int = 40 * HZ


func _live(frame_seed: int, min_delta: float, max_delta: float) -> LiveRun:
	var run: LiveRun = LiveRun.new(LiveRun.encounter(SEED, SETUP, BUILD).build())
	run.run_frames(frame_seed, min_delta, max_delta, END_TICK)
	return run


func _assert_events_equal(a: Array[SimEvent], b: Array[SimEvent]) -> void:
	assert_int(b.size()).is_equal(a.size())
	var ab: Array[PackedByteArray] = LiveRun.event_bytes(a)
	var bb: Array[PackedByteArray] = LiveRun.event_bytes(b)
	for i: int in mini(ab.size(), bb.size()):
		if ab[i] != bb[i]:
			fail("event %d differs: %s vs %s" % [i, a[i], b[i]])
			return


# FT: FT-ARC-008, FT-TST-009, FT-SIM-030
# Frames of 0.1 to 3.5 ticks (several steps in one advance, or none): the log,
# written to text and read back, replays with step() to the same tick, state hash and
# event stream, every command accepted on its recorded tick.
func test_live_run_replays_to_same_state() -> void:
	var live: LiveRun = _live(1, 0.1 * DT, 3.5 * DT)
	var record: CommandLog = CommandLog.from_world(live.world, SETUP)
	assert_int(record.entries.size()).is_greater(20)
	var problems: PackedStringArray = PackedStringArray()
	var copy: CommandLog = CommandLog.from_text(record.to_text())
	var replayed: LiveRun = LiveRun.replay(copy, live.world.tick, problems)
	assert_array(Array(problems)).is_empty()
	assert_int(replayed.world.tick).is_equal(live.world.tick)
	assert_str(replayed.world.state_hash()).is_equal(live.world.state_hash())
	assert_int(replayed.world.command_log.size()).is_equal(record.entries.size())
	assert_bool(live.events.any(func(e: SimEvent) -> bool: return e.kind == &"hit")).is_true()
	_assert_events_equal(live.events, replayed.events)


# FT: FT-ARC-008, FT-TST-009, FT-SIM-030
# Two live runs with different frame jitter (frames shorter than a tick, so the crew
# sees every tick and acts on the same ticks, at different wall times) give the same
# log, state and events: commands are stamped with the tick they apply on, not the
# frame they arrived in.
func test_jitter_does_not_change_log_or_state() -> void:
	var a: LiveRun = _live(2, 0.2 * DT, 0.99 * DT)
	var b: LiveRun = _live(3, 0.05 * DT, 0.7 * DT)
	assert_int(a.world.tick).is_equal(END_TICK)
	assert_int(b.world.tick).is_equal(END_TICK)
	var text_a: String = CommandLog.from_world(a.world, SETUP).to_text()
	assert_str(CommandLog.from_world(b.world, SETUP).to_text()).is_equal(text_a)
	assert_str(b.world.state_hash()).is_equal(a.world.state_hash())
	_assert_events_equal(a.events, b.events)
