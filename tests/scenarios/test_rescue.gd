extends GdUnitTestSuite
## The distress call (FT-MIS-003, FT-MIS-004): escort and salvage differ in reward and standing,
## and ignoring the call pays nothing.


func _rescue() -> ScenarioFixture:
	var f: ScenarioFixture = ScenarioFixture.make()
	f.begin(&"rescue", &"vesper_beacon")
	f.run(3)
	return f


func _card(f: ScenarioFixture, title: String) -> int:
	for c: CardView in f.api.cards_of(0):
		if c.title_key == title:
			return c.id
	return -1


func _accept(f: ScenarioFixture, card: int) -> void:
	var accept: AcceptCardCommand = AcceptCardCommand.new()
	accept.card = card
	assert_bool(f.send(accept)).is_true()


func _raiders_arrive(f: ScenarioFixture) -> Array[int]:
	f.run(60 * 51)
	return f.ships_of(&"m1_raider")


func _standing(f: ScenarioFixture) -> float:
	return f.world.reputation.value_of(f.world.faction_of(0), 3)


# FT: FT-MIS-004, FT-MIS-021
func test_escort_pays_and_raises_standing() -> void:
	var f: ScenarioFixture = _rescue()
	var credits: int = Economy.credits(f.world, 0)
	_accept(f, _card(f, "comms.card.escort"))
	var raiders: Array[int] = _raiders_arrive(f)
	assert_int(raiders.size()).is_equal(2)
	for id: int in raiders:
		f.kill(id)
	assert_int(f.run_until_end(30)).is_equal(Scenario.Result.WON)
	f.run(3)
	assert_int(Economy.credits(f.world, 0)).is_equal(credits + 400)
	assert_float(_standing(f)).is_greater(0.0)


# FT: FT-MIS-004, FT-MIS-021
func test_salvage_pays_more_and_costs_standing() -> void:
	var f: ScenarioFixture = _rescue()
	var credits: int = Economy.credits(f.world, 0)
	_accept(f, _card(f, "comms.card.salvage"))
	var raiders: Array[int] = _raiders_arrive(f)
	var freighter: int = f.ships_of(&"m3_stranded")[0]
	var at: Vector3 = f.world.kin.relative(0, freighter)
	f.world.kin.place(
		0, f.world.kin.px[0] + at.x, f.world.kin.py[0] + at.y, f.world.kin.pz[0] + at.z - 300.0
	)
	f.run(60 * 9)
	for id: int in raiders:
		f.kill(id)
	assert_int(f.run_until_end(60)).is_equal(Scenario.Result.WON)
	f.run(3)
	assert_int(Economy.credits(f.world, 0)).is_equal(credits + 700)
	assert_float(_standing(f)).is_less(0.0)


# FT: FT-MIS-004
func test_a_lost_freighter_fails_the_escort() -> void:
	var f: ScenarioFixture = _rescue()
	var credits: int = Economy.credits(f.world, 0)
	var card: int = _card(f, "comms.card.escort")
	_accept(f, card)
	var raiders: Array[int] = _raiders_arrive(f)
	f.kill(f.ships_of(&"m3_stranded")[0])
	for id: int in raiders:
		f.kill(id)
	assert_int(f.run_until_end(30)).is_equal(Scenario.Result.WON)
	f.run(3)
	assert_int(Economy.credits(f.world, 0)).is_equal(credits)
	assert_int(f.card_state(card)).is_equal(CardView.State.FAILED)
	assert_float(_standing(f)).is_less(0.0)


# FT: FT-MIS-004
func test_ignoring_the_call_pays_nothing() -> void:
	var f: ScenarioFixture = _rescue()
	var credits: int = Economy.credits(f.world, 0)
	for id: int in _raiders_arrive(f):
		f.kill(id)
	assert_int(f.run_until_end(30)).is_equal(Scenario.Result.WON)
	assert_int(Economy.credits(f.world, 0)).is_equal(credits)
