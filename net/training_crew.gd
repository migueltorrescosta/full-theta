class_name TrainingCrew
extends RefCounted
## The acting bots of a solo lesson (D303, FT-MIS-039): each station but the player's is
## crewed by a bot that submits real station commands at a calm pace, so the ship behaves
## as if crewed. Every command goes through send(), which refuses one that is not of the
## bot's own station (StationViews.STATION_COMMANDS) or that would be the player's, and
## submits it to the world as a crew command (the log records it, so the lesson replays).
## What each does, looking once every LOOK_TICKS (a seeded phase apart):
## - Helm holds station: All stop when the ship drifts;
## - Weapons tracks the nearest hostile with mount 0 (it never fires on its own);
## - Engineering sends idle repair crews to damaged subsystems and cools a subsystem that
##   runs hot back to its nominal pips;
## - Science scans the nearest hostile now and then, then closes the scan;
## - Relay launches one probe a while in;
## - Comms answers the hails that come in.
## A station that is the partner of an open pair step is left to TrainingPartners, whose
## scripted halves (half()) act for it. The Captain has no bot. No random choice beyond the
## seeded phases, so the same lesson gives the same commands.

## Ticks between two looks of one bot (2 s).
const LOOK_TICKS: int = 2 * SimWorld.HZ
## Helm lets the ship drift below this speed (m/s).
const REST_MS: float = 8.0
## Weapons and Science look this far for the drone (m).
const SIGHT_M: float = 12000.0
## Science keeps a scan open this long, and waits this long before the next (ticks).
const SCAN_HOLD_TICKS: int = 8 * SimWorld.HZ
const SCAN_WAIT_TICKS: int = 40 * SimWorld.HZ
## Relay launches its probe this long after the lesson starts, and this far ahead (m).
const PROBE_AFTER_TICKS: int = 30 * SimWorld.HZ
const PROBE_AHEAD_M: float = 3000.0
## A subsystem above its nominal pips cools down at this share of its fault heat.
const COOL_SHARE: float = 0.7

## Whether send() keeps a record: [tick, station, kind] per command.
var record: bool = false
var sent: Array[Array] = []

var _solo: StringName = &""
var _phase: Dictionary[StringName, int] = {}
var _scan_at: int = -SCAN_WAIT_TICKS
var _scanning: bool = false
var _probe_sent: bool = false
var _started_tick: int = -1


func _init(seed_value: int = 0) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	for station: String in StationViews.CREW:
		_phase[StringName(station)] = rng.randi_range(0, LOOK_TICKS - 1)


## Looks for every bot that is not `busy` (a station -> true map of partners in an open pair
## step). Call it right before the driver's before_tick.
func act(world: SimWorld, driver: TrainingDriver, busy: Dictionary[StringName, bool]) -> void:
	_solo = driver.solo_station()
	var ship: int = driver.ship_id()
	if _solo == &"" or ship < 0 or not world.kin.is_alive(ship):
		return
	if _started_tick < 0:
		_started_tick = world.tick
	for station: String in StationViews.CREW:
		var who: StringName = StringName(station)
		if who == _solo or busy.has(who):
			continue
		if (world.tick + _phase[who]) % LOOK_TICKS != 0:
			continue
		match who:
			&"helm":
				_helm(world, ship)
			&"weapons":
				_weapons(world, ship)
			&"engineering":
				_engineering(world, ship)
			&"science":
				_science(world, ship)
			&"relay":
				_relay(world, ship)
			&"comms":
				_comms(world, ship)


## Submits `command` for the bot of `station`; false when the station is the player's or the
## command is not of that station.
func send(world: SimWorld, ship: int, station: StringName, command: SimCommand) -> bool:
	if station == _solo or StationViews.station_of_command(command.kind()) != String(station):
		return false
	command.ship_id = ship
	world.submit(command)
	if record:
		sent.append([world.tick, station, command.kind()])
	return true


# --- the bots ---


func _helm(world: SimWorld, ship: int) -> void:
	var held: bool = world.helm.face_held[ship] == 1 or world.helm.approach_held[ship] == 1
	if held:
		var release: HelmInputCommand = HelmInputCommand.new()
		send(world, ship, &"helm", release)
	elif world.kin.vel[ship].length() > REST_MS and world.helm.all_stop[ship] == 0:
		send(world, ship, &"helm", AllStopCommand.new())


func _weapons(world: SimWorld, ship: int) -> void:
	var target: int = CrewMoves.nearest_hostile(world, ship, SIGHT_M)
	if target >= 0:
		send(world, ship, &"weapons", CrewMoves.aim(world, ship, target))


