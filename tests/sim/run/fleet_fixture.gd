class_name FleetFixture
extends RefCounted
## Multi-ship worlds for the M4 sim tests (#11): the server's own RunSetup on m3_run with
## one crewed ship per ShipSlot under a SessionRules mode, the Scenario API on it, and an
## optional FleetDirector driven the way the server drives it. Shared by strands A, C and D;
## owned by the M4 contract (strand K): strands only add helpers at the end of the file.

static var _defs: DefLibrary = DefLibrary.new()

var setup: RunSetup
var world: SimWorld
var api: ScenarioApi
var rules: SessionRules
## Set by with_director(); step() then calls its before_tick() first.
var director: FleetDirector


## Slots for `n` ships under `r`: named "Ship 1" ..., on teams[i] (default: 0 in COOP, i % 2
## with teams, i in RACE and LAST_STANDING), with the faction r.faction_for gives.
static func slots_for(r: SessionRules, n: int, teams: Array[int] = []) -> Array[ShipSlot]:
	var out: Array[ShipSlot] = []
	for i: int in n:
		var team: int = 0
		if i < teams.size():
			team = teams[i]
		elif r.has_teams():
			team = i % 2
		elif r.mode != SessionRules.Mode.COOP:
			team = i
		out.append(ShipSlot.of("Ship %d" % (i + 1), r.faction_for(i, team), team))
	return out


## A world at tick 0 with `n` crewed ships at the yard, ship ids 0 .. n - 1 in slot order.
static func make(
	mode: SessionRules.Mode, n: int, teams: Array[int] = [], seed_value: int = 1
) -> FleetFixture:
	var f: FleetFixture = FleetFixture.new()
	var main: ServerMain = ServerMain.new()
	main.seed_value = seed_value
	f.rules = SessionRules.of_mode(mode)
	f.setup = main.run_setup(_defs)
	f.setup.rules = f.rules
	f.setup.slots = slots_for(f.rules, n, teams)
	f.world = f.setup.build()
	f.api = ScenarioApi.new(f.world) if f.world != null else null
	return f


## Drives the world with a FleetDirector for the preset, as the server's driver does.
func with_director(preset: StringName = &"normal") -> FleetFixture:
	var run_def: RunDef = setup.run_def
	director = FleetDirector.new(
		run_def.director, preset, ScenarioCatalogue.load_for(run_def.scenarios), 1, rules.mode
	)
	return self


## The crewed ships, ascending.
func ships() -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for id: int in world.ship_count():
		if not world.ai.is_enabled(id):
			out.append(id)
	return out


## Steps `ticks` ticks (the director first, when set) and returns their events.
func step(ticks: int = 1) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for i: int in ticks:
		if director != null:
			director.before_tick(api)
		world.step()
		out.append_array(world.drain_events())
	return out


## Destroys a ship as damage would (OutcomeSystem marks it next tick).
func kill(id: int) -> void:
	world.kin.alive[id] = 0


func outcome() -> SessionOutcome:
	return OutcomeSystem.session_outcome(world)
