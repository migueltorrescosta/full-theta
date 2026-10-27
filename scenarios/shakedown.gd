class_name ShakedownScenario
extends Scenario
## The Shakedown (FT-MIS-039, D100, D235): one co-op ship at Kestrel Yard and an unarmed
## drone to practise on. No hazards, no director and no elimination (the training run
## resets a ship at hull 0, RunDef.training). It makes no beats and ends never: the
## TrainingDriver steps the stations' tracks and says the lines; this scenario only keeps a
## drone near the ship, a new one when the drone is destroyed or the ship has jumped away.

## Faction of the drone (hostile to the crew by the default relation).
const DRONE_FACTION: int = 2
## Where the drone appears from the ship (m), at the bow, a little high.
const DRONE_RANGE_M: float = 1500.0
const DRONE_CLOCK: int = 12
const DRONE_HEIGHT: int = 1
## The enemy key of the drone (content/enemies/drone.tres).
const DRONE_KEY: StringName = &"drone"

var _ship: int = -1
var _drone: ApiHandle
## The site nearest the ship when the current drone appeared.
var _anchor: int = -1
## The tick a drone was last asked for, so one spawn is not repeated while it applies.
var _asked: int = -100


func meta() -> ScenarioMeta:
	var m: ScenarioMeta = ScenarioMeta.new()
	m.id = &"shakedown"
	m.tags = PackedStringArray(["training"])
	m.training = true
	m.threat_cost = 0
	m.duration_s = 3600.0
	m.stations = PackedStringArray(ScenarioMeta.STATIONS)
	var pairs: PackedStringArray = PackedStringArray()
	for n: int in range(1, 16):
		pairs.append("p%d" % n)
	m.pairs = pairs
	return m


func start(api: ScenarioApi, params: Dictionary) -> void:
	var ships: PackedInt32Array = params.get("ships", api.crew_ships())
	_ship = ships[0] if not ships.is_empty() else -1
	_ask(api)


func step(api: ScenarioApi) -> void:
	if _ship < 0 or api.tick() - _asked < ScenarioApi.HZ:
		return
	var ship: ShipView = api.ship(_ship)
	# The handle names the real ship: a rejected spawn is gone (review 2 L5).
	var gone: bool = _drone == null or _drone.rejected()
	if not gone and not _drone.pending():
		gone = api.ship(_drone.id()).status != 0
	if gone or (ship.nearest_site != _anchor and not ship.jumping):
		_ask(api)


## Spawns a drone ahead of the ship.
func _ask(api: ScenarioApi) -> void:
	if _ship < 0:
		return
	_drone = api.spawn_at_range(
		DRONE_KEY, DRONE_FACTION, _ship, DRONE_RANGE_M, DRONE_CLOCK, DRONE_HEIGHT
	)
	_anchor = api.ship(_ship).nearest_site
	_asked = api.tick()
