class_name StationFixture
extends RefCounted
## A deterministic station context with no server (#7): ship 0 "Kestrel" picked at the
## given entry, Started; a snapshot view with the own ship at rest at a fixed spot with
## a fixed orientation, a hostile H2 at 4 high, 2.3 km, an unknown U3 at 11 high, 8 km
## and an own-faction F4 at 7 level, 600 m; a free mark Bravo at 8 low, 1.2 km; alert
## Normal; a fixed clock. Sends go to a RecordingClient. Station scene tests and L5
## shots build on it: `var ctx := StationFixture.context("helm")`.

const SHIP: int = 0
const SHIP_NAME: String = "Kestrel"
const SESSION: int = 7
const H2: int = 2
const U3: int = 3
const F4: int = 4
const BRAVO_SLOT: int = 1
const NOW_MS: int = 100_000
const TICK: int = 3600
const START_TICK: int = 600
const PERIOD_M: float = 200_000.0
## The own ship's site-local position (m) and orientation (yawed 30° to port, so ship
## frame and world axes differ, D124).
const OWN_POS: Vector3 = Vector3(1200.0, -300.0, 4500.0)
const OWN_YAW_DEG: float = 30.0


## Records every intent sent: [[method, args], ...].
class RecordingClient:
	extends RefCounted
	var name: String = "Ana"
	var sent: Array = []

	func command(cmd: Dictionary) -> int:
		sent.append(["command", [cmd]])
		return sent.size()

	func set_alert(level: int) -> void:
		sent.append(["set_alert", [level]])

	func place_mark(slot: int, n: String, contact: int, site: int, pos: Vector3) -> void:
		sent.append(["place_mark", [slot, n, contact, site, pos]])

	func move_mark(slot: int, contact: int, site: int, pos: Vector3) -> void:
		sent.append(["move_mark", [slot, contact, site, pos]])

	func rename_mark(slot: int, n: String) -> void:
		sent.append(["rename_mark", [slot, n]])

	func delete_mark(slot: int) -> void:
		sent.append(["delete_mark", [slot]])

	func ping(kind: String, id: int, site: int, pos: Vector3) -> void:
		sent.append(["ping", [kind, id, site, pos]])

	func claim(item: String) -> void:
		sent.append(["claim", [item]])

	func release_claim(item: String) -> void:
		sent.append(["release_claim", [item]])

	func pick(ship: int, entry: String) -> void:
		sent.append(["pick", [ship, entry]])

	func release_pick() -> void:
		sent.append(["release_pick", []])

	func set_ready(ready: bool) -> void:
		sent.append(["set_ready", [ready]])

	func vote_abandon(ship: int, vote: bool) -> void:
		sent.append(["vote_abandon", [ship, vote]])

	func abandon(ship: int) -> void:
		sent.append(["abandon", [ship]])

	func takeover(ship: int, entry: String) -> void:
		sent.append(["takeover", [ship, entry]])

	func run_again(ship: int, vote: bool) -> void:
		sent.append(["run_again", [ship, vote]])

	## The sends of one method, newest last.
	func of(method: String) -> Array:
		return sent.filter(func(s: Array) -> bool: return s[0] == method)


## A pinned clock tests may move: ctx.clock = clock.now.
class Clock:
	extends RefCounted
	var ms: int = NOW_MS

	func now() -> int:
		return ms


## The context for `entry` (a catalogue id). settings_path: a test-local file.
static func context(
	entry: String = "helm", settings_path: String = "user://test_station_fixture.cfg"
) -> StationContext:
	var ctx: StationContext = StationContext.new()
	var rec: RecordingClient = RecordingClient.new()
	ctx.intents = ShipIntents.new(rec)
	var clock: Clock = Clock.new()
	# The context keeps the clock alive (a Callable doesn't hold its object).
	ctx.set_meta(&"clock", clock)
	ctx.clock = clock.now
	ctx.settings = ClientSettings.new(settings_path)
	ctx.settings.player_name = rec.name
	ctx.matcher = InputMatcher.new(ctx.settings.bindings)
	var crew: CrewState = ctx.crew
	crew.welcome(
		{
			"session": SESSION,
			"ship": SHIP,
			"entry": entry,
			"host": false,
			"dev_all": entry == StationViews.ALL,
			"lang": "en"
		}
	)
	crew.set_catalogue(catalogue(true))
	crew.started[SHIP] = START_TICK
	crew.lobby[SHIP] = {
		"ship": SHIP,
		"crew": 3,
		"min_crew": 3,
		"uncovered": [],
		"ready": true,
		"started": true,
		"in_play": true,
		"captain": ""
	}
	crew.handle_event(
		{
			"type": "marks",
			"payload":
			{
				"ship": SHIP,
				"marks":
				[
					{
						"slot": BRAVO_SLOT,
						"name": "Bravo",
						"contact": -1,
						"site": 0,
						"x": _world(_at(8, -25.0, 1200.0)).x,
						"y": _world(_at(8, -25.0, 1200.0)).y,
						"z": _world(_at(8, -25.0, 1200.0)).z,
						"by": "Ana"
					}
				]
			}
		},
		NOW_MS
	)
	ctx.view = view()
	ctx.interp.push(ctx.view, NOW_MS - 100)
	ctx.interp.push(ctx.view, NOW_MS)
	ctx.interp.update(NOW_MS)
	return ctx


