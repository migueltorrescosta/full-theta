extends GdUnitTestSuite
## SimCopy's two halves (FT-NET-040, D111): capture() on the sim thread takes a state that
## the live world can't change any more, and restore() on the net thread builds a world
## holding exactly that state, every table variable included.


func _world() -> SimWorld:
	var world: SimWorld = (
		M1Encounter.new(5, "test", TestDefs.corvette(), TestDefs.raider_enemy()).build()
	)
	var helm: HelmInputCommand = HelmInputCommand.new()
	helm.ship_id = M1Encounter.PLAYER_SHIP
	helm.throttle = 1.0
	helm.rotation = Vector3(0.2, 0.3, 0.0)
	world.submit(helm)
	for i: int in 30:
		world.step()
	return world


## Every script variable of every table (derived indexes too), the tick, the
## definitions and the RNG states, as bytes.
func _everything(world: SimWorld) -> PackedByteArray:
	var out: PackedByteArray = var_to_bytes([world.tick, world.rng.states(), world.defs.size()])
	for def: ShipDef in world.defs:
		out.append_array(var_to_bytes(def.get_instance_id()))
	for t: SimTable in world.tables():
		for p: Dictionary in t.get_property_list():
			if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
				out.append_array(var_to_bytes([p["name"], t.get(p["name"])]))
	return out


# FT: FT-NET-040
# A capture restored after the world has stepped on holds the world as it was at the
# capture, KnowledgeTable._rows (rebuilt, not copied) included.
func test_capture_is_detached_and_restores_everything() -> void:
	var world: SimWorld = _world()
	assert_int(world.knowledge.size()).is_greater(0)
	var at_capture: PackedByteArray = _everything(world)
	var state: Array = SimCopy.capture(world)
	for i: int in 30:
		world.step()
	assert_bool(_everything(world) == at_capture).is_false()
	var copy: SimWorld = SimCopy.restore(state)
	assert_bool(_everything(copy) == at_capture).is_true()


# FT: FT-NET-040
# The handoff across threads, as NetServer and NetTransport do it: a capture restored
# on another thread while the sim steps on the main thread holds the captured state.
func test_restore_on_another_thread_while_the_sim_steps() -> void:
	var world: SimWorld = _world()
	var at_capture: PackedByteArray = _everything(world)
	var state: Array = SimCopy.capture(world)
	var thread: Thread = Thread.new()
	thread.start(SimCopy.restore.bind(state))
	for i: int in 30:
		world.step()
	var copy: SimWorld = thread.wait_to_finish()
	assert_bool(_everything(copy) == at_capture).is_true()
	assert_bool(_everything(world) == at_capture).is_false()
