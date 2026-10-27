class_name ShakedownRig
extends RefCounted
## A Shakedown world for the tests (FT-MIS-039): the real run (content/runs/shakedown.tres),
## the real step list and scenario, one crewed ship, and a TrainingDriver stepped through a
## ScenarioHost. Stations "use" a step the way a player does: a COMMAND step by an accepted
## crew command of its kind, a NEXT step by TrainingNextCommand.

var defs: DefLibrary = DefLibrary.new()
var steps: TrainingStepsDef
var world: SimWorld
var host: ScenarioHost
var driver: TrainingDriver


## Accepts whatever kind it is made with (a command the training world could not trigger
## in a bare test world, like jump without a target).
class AnyCommand:
	extends SimCommand
	var name_of: StringName = &""

	func kind() -> StringName:
		return name_of

	func apply(_w: SimWorld) -> bool:
		return true


func _init(crew: int = 1) -> void:
	steps = load("res://content/training/steps.tres") as TrainingStepsDef
	var setup: RunSetup = RunSetup.new(7, "test", defs.run(&"shakedown"), defs.enemies(), crew)
	setup.science = defs.science()
	# The server's own hail map and the real conversations: the Comms hail step must be
	# doable against the training drone (review 2, H2).
	setup.conversations = ConversationLibrary.load_dir()
	setup.hail_conversations = ServerMain.HAIL_CONVERSATIONS
	world = setup.build()
	host = ScenarioHost.new(world)
	driver = TrainingDriver.new(ShakedownScenario.new(), steps)


## Steps n ticks with the driver.
func tick(n: int = 1) -> void:
	for i: int in n:
		host.advance(SimWorld.DT * 1.001, driver.before_tick)


## The say events so far for a line id.
func said(line: String) -> Array[SimEvent]:
	return world.events.filter(
		func(e: SimEvent) -> bool: return e.kind == &"say" and String(e.tag) == line
	)


## Sends Next for a station and lets the driver read it.
func press_next(station: StringName, ship: int = 0) -> void:
	var cmd: TrainingNextCommand = TrainingNextCommand.new()
	cmd.ship_id = ship
	cmd.station = station
	world.submit(cmd)
	tick(2)


## A crew command that produces the tag (kind or kind:detail).
func command_for(tag: StringName, ship: int = 0) -> SimCommand:
	var kind: String = String(tag).get_slice(":", 0)
	var cmd: SimCommand
	if kind == "comms_hail":
		var hail: HailCommand = HailCommand.new()
		hail.target = 1  # the training drone
		cmd = hail
	elif kind == "helm_input":
		var h: HelmInputCommand = HelmInputCommand.new()
		match String(tag).get_slice(":", 1):
			"face":
				h.face = true
			"approach":
				h.approach = true
			"throttle":
				h.throttle = 0.5
			"strafe":
				h.strafe = 0.5
			"lift":
				h.lift = 0.5
			"pitch":
				h.rotation = Vector3(0.5, 0.0, 0.0)
			"yaw":
				h.rotation = Vector3(0.0, 0.5, 0.0)
			"roll":
				h.rotation = Vector3(0.0, 0.0, 0.5)
		cmd = h
	else:
		var a: AnyCommand = AnyCommand.new()
		a.name_of = StringName(kind)
		cmd = a
	cmd.ship_id = ship
	return cmd


## Does the step as a player would; the driver sees it two ticks later. The hail is the
## real command, which the sim may refuse (then the step does not end, as for a player).
func use(step: TrainingStepDef) -> void:
	if step.kind == TrainingStepDef.Kind.COMMAND:
		world.submit(command_for(step.command))
		tick(2)
	else:
		press_next(step.station)


## Finishes a station's whole track.
func finish(station: StringName) -> void:
	var guard: int = 0
	while driver.current(station) != null and guard < 1000:
		use(driver.current(station))
		guard += 1
