class_name TrainingDriver
extends RefCounted
## Steps the Shakedown (FT-MIS-039, D100, D235, FT-PAIR-012). It has the same
## before_tick(api) as the Director and makes no decisions: it never opens sites, picks
## scenarios or spends budget. It steps its one training Scenario and runs the stations'
## tracks from a TrainingStepsDef.
##
## Each station has its own track at its own pace: the step it is on is said to it through
## ScenarioApi.message (the ship computer's line, for that station only), and the station
## moves on when the step ends. A COMMAND step ends when ScenarioApi.commands_this_tick
## shows its command from the ship; a NEXT step ends when the station presses Next (the
## flag train.<station>.next, TrainingNextCommand, counts the presses). Once both stations
## of a pair have finished their tracks, the pair's step starts; it ends when both press
## Next. A station never sees another station's step. Nothing here is hashed: what it
## decides is in the command log (say, set_flag), so a run replays without it.

## A step is said again to a station that has not finished it after this long (s), so a
## player who joined late, or looked away, hears it.
const REMIND_S: float = 45.0
## Dialogue lines for a finished track (per station) and a finished Shakedown.
const LINE_TRACK_DONE: String = "shakedown.%s.track_done"
const LINE_ALL_DONE: String = "shakedown.all_done"
## The flag the server keeps at 1 while a Captain sits on the ship (Q20, owner 2026-10-26):
## the Captain's track counts toward the end only then, other tracks always.
const CAPTAIN_SEATED: StringName = &"train.captain.seated"
const CAPTAIN: StringName = &"captain"

var _scenario: Scenario
var _def: TrainingStepsDef
var _started: bool = false
var _ship: int = -1
## Station -> its track's steps, and the index of the step it is on (the track length once
## it has finished).
var _tracks: Dictionary[StringName, Array] = {}
var _index: Dictionary[StringName, int] = {}
## Station -> Next presses already read, and the tick its step was last said.
var _seen: Dictionary[StringName, int] = {}
var _said: Dictionary[StringName, int] = {}
var _pairs: Array[TrainingStepDef] = []
## Pair index -> 0 waiting, 1 on, 2 done.
var _pair_state: Array[int] = []
## Station -> the pair step it is in (an index into _pairs), or -1.
var _in_pair: Dictionary[StringName, int] = {}
## Station -> pressed Next in its current pair step.
var _pair_pressed: Dictionary[StringName, bool] = {}
var _closed: bool = false


func _init(scenario: Scenario, steps: TrainingStepsDef) -> void:
	_scenario = scenario
	_def = steps
	for s: TrainingStepDef in steps.steps:
		if not s.is_pair() and not _tracks.has(s.station):
			_tracks[s.station] = steps.track(s.station)
			_index[s.station] = 0
			_seen[s.station] = 0
			_said[s.station] = -1000000
			_in_pair[s.station] = -1
	_pairs = steps.pairs()
	_pair_state.resize(_pairs.size())
	_pair_state.fill(0)


## Called by ScenarioHost before every tick.
func before_tick(api: ScenarioApi) -> void:
	if not _started and not _start(api):
		return
	_scenario.step(api)
	var now: int = api.tick()
	var tags: Dictionary[StringName, bool] = {}
	for e: ApiEvent in api.commands_this_tick(_ship):
		tags[e.tag] = true
	for station: StringName in _tracks:
		_step_station(api, now, station, tags)
	_step_pairs(api, now)
	if not _closed and _all_finished(api):
		_closed = true
		_say(api, LINE_ALL_DONE, stations())


## The step a station is on, or null when its track is finished.
func current(station: StringName) -> TrainingStepDef:
	var track: Array = _tracks.get(station, [])
	var i: int = _index.get(station, 0)
	return track[i] if i < track.size() else null


## Whether the station has finished its track.
func finished(station: StringName) -> bool:
	return _tracks.has(station) and current(station) == null


## The pair steps that are on now.
func active_pairs() -> Array[TrainingStepDef]:
	var out: Array[TrainingStepDef] = []
	for i: int in _pairs.size():
		if _pair_state[i] == 1:
			out.append(_pairs[i])
	return out


func _start(api: ScenarioApi) -> bool:
	var crew: PackedInt32Array = api.crew_ships()
	if crew.is_empty():
		return false
	_ship = crew[0]
	_started = true
	_scenario.start(api, {"site": 0, "ships": crew})
	for station: StringName in _tracks:
		_announce(api, api.tick(), station)
	return true


func _step_station(
	api: ScenarioApi, now: int, station: StringName, tags: Dictionary[StringName, bool]
) -> void:
	var presses: int = api.flag(next_flag(station))
	var pressed: bool = presses > _seen[station]
	_seen[station] = presses
	if _in_pair[station] >= 0:
		_pair_pressed[station] = _pair_pressed.get(station, false) or pressed
		return
	var step: TrainingStepDef = current(station)
	if step == null:
		return
	var done: bool = false
	if step.kind == TrainingStepDef.Kind.COMMAND:
		done = tags.has(step.command)
	else:
		done = pressed
	if done:
		_index[station] += 1
		_announce(api, now, station)
	elif now - _said[station] >= int(REMIND_S * ScenarioApi.HZ):
		_announce(api, now, station)


func _step_pairs(api: ScenarioApi, now: int) -> void:
	for i: int in _pairs.size():
		var step: TrainingStepDef = _pairs[i]
		match _pair_state[i]:
			0:
				if _free(step.station) and _free(step.partner):
					_pair_state[i] = 1
					_in_pair[step.station] = i
					_in_pair[step.partner] = i
					_pair_pressed[step.station] = false
					_pair_pressed[step.partner] = false
					_say(api, step.line, [step.station, step.partner] as Array[StringName])
					_said[step.station] = now
					_said[step.partner] = now
			1:
				if (
					_pair_pressed.get(step.station, false)
					and _pair_pressed.get(step.partner, false)
				):
					_pair_state[i] = 2
					_in_pair[step.station] = -1
					_in_pair[step.partner] = -1
				elif now - _said[step.station] >= int(REMIND_S * ScenarioApi.HZ):
					_say(api, step.line, [step.station, step.partner] as Array[StringName])
					_said[step.station] = now
					_said[step.partner] = now


## A station that has finished its track and is in no pair step.
func _free(station: StringName) -> bool:
	return _tracks.has(station) and finished(station) and _in_pair[station] < 0


func _all_finished(api: ScenarioApi) -> bool:
	for station: StringName in _tracks:
		if station == CAPTAIN and api.flag(CAPTAIN_SEATED) == 0:
			continue
		if not finished(station):
			return false
	for state: int in _pair_state:
		if state != 2:
			return false
	return true


## Says the station's current step, or that its track is done.
func _announce(api: ScenarioApi, now: int, station: StringName) -> void:
	_said[station] = now
	var step: TrainingStepDef = current(station)
	_say(
		api,
		step.line if step != null else LINE_TRACK_DONE % station,
		[station] as Array[StringName]
	)


func _say(api: ScenarioApi, line: String, stations: Array[StringName]) -> void:
	var names: PackedStringArray = PackedStringArray()
	for station: StringName in stations:
		names.append(String(station))
	api.message(line, {}, SayTarget.computer(_ship, names))


func stations() -> Array[StringName]:
	var out: Array[StringName] = []
	for station: StringName in _tracks:
		out.append(station)
	return out


static func next_flag(station: StringName) -> StringName:
	return StringName("train.%s.next" % station)