## The fixture's clock (move `ms` to advance time).
static func clock(ctx: StationContext) -> Clock:
	return ctx.get_meta(&"clock")


## The recording client behind a fixture context.
static func sent(ctx: StationContext) -> RecordingClient:
	return ctx.intents.client as RecordingClient


## The Catalogue message as the server sends it (StationViews), with ship 0.
static func catalogue(dev_all: bool = false) -> Dictionary:
	var entries: Array = []
	var ids: Array = StationViews.CREW + StationViews.ENTRIES.keys()
	if dev_all:
		ids.append(StationViews.ALL)
	for id: String in ids:
		entries.append(StationViews.def(id).to_dict())
	return {
		"ships": [{"id": SHIP, "def": "m1_corvette", "name": SHIP_NAME, "faction": 0}],
		"entries": entries,
		"load_tags": StationViews.LOAD_TAGS,
	}


## The snapshot view: own ship, STATUS and MOUNTS blocks, contacts H2, U3, F4.
static func view() -> NetViewState:
	var p_units: int = NetCodec.period_units(PERIOD_M)
	var v: NetViewState = NetViewState.new(p_units)
	v.seq = 10
	v.tick = TICK
	v.kin = {
		"site": 0,
		"pos": _units(OWN_POS, p_units),
		"vel": Vector3i.ZERO,
		"rot": own_rotation(),
		"ang": Vector3i.ZERO,
	}
	v.blocks[StationViews.Section.STATUS] = {
		"alive": true,
		"status": 0,
		"outcome": 0,
		"hull": 920.0,
		"shields": 700.0,
		"pips_used": 6,
		"propellant": 0.8,
	}
	# The corvette's bow mount at rest, loaded and cool.
	v.blocks[StationViews.Section.MOUNTS] = {
		"mounts":
		[{"barrel": Vector3.FORWARD, "cooldown": 0.0, "ammo": 380, "heat": 6.0, "aim_set": false}]
	}
	var model: Dictionary = {}
	var info: Dictionary = {}
	for c: Array in [[H2, "H2", _at(4, 30.0, 2300.0)], [U3, "U3", _at(11, 20.0, 8000.0)]]:
		model[c[0]] = [_units(_world(c[2]), p_units), Vector3i.ZERO, TICK]
		info[c[0]] = [0, c[1]]
	model[F4] = [_units(_world(_at(7, 0.0, 600.0)), p_units), Vector3i.ZERO, TICK]
	info[F4] = [2, "F4"]
	v.contacts = {"model": model, "info": info}
	return v


static func own_rotation() -> Quaternion:
	return Quaternion(Vector3.UP, deg_to_rad(OWN_YAW_DEG))


## Ship-frame offset at a clock hour, elevation (degrees) and range (m).
static func _at(clock_hour: int, elevation_deg: float, range_m: float) -> Vector3:
	var b: float = deg_to_rad(clock_hour * 30.0)
	var e: float = deg_to_rad(elevation_deg)
	var h: float = range_m * cos(e)
	return Vector3(sin(b) * h, range_m * sin(e), -cos(b) * h)


## A ship-frame offset as a site-local position.
static func _world(local: Vector3) -> Vector3:
	return OWN_POS + own_rotation() * local


static func _units(p: Vector3, p_units: int) -> Vector3i:
	return NetCodec.quant_pos(p.x, p.y, p.z, p_units)
