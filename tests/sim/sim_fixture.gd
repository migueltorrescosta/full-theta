class_name SimFixture
extends RefCounted
## Event and stepping helpers shared by the sim test suites.


## The events of one kind, in order.
static func of_kind(events: Array[SimEvent], kind: StringName) -> Array[SimEvent]:
	return events.filter(func(e: SimEvent) -> bool: return e.kind == kind)


## Steps the world, calling crew (if given) with it before each tick, and returns the
## events drained after each step, in order.
static func run(world: SimWorld, ticks: int, crew: Callable = Callable()) -> Array[SimEvent]:
	var events: Array[SimEvent] = []
	for i: int in ticks:
		if crew.is_valid():
			crew.call(world)
		world.step()
		events.append_array(world.drain_events())
	return events
