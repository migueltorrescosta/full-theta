extends GdUnitTestSuite
## Every Scenario API write is one queued SERVER command (E07, FT-DAT-009, FT-ARC-016,
## FT-ARC-008): it adds exactly one command to the queue, leaves the state tables as they
## were until the next step, and then lands in the command log as a SERVER command.


func _api(w: SimWorld) -> ScenarioApi:
	return ScenarioApi.new(w)


## Runs `write` on the api and checks the one-command rules; returns the queued command.
func _one(w: SimWorld, write: Callable, kind: StringName) -> SimCommand:
	var before_queue: int = w.queued_commands().size()
	var before_state: String = ApiFixture.tables_hash(w)
	var log_before: int = w.command_log.size()
	write.call(_api(w))
	var queued: Array[SimCommand] = w.queued_commands()
	assert_int(queued.size()).is_equal(before_queue + 1)
	assert_str(ApiFixture.tables_hash(w)).is_equal(before_state)
	assert_int(w.command_log.size()).is_equal(log_before)
	var cmd: SimCommand = queued[queued.size() - 1]
	assert_str(String(cmd.kind())).is_equal(String(kind))
	assert_int(cmd.source).is_equal(SimCommand.Source.SERVER)
	var tick: int = w.tick
	w.step()
	assert_array(w.command_log).contains([cmd])
	assert_int(cmd.tick).is_equal(tick)
	return cmd


# FT: FT-DAT-009, FT-ARC-016
func test_spawn_writes_queue_one_command_and_spawn_on_apply() -> void:
	var w: SimWorld = ApiFixture.world()
	var api: ScenarioApi = _api(w)
	var handle: ApiHandle = api.spawn_at_range(ApiFixture.RAIDER, 2, 0, 4000.0, 3, 0)
	# The id is not known until the command applies (Q24).
	assert_bool(handle.pending()).is_true()
	assert_int(handle.id()).is_equal(-1)
	assert_int(w.queued_commands().size()).is_equal(1)
	assert_int(w.ship_count()).is_equal(1)
	w.step()
	assert_bool(handle.pending()).is_false()
	assert_int(handle.id()).is_equal(1)
	assert_int(w.ship_count()).is_equal(2)
	# Clock 3 is starboard (+X): 4 km out, level.
	var rel: Vector3 = w.kin.relative(0, 1)
	assert_float(rel.length()).is_equal_approx(4000.0, 1.0)
	assert_float(rel.x).is_equal_approx(4000.0, 1.0)
	assert_bool(w.ai.is_enabled(1)).is_true()
	assert_int(w.faction_of(1)).is_equal(2)
	var log_cmd: SimCommand = w.command_log[0]
	assert_bool(log_cmd.accepted).is_true()
	assert_int(log_cmd.ship_id).is_equal(-1)


# FT: FT-DAT-009
func test_spawn_at_offset_and_on_leg_land_where_asked() -> void:
	var w: SimWorld = ApiFixture.world()
	var api: ScenarioApi = _api(w)
	var a: ApiHandle = api.spawn_at_offset(ApiFixture.RAIDER, 2, 0, Vector3(0.0, 500.0, 2000.0))
	var b: ApiHandle = api.spawn_on_leg(ApiFixture.RAIDER, 2, 0, 1, 0.5, 200.0)
	w.step()
	assert_int(b.id()).is_equal(a.id() + 1)
	assert_float(w.kin.relative_to_point(a.id(), 0.0, 500.0, 2000.0).length()).is_less(1.0)
	var mid: Vector3 = w.kin.relative_to_point(b.id(), 15000.0, 0.0, 0.0)
	assert_float(mid.length()).is_equal_approx(200.0, 1.0)


# FT: FT-DAT-009, FT-ARC-016
func test_each_write_is_one_server_command() -> void:
	var w: SimWorld = ApiFixture.world()
	var r: StringName = ApiFixture.RAIDER
	var helm: PackedStringArray = PackedStringArray(["helm"])
	var ship0: PackedInt32Array = PackedInt32Array([0])
	var writes: Array = [
		[func(a: ScenarioApi) -> void: a.spawn_at_range(r, 2, 0, 3000.0, 12, 1), &"spawn_ship"],
		[func(a: ScenarioApi) -> void: a.spawn_at_offset(r, 2, 0, Vector3.ZERO), &"spawn_ship"],
		[func(a: ScenarioApi) -> void: a.spawn_on_leg(r, 2, 0, 1, 0.3, 50.0), &"spawn_ship"],
		[func(a: ScenarioApi) -> void: a.open_site(&"beta"), &"open_site"],
		[
			func(a: ScenarioApi) -> void: a.set_relation(1, 2, SimWorld.Relation.NEUTRAL),
			&"set_relation"
		],
		[func(a: ScenarioApi) -> void: a.begin_encounter(&"s_a", 1, ship0, 3), &"begin_encounter"],
		[func(a: ScenarioApi) -> void: a.end_encounter(0, Scenario.Result.WON), &"end_encounter"],
		[
			func(a: ScenarioApi) -> void:
				a.message("computer.hello", {"x": 1}, SayTarget.computer(0, helm)),
			&"say"
		],
		[func(a: ScenarioApi) -> void: a.offer(0, CardSpec.new()), &"post_card"],
		[func(a: ScenarioApi) -> void: a.close_run(0), &"close_run"],
	]
	for pair: Array in writes:
		_one(w, pair[0], pair[1])


