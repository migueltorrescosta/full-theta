class_name LiveRun
extends RefCounted
## The M1 encounter driven like a live client for the replay tests (T037): the
## ScriptedCrew acts once per tick it sees, between frames, and the frame loop feeds
## world.advance() irregular, seeded frame deltas, so commands reach the world at
## varying wall times. It keeps every event in emission order.

var world: SimWorld
var events: Array[SimEvent] = []
var _crew: ScriptedCrew = ScriptedCrew.new()
var _acted_tick: int = -1


func _init(start: SimWorld) -> void:
	world = start


## The M1 encounter on the shipped definitions, looked up by the ids a log records, at
## its site period (the default when the log has none, D125).
static func encounter(seed_value: int, setup: Dictionary, build: String) -> M1Encounter:
	var lib: DefLibrary = DefLibrary.new()
	var period: float = setup.get("site_period", Kinematics.DEFAULT_PERIOD)
	return M1Encounter.new(
		seed_value, build, lib.ship(setup["player"]), lib.enemy(setup["enemy"]), period
	)


## Frames with deltas drawn uniformly from [min_delta, max_delta] (s) until the world
## reaches end_tick; the crew acts before a frame when the world has moved to a new tick.
func run_frames(frame_seed: int, min_delta: float, max_delta: float, end_tick: int) -> void:
	var frames: RandomNumberGenerator = RandomNumberGenerator.new()
	frames.seed = frame_seed
	while world.tick < end_tick:
		_act()
		world.advance(frames.randf_range(min_delta, max_delta))
		events.append_array(world.drain_events())


## Fixed steps until the encounter has an outcome or the world reaches end_tick.
func run_steps(end_tick: int) -> void:
	while world.tick < end_tick and OutcomeSystem.encounter_outcome(world) == RunTable.Outcome.NONE:
		_act()
		world.step()
		events.append_array(world.drain_events())


## Each event's fields as one exact byte string (floats bit for bit).
static func event_bytes(list: Array[SimEvent]) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	for e: SimEvent in list:
		out.append(
			var_to_bytes(
				[e.tick, e.kind, e.ship_id, e.faction, e.other_id, e.value, e.vector, e.tag]
			)
		)
	return out


## Replays a log on a fresh world built from its setup; returns the world and its
## events, failing the problems into the given list.
static func replay(record: CommandLog, end_tick: int, problems: PackedStringArray) -> LiveRun:
	var enc: M1Encounter = encounter(record.seed_value, record.setup, record.build_id)
	var out: LiveRun = LiveRun.new(enc.build())
	problems.append_array(record.replay(out.world, end_tick))
	out.events = out.world.drain_events()
	return out


func _act() -> void:
	if world.tick != _acted_tick:
		_crew.act(world)
		_acted_tick = world.tick
