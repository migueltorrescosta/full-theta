class_name BotRun
extends RefCounted
## One headless run for the bot batch (FT-TST-022): the server's own RunSetup on
## content/runs/m3_run.tres (ServerMain.run_setup), the Director, a BotCrew and a ScenarioHost,
## stepped without a network until the ship wins, is lost or the sim-time cap passes. The
## result is the run's debrief record (RunDebrief) plus how it ended, the crew's site picks
## (crew_picks) and, per encounter, whether the crew picked it and what was offered.

## Sim seconds a run may last before it counts as stalled.
const DEFAULT_CAP_TIME: float = 7200.0


## Plays one run of one crewed ship. `outcome` is "win", "survived", "loss", "abandoned" or
## "stalled".
static func play(
	defs: DefLibrary,
	profile_name: String,
	difficulty: String,
	seed_value: int,
	cap_time: float = DEFAULT_CAP_TIME,
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
		seed_value,
		world.faction_of(0)
	)
	var profile: BotProfiles.Profile = BotProfiles.named(profile_name)
	if jump_share >= 0.0:
		profile.jump_share = jump_share  # a test's choice of how the trips are flown
	var crew: BotCrew = BotCrew.new(profile, 0, seed_value ^ 0x5BD1E995)
	var faction: int = world.faction_of(0)
	crew.offers = func() -> Array[Dictionary]: return director.site_offers(faction)
	var host: ScenarioHost = ScenarioHost.new(world)
	var drive: Callable = func(api: ScenarioApi) -> void:
		director.before_tick(api)
		crew.act(world)
	var cap_ticks: int = ceili(cap_time * SimWorld.HZ)
	var jumps: int = 0
	var top_speed: float = 0.0
	var settle: int = 3
	while world.tick < cap_ticks and settle > 0:
		host.advance(SimWorld.DT * 1.001, drive)
		for e: SimEvent in world.drain_events():
			jumps += 1 if e.kind == &"jump_arrive" else 0
		top_speed = maxf(top_speed, world.kin.vel[0].length())
		if world.ships.ship_outcome[0] != ShipStateTable.ShipOutcome.NONE:
			settle -= 1  # the encounter a ship is lost in closes a tick or two later
	var record: Dictionary = (
		RunDebrief.new(world, director.decisions(), CoopEvents.new(), FirstUse.new()).for_ship(0)
	)
	record["outcome"] = (
		"stalled"
		if world.ships.ship_outcome[0] == ShipStateTable.ShipOutcome.NONE
		else record["result"]
	)
	_note_picks(world, record["encounters"], crew.picks)
	record["crew_picks"] = crew.picks.size()
	record["profile"] = profile_name
	record["difficulty"] = difficulty
	record["seed"] = seed_value
	record["ticks"] = world.tick
	record["jumps"] = jumps
	record["top_speed"] = top_speed
	return record


## Marks each encounter row with the crew's pick made in the gap before it opened: "picked"
## and "offered" (the offers' scenarios; empty with no pick).
static func _note_picks(world: SimWorld, rows: Array, picks: Array[Dictionary]) -> void:
	var since: int = -1
	for row: Dictionary in rows:
		var opened: int = world.encounters.open_tick[row["id"]]
		var offered: Array = []
		for p: Dictionary in picks:
			if p["tick"] >= since and p["tick"] < opened:
				offered = p["offered"]  # the last pick of the gap holds
		row["picked"] = not offered.is_empty()
		row["offered"] = offered
		since = opened
