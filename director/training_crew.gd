class_name TrainingCrew
extends RefCounted
## The acting bots of a solo lesson (D303, FT-MIS-039): each station but the player's is
## crewed by a bot that submits real station commands at a calm pace, so the ship behaves
## as if crewed. Every bot acts only through the ApiCrew verbs, each fixed to one station, and
## never for the player's station; the verbs submit real crew commands (the log records them,
## so the lesson replays).
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
const LOOK_TICKS: int = 2 * SimRate.HZ
## Helm lets the ship drift below this speed (m/s).
const REST_MS: float = 8.0
## Weapons and Science look this far for the drone (m).
const SIGHT_REACH: float = 12000.0
## Science keeps a scan open this long, and waits this long before the next (ticks).
const SCAN_HOLD_TICKS: int = 8 * SimRate.HZ
const SCAN_WAIT_TICKS: int = 40 * SimRate.HZ
## Relay launches its probe this long after the lesson starts, and this far ahead (m).
const PROBE_AFTER_TICKS: int = 30 * SimRate.HZ
const PROBE_AHEAD_DISTANCE: float = 3000.0
## A subsystem above its nominal pips cools down at this share of its fault heat.
const COOL_SHARE: float = 0.7
## The crew stations a bot can hold, in the order they look.
const STATIONS: Array[StringName] = [
	&"helm", &"weapons", &"engineering", &"science", &"relay", &"comms"
]

var _solo: StringName = &""
var _phase: Dictionary[StringName, int] = {}
var _scan_at: int = -SCAN_WAIT_TICKS
var _scanning: bool = false
var _probe_sent: bool = false
var _started_tick: int = -1


func _init(seed_value: int = 0) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	for station: StringName in STATIONS:
		_phase[station] = rng.randi_range(0, LOOK_TICKS - 1)


## Looks for every bot that is not `busy` (a station -> true map of partners in an open pair
## step). Call it right before the driver's before_tick.
func act(api: ScenarioApi, driver: TrainingDriver, busy: Dictionary[StringName, bool]) -> void:
	_solo = driver.solo_station()
	var ship: int = driver.ship_id()
	var hands: ApiCrew = api.crew()
	if _solo == &"" or not hands.alive(ship):
		return
	if _started_tick < 0:
		_started_tick = api.tick()
	for who: StringName in STATIONS:
		if who == _solo or busy.has(who):
			continue
		if (api.tick() + _phase[who]) % LOOK_TICKS != 0:
			continue
		match who:
			&"helm":
				hands.helm_settle(ship, REST_MS)
			&"weapons":
				_weapons(hands, ship)
			&"engineering":
				_engineering(hands, ship)
			&"science":
				_science(api, hands, ship)
			&"relay":
				_relay(api, hands, ship)
			&"comms":
				hands.answer_hail(ship)


# --- the bots ---


func _weapons(hands: ApiCrew, ship: int) -> void:
	var target: int = hands.nearest_hostile(ship, SIGHT_REACH)
	if target >= 0:
		hands.aim_at(ship, target)


func _engineering(hands: ApiCrew, ship: int) -> void:
	if not hands.repair_next(ship):
		hands.cool_hot(ship, COOL_SHARE)


func _science(api: ScenarioApi, hands: ApiCrew, ship: int) -> void:
	var now: int = api.tick()
	if _scanning:
		if now - _scan_at >= SCAN_HOLD_TICKS:
			_scanning = false
			hands.cancel_scan(ship)
		return
	if now - _scan_at < SCAN_WAIT_TICKS or not hands.science_idle(ship):
		return
	var target: int = hands.nearest_hostile(ship, SIGHT_REACH)
	if target >= 0:
		_scan_at = now
		_scanning = hands.scan(ship, target)


func _relay(api: ScenarioApi, hands: ApiCrew, ship: int) -> void:
	if _probe_sent or api.tick() - _started_tick < PROBE_AFTER_TICKS:
		return
	_probe_sent = true
	hands.launch_probe(ship, PROBE_AHEAD_DISTANCE)


# --- the scripted halves of pair steps ---


## Does the action a pair step teaches for `station`'s bot (HALVES names them); the player
## sees it on the partner glance card. Nothing for the player's own station.
func half(api: ScenarioApi, ship: int, station: StringName, action: StringName) -> void:
	if station == _solo:
		return
	var hands: ApiCrew = api.crew()
	var target: int = hands.nearest_hostile(ship, SIGHT_REACH)
	match action:
		&"helm_speed":
			hands.helm_speed(ship, 0.5)
		&"helm_face", &"helm_approach":
			hands.helm_face(ship, target, action == &"helm_approach")
		&"eng_boost":
			hands.boost(ship)
		&"eng_weapons_pips":
			hands.pip_up(ship, SubsystemDef.Kind.WEAPONS)
		&"eng_sensors_pips":
			hands.pip_up(ship, SubsystemDef.Kind.SENSORS)
		&"sci_scan":
			if target >= 0:
				_scan_at = api.tick()
				_scanning = hands.rescan(ship, target)
		&"relay_probe":
			hands.launch_probe(ship, PROBE_AHEAD_DISTANCE)
