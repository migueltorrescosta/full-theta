class_name TrainingPartners
extends RefCounted
## The scripted partner of a solo lesson (D303, FT-MIS-039): the bots that crew every other
## station press Next for their half of each pair step, a few seconds after the step starts,
## so the player hears the step before it ends. A pair step ends on both stations' Next
## (TrainingDriver), and the bot's press is an ordinary logged crew command, so the lesson
## replays. Call act() right before the driver's before_tick. It has no random choice: the
## same lesson gives the same presses.

## Ticks between a pair step starting and the partner's press (4 s).
const DELAY_TICKS: int = 4 * SimWorld.HZ

## Pair step intent -> the tick it was first seen on, and the ones already pressed.
var _seen: Dictionary[StringName, int] = {}
var _pressed: Dictionary[StringName, bool] = {}


func act(world: SimWorld, driver: TrainingDriver) -> void:
	var solo: StringName = driver.solo_station()
	if solo == &"" or driver.ship_id() < 0:
		return
	for step: TrainingStepDef in driver.active_pairs():
		var partner: StringName = step.partner if step.station == solo else step.station
		if partner == solo or _pressed.has(step.intent):
			continue
		if not _seen.has(step.intent):
			_seen[step.intent] = world.tick
		if world.tick - _seen[step.intent] >= DELAY_TICKS:
			_pressed[step.intent] = true
			var press: TrainingNextCommand = TrainingNextCommand.new()
			press.ship_id = driver.ship_id()
			press.station = partner
			world.submit(press)
