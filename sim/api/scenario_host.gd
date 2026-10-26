class_name ScenarioHost
extends RefCounted
## Steps a world together with the director (E07, FT-ARC-016): net/ and the bot batch call
## advance() instead of SimWorld.advance(). Before each tick the driver's before_tick runs
## with the API, so the director sees the world between ticks and queues SERVER commands
## that apply on that tick; then the world steps. The driver is a Director or a
## TrainingDriver (anything with before_tick(api)).

var _world: SimWorld
var _api: ScenarioApi


func _init(world: SimWorld) -> void:
	_world = world
	_api = ScenarioApi.new(world)


## Whether this host steps that world.
func holds(world: SimWorld) -> bool:
	return world == _world


func api() -> ScenarioApi:
	return _api


## Adds frame time and steps whole ticks (SimWorld.advance), calling before_tick(api)
## right before each; returns the ticks stepped. An invalid callable steps without a driver.
func advance(delta: float, before_tick: Callable) -> int:
	if not before_tick.is_valid():
		return _world.advance(delta)
	return _world.advance(delta, func() -> void: before_tick.call(_api))
