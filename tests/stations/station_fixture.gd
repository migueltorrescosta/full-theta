class_name StationFixture
extends RefCounted
## A deterministic station context with no server (#7): ship 0 "Kestrel" picked at the
## given entry, Started; a snapshot view with the own ship at a fixed spot with a fixed
## orientation, yawed, pitched and rolled so the ship frame and world axes differ on
## every axis (D124; its KIN velocity says 80 m/s along the bow; the position doesn't
## move), a hostile H2 at 4 high, 2.3 km, an unknown U3 at 11 high, 8 km and an
## own-faction F4 at 7 level, 600 m; a free mark Bravo at 8 low, 1.2 km; alert Normal; a
## fixed clock; a HELM block (assist on, H2 targeted and shield-tracked). Sends go to a
## RecordingClient. Station scene tests and L5 shots build on it:
## `var ctx := StationFixture.context("helm")`.
##
## The seam variant (`context(entry, path, true)`) adds items about half a period away,
## across the site's seam from each other (minimum image, D124): hostiles H5 and H6 and
## a free mark Echo, with H5 0.7 km from Echo through the seam and H6 2.7 km from it the
## other way.

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
## The own ship's site-local position (m) and orientation: yawed 30° to port, pitched
## 10° nose up and rolled 25° to port (Basis.from_euler order: yaw, pitch, roll).
const OWN_POS: Vector3 = Vector3(1200.0, -300.0, 4500.0)
const OWN_EULER_DEG: Vector3 = Vector3(10.0, 30.0, 25.0)
## The seam variant's items: world-axes offsets from the own ship (m).
const H5: int = 5
const H6: int = 6
const ECHO_SLOT: int = 4
const SEAM_H5: Vector3 = Vector3(PERIOD_M / 2.0 - 400.0, 0.0, 0.0)
const SEAM_H6: Vector3 = Vector3(-PERIOD_M / 2.0 + 3000.0, 0.0, 0.0)
const SEAM_ECHO: Vector3 = Vector3(-PERIOD_M / 2.0 + 300.0, 0.0, 0.0)


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
	entry: String = "helm",
	settings_path: String = "user://test_station_fixture.cfg",
	seam: bool = false
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
	# The first-visit help (FT-STN-012) would open the menu and block input.
	for station: String in StationViews.CREW + [StationViews.VIEWER, StationViews.CAPTAIN]:
		ctx.settings.mark_tooltip_seen(station)
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
	var marks: Array = [_mark(BRAVO_SLOT, "Bravo", _world(_at(8, -25.0, 1200.0)))]
	if seam:
		marks.append(_mark(ECHO_SLOT, "Echo", _site_pos(OWN_POS + SEAM_ECHO)))
	crew.handle_event({"type": "marks", "payload": {"ship": SHIP, "marks": marks}}, NOW_MS)
	ctx.view = view(seam)
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


## The snapshot view: own ship, STATUS and MOUNTS blocks, contacts H2, U3, F4 (and H5,
## H6 with `seam`).
static func view(seam: bool = false) -> NetViewState:
	var p_units: int = NetCodec.period_units(PERIOD_M)
	var v: NetViewState = NetViewState.new(p_units)
	v.seq = 10
	v.tick = TICK
	v.kin = {
		"site": 0,
		"pos": _units(OWN_POS, p_units),
		"vel": NetCodec.quant_vel(own_rotation() * Vector3(0.0, 0.0, -80.0)),
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
		"propellant": 8000.0,
		"decoupled": false,
	}
	# Helm (#7 A): assist on at 80 m/s, H2 selected and shields tracking it.
	v.blocks[StationViews.Section.HELM] = {
		"decoupled": false,
		"throttle_setpoint": 80.0,
		"face": false,
		"approach": false,
		"all_stop": false,
		"align": 0,
		"target_kind": 1,
		"target_ship": H2,
		"shield_focus": _at(4, 30.0, 1.0).normalized(),
		"shield_track": H2,
		"shield_tightness": 2.0,
		"shield_power": 1.0,
		"thrust_scale": 1.0,
		"torque_scale": 0.8,
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
	if seam:
		for c: Array in [[H5, "H5", SEAM_H5], [H6, "H6", SEAM_H6]]:
			model[c[0]] = [_units(OWN_POS + c[2], p_units), Vector3i.ZERO, TICK]
			info[c[0]] = [0, c[1]]
	v.contacts = {"model": model, "info": info}
	v.blocks[StationViews.Section.ENGINEERING] = engineering_block()
	return v


## The ENGINEERING block (m1_corvette): engines at 40 % and overcharged with crew A on
## them, weapons at 75 %, shields running hot, 6 spare parts, shields at 70 % with
## focus tightness 1.5 towards 1 o'clock; 10 of 12 reactor pips used.
static func engineering_block() -> Dictionary:
	var subsystems: Array = []
	# engines, thrusters, weapons, shields, sensors, reactor: [health, pips, heat, crews].
	for r: Array in [
		[0.4, 3, 30.0, 1],
		[1.0, 2, 0.0, 0],
		[0.75, 2, 0.0, 0],
		[1.0, 2, 80.0, 0],
		[1.0, 1, 0.0, 0],
		[1.0, 0, 0.0, 0]
	]:
		subsystems.append(
			{
				"health": r[0] * 20_000_000.0,
				"pips": r[1],
				"heat": r[2],
				"crews": r[3],
				"fault_armed": true
			}
		)
	return {
		"boost_ticks": 0,
		"weapon_energy": 3_000_000.0,
		"hull": 92_000_000.0,
		"spare_parts": 6,
		"shield_strength": 21_000_000.0,
		"shield_tightness": 1.5,
		"shield_focus": Vector3(0.5, 0.0, -0.866).normalized(),
		"subsystems": subsystems,
	}


static func own_rotation() -> Quaternion:
	var e: Vector3 = OWN_EULER_DEG
	return Quaternion.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)))


## Ship-frame offset at a clock hour, elevation (degrees) and range (m).
static func _at(clock_hour: int, elevation_deg: float, range_m: float) -> Vector3:
	var b: float = deg_to_rad(clock_hour * 30.0)
	var e: float = deg_to_rad(elevation_deg)
	var h: float = range_m * cos(e)
	return Vector3(sin(b) * h, range_m * sin(e), -cos(b) * h)


## A ship-frame offset as a site-local position.
static func _world(local: Vector3) -> Vector3:
	return _site_pos(OWN_POS + own_rotation() * local)


## A position wrapped into the site, [-P/2, P/2) on each axis.
static func _site_pos(p: Vector3) -> Vector3:
	var h: float = PERIOD_M / 2.0
	return Vector3(
		fposmod(p.x + h, PERIOD_M) - h,
		fposmod(p.y + h, PERIOD_M) - h,
		fposmod(p.z + h, PERIOD_M) - h
	)


## A free mark as the marks event carries it.
static func _mark(slot: int, mark_name: String, pos: Vector3) -> Dictionary:
	return {
		"slot": slot,
		"name": mark_name,
		"contact": -1,
		"site": 0,
		"x": pos.x,
		"y": pos.y,
		"z": pos.z,
		"by": "Ana",
	}


static func _units(p: Vector3, p_units: int) -> Vector3i:
	return NetCodec.quant_pos(p.x, p.y, p.z, p_units)