# FT: FT-DAT-009
func test_writes_take_effect_on_the_next_step() -> void:
	var w: SimWorld = ApiFixture.world()
	var api: ScenarioApi = _api(w)
	var opened: ApiHandle = api.open_site(&"beta")
	api.set_relation(1, 2, SimWorld.Relation.FRIENDLY)
	assert_int(opened.id()).is_equal(-1)
	assert_int(api.sites().size()).is_equal(2)
	w.step()
	assert_int(opened.id()).is_equal(2)
	assert_int(api.sites().size()).is_equal(3)
	assert_int(w.relation(1, 2)).is_equal(SimWorld.Relation.FRIENDLY)
	# Opening an open site queues nothing and names the existing id at once.
	var again: ApiHandle = api.open_site(&"beta")
	assert_int(again.id()).is_equal(2)
	assert_bool(again.pending()).is_false()
	assert_int(w.queued_commands().size()).is_equal(0)


# FT: FT-DAT-009
# Q24, owner 2026-10-26: a handle names the real id even when an earlier command of the same
# tick changes it. A crew hail applies first and adds a card, so the offered card is not the
# next row a prediction would have named.
func test_an_offered_card_resolves_to_its_real_id_after_a_crew_hail_in_the_same_tick() -> void:
	var w: SimWorld = StoryFixture.wire(ApiFixture.world())
	var raider: int = w.spawn_enemy(TestDefs.raider_enemy(), 2, Vector3(0.0, 0.0, -5000.0))
	w.hail_conversations[w.defs[raider].id] = &"conv.trader_bluff"
	w.step()
	var api: ScenarioApi = _api(w)
	var hail: HailCommand = HailCommand.new()
	hail.ship_id = 0
	hail.target = raider
	w.submit(hail)
	var card: CardSpec = CardSpec.new()
	card.title_key = &"comms.card.test"
	var handle: ApiHandle = api.offer(0, card)
	w.step()
	assert_bool(hail.accepted).is_true()
	assert_int(w.story.size()).is_equal(2)
	assert_int(handle.id()).is_equal(1)
	assert_str(w.story.title[handle.id()]).is_equal("comms.card.test")
	# The scenario finds its card by the handle's id, not by title.
	var ids: Array[int] = []
	for c: CardView in api.cards_of(0):
		ids.append(c.id)
	assert_array(ids).contains([handle.id()])


# FT: FT-DAT-009
# A write that applies and is refused leaves its handle rejected, with no id; the next
# write's handle is not shifted (review 2 M4: the director's begin, L5: a spawn).
func test_a_rejected_write_has_a_rejected_handle_and_shifts_no_other() -> void:
	var w: SimWorld = ApiFixture.world()
	var api: ScenarioApi = _api(w)
	var ship0: PackedInt32Array = PackedInt32Array([0])
	var first: ApiHandle = api.begin_encounter(&"s_a", 1, ship0, 3)
	var second: ApiHandle = api.begin_encounter(&"s_b", 1, ship0, 3)
	var bad: ApiHandle = api.spawn_at_range(&"no_such_enemy", 2, 0, 1000.0, 12, 0)
	var good: ApiHandle = api.spawn_at_range(ApiFixture.RAIDER, 2, 0, 1000.0, 12, 0)
	w.step()
	assert_int(first.id()).is_equal(0)
	assert_bool(second.rejected()).is_true()
	assert_int(second.id()).is_equal(-1)
	assert_bool(bad.rejected()).is_true()
	assert_int(good.id()).is_equal(1)
	assert_int(w.encounters.size()).is_equal(1)


# FT: FT-DAT-009
func test_message_without_a_listener_queues_nothing() -> void:
	var w: SimWorld = ApiFixture.world()
	w.run.status[0] = RunTable.Status.ABANDONED
	_api(w).message("npc.hello", {}, SayTarget.npc(&"rosa"))
	assert_int(w.queued_commands().size()).is_equal(0)


# FT: FT-DAT-009
func test_events_and_commands_of_the_latest_step() -> void:
	var w: SimWorld = ApiFixture.world()
	var api: ScenarioApi = _api(w)
	api.spawn_at_offset(ApiFixture.RAIDER, 2, 0, Vector3(0.0, 0.0, 500.0))
	w.step()
	w.drain_events()
	var spawned: Array[ApiEvent] = api.events().filter(
		func(e: ApiEvent) -> bool: return e.kind == &"ship_spawned"
	)
	assert_array(spawned).has_size(1)
	assert_int(spawned[0].ship_id).is_equal(1)
	assert_str(String(spawned[0].tag)).is_equal("raider")
	var crew: AllStopCommand = AllStopCommand.new()
	crew.ship_id = 0
	w.submit(crew)
	w.step()
	var seen: Array[ApiEvent] = api.commands_this_tick(0)
	assert_array(seen).has_size(1)
	assert_str(String(seen[0].kind)).is_equal("helm_all_stop")
	assert_array(api.commands_this_tick(1)).is_empty()
	w.step()
	assert_array(api.commands_this_tick(0)).is_empty()