func _engineering(world: SimWorld, ship: int) -> void:
	var repair: DispatchRepairCommand = CrewMoves.repair(world, ship)
	if repair != null:
		send(world, ship, &"engineering", repair)
		return
	var def: ShipDef = world.defs[ship]
	for sub: SubsystemDef in def.subsystems:
		var row: int = world.damage.find_subsystem(ship, sub.id)
		var hot: bool = world.damage.heat[row] > COOL_SHARE * sub.fault_heat_threshold
		if (
			sub.kind != SubsystemDef.Kind.REACTOR
			and hot
			and world.damage.pips[row] > sub.nominal_pips
		):
			var cool: SetPipsCommand = SetPipsCommand.new()
			cool.subsystem_kind = sub.kind
			cool.pips = sub.nominal_pips
			send(world, ship, &"engineering", cool)
			return


func _science(world: SimWorld, ship: int) -> void:
	var now: int = world.tick
	if _scanning:
		if now - _scan_at >= SCAN_HOLD_TICKS:
			_scanning = false
			send(world, ship, &"science", ScienceCancelCommand.new())
		return
	if now - _scan_at < SCAN_WAIT_TICKS or world.science.kind[ship] != ScienceTable.Session.NONE:
		return
	var target: int = CrewMoves.nearest_hostile(world, ship, SIGHT_M)
	if target >= 0:
		var scan: ScienceScanCommand = ScienceScanCommand.new()
		scan.contact = target
		_scan_at = now
		_scanning = send(world, ship, &"science", scan)


func _relay(world: SimWorld, ship: int) -> void:
	if _probe_sent or world.tick - _started_tick < PROBE_AFTER_TICKS:
		return
	_probe_sent = true
	send(world, ship, &"relay", _probe(world, ship))


func _comms(world: SimWorld, ship: int) -> void:
	var story: StoryTable = world.story
	for card: int in story.size():
		if not Story.visible_to(world, card, ship):
			continue
		if story.kind[card] == StoryTable.Kind.HAIL and story.state[card] == StoryTable.State.OPEN:
			var answer: AnswerHailCommand = AnswerHailCommand.new()
			answer.card = card
			send(world, ship, &"comms", answer)
			return


# --- the scripted halves of pair steps ---


## Does the action a pair step teaches for `station`'s bot (HALVES names them); the player
## sees it on the partner glance card.
func half(world: SimWorld, ship: int, station: StringName, action: StringName) -> void:
	var target: int = CrewMoves.nearest_hostile(world, ship, SIGHT_M)
	match action:
		&"helm_speed":
			var h: HelmInputCommand = HelmInputCommand.new()
			h.throttle = 0.5
			send(world, ship, station, h)
		&"helm_face", &"helm_approach":
			if target >= 0:
				var select: SelectTargetCommand = SelectTargetCommand.new()
				select.target_ship = target
				send(world, ship, station, select)
			var f: HelmInputCommand = HelmInputCommand.new()
			f.face = true
			f.approach = action == &"helm_approach"
			send(world, ship, station, f)
		&"eng_boost":
			send(world, ship, station, BoostCommand.new())
		&"eng_weapons_pips":
			_pip(world, ship, station, SubsystemDef.Kind.WEAPONS)
		&"eng_sensors_pips":
			_pip(world, ship, station, SubsystemDef.Kind.SENSORS)
		&"sci_scan":
			if target >= 0:
				send(world, ship, station, ScienceCancelCommand.new())
				var scan: ScienceScanCommand = ScienceScanCommand.new()
				scan.contact = target
				_scan_at = world.tick
				_scanning = send(world, ship, station, scan)
		&"relay_probe":
			send(world, ship, station, _probe(world, ship))


## One more pip on a subsystem (one fewer when it is at the top), taking it from the engines
## when the reactor has none to spare.
func _pip(world: SimWorld, ship: int, station: StringName, kind: int) -> void:
	var def: ShipDef = world.defs[ship]
	var cur: int = 0
	var used: int = 0
	var engines: int = 0
	for sub: SubsystemDef in def.subsystems:
		var pips: int = world.damage.pips[world.damage.find_subsystem(ship, sub.id)]
		used += pips
		if sub.kind == kind:
			cur = pips
		if sub.kind == SubsystemDef.Kind.ENGINES:
			engines = pips
	var want: SetPipsCommand = SetPipsCommand.new()
	want.subsystem_kind = kind
	if cur >= def.power.max_pips_per_subsystem:
		want.pips = cur - 1
	else:
		want.pips = cur + 1
		if used + 1 > def.power.reactor_pips:
			var give: SetPipsCommand = SetPipsCommand.new()
			give.subsystem_kind = SubsystemDef.Kind.ENGINES
			give.pips = maxi(0, engines - 1)
			send(world, ship, station, give)
	send(world, ship, station, want)


func _probe(world: SimWorld, ship: int) -> LaunchProbeCommand:
	var ahead: Vector3 = world.kin.forward(ship) * PROBE_AHEAD_M
	var probe: LaunchProbeCommand = LaunchProbeCommand.new()
	probe.x = world.kin.px[ship] + ahead.x
	probe.y = world.kin.py[ship] + ahead.y
	probe.z = world.kin.pz[ship] + ahead.z
	return probe
