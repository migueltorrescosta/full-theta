class_name SimFixture
extends RefCounted
## Event and stepping helpers shared by the sim test suites.


## The events of one kind, in order.
static func of_kind(events: Array[SimEvent], kind: StringName) -> Array[SimEvent]:
	return events.filter(func(e: SimEvent) -> bool: return e.kind == kind)


## Steps the world and returns the events drained after each step, in order.
static func run(world: SimWorld, ticks: int) -> Array[SimEvent]:
	var events: Array[SimEvent] = []
	for i: int in ticks:
		world.step()
		events.append_array(world.drain_events())
	return events


## Index in ShipDef.subsystems of the ship's subsystem with that id (it must exist).
static func sub_index(world: SimWorld, ship: int, subsystem_id: StringName) -> int:
	return world.damage.find_subsystem(ship, subsystem_id) - world.damage.subsystem_row(ship, 0)


## The ship's subsystem values of a DamageTable column (e.g. "pips", "heat"), in
## ShipDef.subsystems order.
static func sub_values(world: SimWorld, ship: int, column: String) -> Array:
	var first: int = world.damage.subsystem_row(ship, 0)
	var values: Variant = world.damage.get(column)
	return Array(values.slice(first, first + world.defs[ship].subsystems.size()))
