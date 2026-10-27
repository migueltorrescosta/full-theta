extends GdUnitTestSuite
## SayCommand (E10): the server says a line; the sim emits a &"say" event carrying the
## line id, the audience ship and the arguments, and the command is logged as SERVER.


func _world() -> SimWorld:
	return M1Encounter.new(5, "test", TestDefs.corvette(), TestDefs.raider_enemy()).build()


# FT: FT-ARC-008
func test_say_event_carries_args_and_the_command_is_logged_as_server() -> void:
	var world: SimWorld = _world()
	var cmd: SayCommand = SayCommand.new()
	cmd.ship_id = 0
	cmd.line_id = "npc.hail_trader"
	cmd.npc_id = "trader_1"
	cmd.stations = ["comms"]
	cmd.args = {"npc": "Rosa"}
	assert_int(cmd.source).is_equal(SimCommand.Source.SERVER)
	world.submit(cmd)
	world.step()
	var says: Array[SimEvent] = world.events.filter(
		func(e: SimEvent) -> bool: return e.kind == &"say"
	)
	assert_array(says).has_size(1)
	assert_str(String(says[0].tag)).is_equal("npc.hail_trader")
	assert_int(says[0].ship_id).is_equal(0)
	assert_int(says[0].faction).is_equal(world.faction_of(0))
	assert_dict(says[0].args).is_equal({"npc": "Rosa", "npc_id": "trader_1", "stations": ["comms"]})
	assert_array(world.accepted_commands()).contains([cmd])
	var round: SimCommand = SimCommands.from_dict(cmd.to_dict())
	assert_object(round).is_instanceof(SayCommand)
	assert_str((round as SayCommand).line_id).is_equal("npc.hail_trader")
	assert_int(round.source).is_equal(SimCommand.Source.SERVER)


# FT: FT-ARC-008
func test_empty_line_id_is_rejected() -> void:
	var world: SimWorld = _world()
	var cmd: SayCommand = SayCommand.new()
	world.submit(cmd)
	world.step()
	assert_bool(cmd.accepted).is_false()
