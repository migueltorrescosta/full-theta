class_name BotRun
extends RefCounted
## One headless run for the bot batch (FT-TST-022): the server's own RunSetup on
## content/runs/m3_run.tres (ServerMain.run_setup), the Director, a BotCrew and a ScenarioHost,
## stepped without a network until the ship wins, is lost or the sim-time cap passes. The
## result is the run's debrief record (RunDebrief) plus how it ended.

## Sim seconds a run may last before it counts as stalled.
const DEFAULT_CAP_S: float = 7200.0


## Plays one run of one crewed ship. `outcome` is "win", "loss" or "stalled".
static func play(
	defs: DefLibrary,
	profile_name: String,
	difficulty: String,
	seed_value: int,
	cap_s: float = DEFAULT_CAP_S,
	jump_share: float = -1.0
) -> Dictionary:
	var main: ServerMain = ServerMain.new()
	main.seed_value = seed_value
	var setup: RunSetup = main.run_setup(defs)
	var world: SimWorld = setup.build()
	var director: Director = Director.new(
		setup.run_def.director,
		StringName(difficulty),
		ScenarioCatalogue.load_for(setup.run_def.scenarios),
		seed_value
	)
	var profile: BotProfiles.Profile = BotProfiles.named(profile_name)
	if jump_share >= 0.0:
		profile.jump_share = jump_share  # a test's choice of how the trips are flown
	var crew: BotCrew = BotCrew.new(profile, 0, seed_value ^ 0x5BD1E995)
	var host: ScenarioHost = ScenarioHost.new(world)
	var drive: Callable = func(api: ScenarioApi) -> void:
		director.before_tick(api)
		crew.act(world)
	var cap_ticks: int = ceili(cap_s * SimWorld.HZ)
	var jumps: int = 0
	var top_speed: float = 0.0
	var settle: int = 3
	while world.tick < cap_ticks and settle > 0:
		host.advance(SimWorld.DT * 1.001, drive)
		for e: SimEvent in world.drain_events():
			jumps += 1 if e.kind == &"jump_arrive" else 0
		top_speed = maxf(top_speed, world.kin.vel[0].length())
		if world.run.outcome[0] != RunTable.Outcome.NONE:
			settle -= 1  # the encounter a ship is lost in closes a tick or two later
	var record: Dictionary = (
		RunDebrief.new(world, director.decisions(), CoopEvents.new(), FirstUse.new()).for_ship(0)
	)
	record["outcome"] = (
		"stalled" if world.run.outcome[0] == RunTable.Outcome.NONE else record["result"]
	)
	record["profile"] = profile_name
	record["difficulty"] = difficulty
	record["seed"] = seed_value
	record["ticks"] = world.tick
	record["jumps"] = jumps
	record["top_speed"] = top_speed
	return record
