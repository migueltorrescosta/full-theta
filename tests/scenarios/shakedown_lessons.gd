class_name ShakedownLessons
extends RefCounted
## Solo Shakedown lessons for the tests (D303, FT-MIS-039): a player at one station plays the
## whole track, the scripted partners and acting bots do the rest. `lesson` plays each
## station's lesson once per test process (seed SEED, commands recorded) and hands the same
## finished world to every test that reads it, so treat the result as read-only. A test that
## needs a lesson stopped part way builds its own with `rig`, `tick` and `play`.

const STATIONS: Array[StringName] = [
	&"helm", &"weapons", &"engineering", &"science", &"relay", &"comms", &"captain"
]
const SEED: int = 11

## station -> {rig, partners, took}: took is the ticks the lesson needed (-1: it never ended).
static var _lessons: Dictionary[StringName, Dictionary] = {}


static func rig(solo: StringName) -> ShakedownRig:
	var out: ShakedownRig = ShakedownRig.new()
	out.driver = TrainingDriver.new(ShakedownScenario.new(), out.steps, solo)
	return out


## Steps n ticks with the partners ahead of the driver, as the server does.
static func tick(r: ShakedownRig, partners: TrainingPartners, n: int = 1) -> void:
	for i: int in n:
		r.host.advance(
			SimWorld.DT * 1.001,
			func(api: ScenarioApi) -> void:
				partners.act(r.world, r.driver)
				r.driver.before_tick(api)
		)


static func press(r: ShakedownRig, partners: TrainingPartners, station: StringName) -> void:
	var cmd: TrainingNextCommand = TrainingNextCommand.new()
	cmd.ship_id = 0
	cmd.station = station
	r.world.submit(cmd)
	tick(r, partners, 2)


## Plays the lesson as a player does: each step of the track, then Next in every pair step,
## until `stop` is true (default: the driver says all_done). Returns the ticks it took (-1:
## the guard ran out first).
static func play(
	r: ShakedownRig, partners: TrainingPartners, solo: StringName, stop: Callable = Callable()
) -> int:
	var start: int = r.world.tick
	tick(r, partners, 2)
	for guard: int in 4000:
		var done: bool = (
			stop.call() if stop.is_valid() else not r.said("shakedown.all_done").is_empty()
		)
		if done:
			return r.world.tick - start
		var step: TrainingStepDef = r.driver.current(solo)
		if step != null:
			if step.kind == TrainingStepDef.Kind.COMMAND:
				r.world.submit(r.command_for(step.command))
				tick(r, partners, 2)
			else:
				press(r, partners, solo)
		elif not r.driver.active_pairs().is_empty():
			press(r, partners, solo)
		else:
			tick(r, partners, 30)
	return -1


## The finished lesson of `solo` (played on first use): {rig, partners, took}.
static func lesson(solo: StringName) -> Dictionary:
	if not _lessons.has(solo):
		var r: ShakedownRig = rig(solo)
		var partners: TrainingPartners = TrainingPartners.new(SEED)
		partners.crew.record = true
		var took: int = play(r, partners, solo)
		_lessons[solo] = {"rig": r, "partners": partners, "took": took}
	return _lessons[solo]
