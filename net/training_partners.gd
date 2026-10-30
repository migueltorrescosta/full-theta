class_name TrainingPartners
extends RefCounted
## The scripted partner of a solo lesson (D303, FT-MIS-039): the bots that crew every other
## station (TrainingCrew) do their half of each pair step. A pair step ends on both stations'
## Next (TrainingDriver). For the steps in HALVES the partner first does the action the step
## teaches, HALF_TICKS after the step starts, so the player sees it on the partner glance
## card, then presses Next HALF_PRESS_TICKS later; for the others it presses Next after
## DELAY_TICKS. The press is an ordinary logged crew command, so the lesson replays. Call
## act() right before the driver's before_tick. There is no random choice: the same lesson
## gives the same actions.

## Ticks between a pair step starting and the partner's press when it has no scripted half
## (4 s).
const DELAY_TICKS: int = 4 * SimWorld.HZ
## Ticks to the scripted half (2 s), and from the half to the press (4 s).
const HALF_TICKS: int = 2 * SimWorld.HZ
const HALF_PRESS_TICKS: int = 4 * SimWorld.HZ

## "pair step intent|partner station" -> [the action TrainingCrew.half does, the partner
## glance read-out (PartnerGlance.readout id) that shows it]. The glance card of the
## partner at the player's station carries that read-out.
const HALVES: Dictionary = {
	"pair_p1|helm": [&"helm_speed", "helm.mode"],
	"pair_p1|engineering": [&"eng_boost", "eng.boost"],
	"pair_p2|helm": [&"helm_face", "helm.mode"],
	"pair_p3|helm": [&"helm_approach", "helm.mode"],
	"pair_p3|science": [&"sci_scan", "science.scan"],
	"pair_p6|engineering": [&"eng_weapons_pips", "eng.weapons"],
	"pair_p7|science": [&"sci_scan", "science.scan"],
	"pair_p10|engineering": [&"eng_sensors_pips", "eng.sensors"],
	"pair_p11|relay": [&"relay_probe", "relay.probes"],
	"pair_p13|relay": [&"relay_probe", "relay.probes"],
}

var crew: TrainingCrew

## Pair step intent -> the tick it was first seen on, and the ones already pressed.
var _seen: Dictionary[StringName, int] = {}
var _pressed: Dictionary[StringName, bool] = {}
var _acted: Dictionary[StringName, bool] = {}


func _init(seed_value: int = 0) -> void:
	crew = TrainingCrew.new(seed_value)


## The partner station of a pair step for a player at `solo`.
static func partner_of(step: TrainingStepDef, solo: StringName) -> StringName:
	return step.partner if step.station == solo else step.station


## The scripted half of a pair step for its partner: [action, read-out], or [].
static func half_of(step: TrainingStepDef, partner: StringName) -> Array:
	return HALVES.get("%s|%s" % [step.intent, partner], [])


## Ticks from a pair step starting to the partner's Next press.
static func press_ticks(step: TrainingStepDef, partner: StringName) -> int:
	return DELAY_TICKS if half_of(step, partner).is_empty() else HALF_TICKS + HALF_PRESS_TICKS


func act(world: SimWorld, driver: TrainingDriver) -> void:
	var solo: StringName = driver.solo_station()
	if solo == &"" or driver.ship_id() < 0:
		return
	var busy: Dictionary[StringName, bool] = {}
	for step: TrainingStepDef in driver.active_pairs():
		var partner: StringName = partner_of(step, solo)
		if partner == solo or _pressed.has(step.intent):
			continue
		busy[partner] = true
		if not _seen.has(step.intent):
			_seen[step.intent] = world.tick
		var age: int = world.tick - _seen[step.intent]
		var half: Array = half_of(step, partner)
		if not half.is_empty() and age >= HALF_TICKS and not _acted.has(step.intent):
			_acted[step.intent] = true
			crew.half(world, driver.ship_id(), partner, half[0])
		if age >= press_ticks(step, partner):
			_pressed[step.intent] = true
			var press: TrainingNextCommand = TrainingNextCommand.new()
			press.ship_id = driver.ship_id()
			press.station = partner
			world.submit(press)
	crew.act(world, driver, busy)
