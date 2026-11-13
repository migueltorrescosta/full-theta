class_name StandInCrew
extends RefCounted
## The stand-in bots of one ship (gp-01, gp-03; #40 D1, D2): a novice crewman on each station
## a bot holds, a dropped player's after the grace or a light station the host filled at
## Start (NetLobby.bots). Like the solo-lesson bots (TrainingCrew, D306) it acts only through
## the ApiCrew verbs, so its commands are logged and a run replays. Its numbers are a
## StandInDef (content/runs/stand_in.tres), the novice of tools/bots/profiles.gd:
## - Helm faces the nearest hostile at cruise speed; with none near it faces the site of the
##   ship's encounter and jumps there; at the site it holds station;
## - Weapons aims at the nearest armed hostile with an error, and fires at the cadence once
##   the target stood reaction_time, skipping a share of the shots;
## - Engineering, Science, Relay and Comms look as the lesson bots do (TrainingCrew.look).
## The server keeps one per ship and makes them again with every new world (NetServer).

## Helm's state: no hold, or holding the face of a site (SITE_HOLD - site).
const IDLE: int = -1
const SITE_HOLD: int = -1000
## Helm holds station below this speed (m/s), as the lesson's Helm bot does.
const REST_MS: float = TrainingCrew.REST_MS

var _def: StandInDef
var _ship: int
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _lesson: TrainingCrew
var _phase: Dictionary[StringName, int] = {}
var _look_ticks: int
var _aim_ticks: int
var _fire_ticks: int
var _react_ticks: int
## Weapons: its target, the tick it first saw it, the tick of the next due shot.
var _target: int = -1
var _seen_at: int = 0
var _next_fire: int = 0
## Helm: the contact it faces (>= 0), a site hold (SITE_HOLD - site) or IDLE; its throttle.
var _helm_on: int = IDLE
var _throttle: float = 0.0


func _init(def: StandInDef, ship: int, seed_value: int) -> void:
	_def = def
	_ship = ship
	_rng.seed = seed_value + ship
	_lesson = TrainingCrew.new(seed_value + ship)
	_look_ticks = maxi(1, SimRate.ticks(def.look_every))
	_aim_ticks = maxi(1, SimRate.ticks(def.aim_every))
	_fire_ticks = maxi(1, SimRate.ticks(def.fire_every))
	_react_ticks = SimRate.ticks(def.reaction_time)
	for station: StringName in TrainingCrew.STATIONS:
		_phase[station] = _rng.randi_range(0, _look_ticks - 1)


## Acts for `stations` (the ship's bot stations no player covers now) before a tick.
func act(api: ScenarioApi, stations: Array) -> void:
	var hands: ApiCrew = api.crew()
	if not hands.alive(_ship):
		return
	var t: int = api.tick()
	for station: Variant in stations:
		var who: StringName = StringName(station)
		if who == &"weapons":
			if (t + _phase[who]) % _aim_ticks == 0:
				_weapons(hands, t)
		elif _phase.has(who) and (t + _phase[who]) % _look_ticks == 0:
			if who == &"helm":
				_helm(hands)
			else:
				_lesson.look(api, _ship, who)


func _weapons(hands: ApiCrew, t: int) -> void:
	var target: int = hands.nearest_hostile(_ship, _def.sight_reach, true)
	if target != _target:
		_target = target
		_seen_at = t
	if target < 0:
		return
	# One gunner: the mount whose arc holds the target (gp-12).
	var mount: int = hands.mount_for(_ship, target)
	hands.aim_at(_ship, target, _def.aim_error, _rng, mount)
	if t - _seen_at < _react_ticks or t < _next_fire:
		return
	if hands.range_to(_ship, target) > _def.shoot_reach:
		return
	_next_fire = t + _fire_ticks
	if _rng.randf() >= _def.fire_skip:
		hands.fire(_ship, mount)


func _helm(hands: ApiCrew) -> void:
	var hostile: int = hands.nearest_hostile(_ship, _def.sight_reach)
	if hostile >= 0:
		var throttle: float = 1.0 if hands.speed(_ship) < _def.cruise_ms else 0.0
		if hostile != _helm_on or throttle != _throttle:
			hands.helm_face(_ship, hostile if hostile != _helm_on else -1, false, throttle)
			_helm_on = hostile
			_throttle = throttle
		return
	var site: int = hands.encounter_site(_ship)
	if site >= 0 and not hands.at_site(_ship, site):
		if _helm_on != SITE_HOLD - site:
			_helm_on = SITE_HOLD - site
			_throttle = 0.0
			hands.face_site(_ship, site)
		else:
			hands.jump_to(_ship, site, _def.jump_aim_share)
		return
	_helm_on = IDLE
	_throttle = 0.0
	hands.helm_settle(_ship, REST_MS)
