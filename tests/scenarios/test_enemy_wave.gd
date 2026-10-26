extends GdUnitTestSuite
## The raider wave (FT-MIS-003, FT-MIS-004): raiders hail and taunt, and the encounter ends
## by destruction, by a surrender the crew asked for, or by the clock.

const SITE: StringName = &"vesper_beacon"


func _wave() -> ScenarioFixture:
	var f: ScenarioFixture = ScenarioFixture.make()
	f.begin(&"enemy_wave", SITE)
	f.run(3)
	return f


func _says(f: ScenarioFixture, line: String) -> bool:
	for c: SimCommand in f.world.command_log:
		if c.kind() == &"say" and (c as SayCommand).line_id == line:
			return true
	return false


# FT: FT-MIS-003, FT-MIS-041
func test_the_wave_hails_and_posts_a_hail_card() -> void:
	var f: ScenarioFixture = _wave()
	assert_int(f.ships_of(&"m1_raider").size()).is_equal(1)
	f.run(60 * 46)
	assert_int(f.ships_of(&"m1_raider").size()).is_equal(2)
	assert_bool(_says(f, "npc.hail_raider")).is_true()
	var hails: int = 0
	for c: CardView in f.api.cards_of(0):
		hails += 1 if c.kind == CardSpec.Kind.HAIL else 0
	assert_int(hails).is_equal(1)
	f.run(60 * 26)
	assert_bool(_says(f, "npc.taunt_raider")).is_true()


# FT: FT-MIS-004
func test_destroying_the_raiders_wins_the_encounter() -> void:
	var f: ScenarioFixture = _wave()
	f.run(60 * 46)
	for id: int in f.ships_of(&"m1_raider"):
		f.kill(id)
	assert_int(f.run_until_end(10)).is_equal(Scenario.Result.WON)


# FT: FT-MIS-004, FT-PAIR-004
func test_a_surrender_the_crew_asked_for_ends_it() -> void:
	var f: ScenarioFixture = _wave()
	var card: int = -1
	for c: CardView in f.api.cards_of(0):
		card = c.id
	var answer: AnswerHailCommand = AnswerHailCommand.new()
	answer.card = card
	assert_bool(f.send(answer)).is_true()
	var result: int = Scenario.Result.ACTIVE
	for i: int in 200:
		var reply: ReplyCommand = ReplyCommand.new()
		reply.card = card
		reply.option = &"o1"
		f.send(reply)
		result = f.api.encounter(f.encounter).result
		if result != Scenario.Result.ACTIVE:
			break
		f.run(2)
	f.run(3)
	assert_int(f.api.encounter(f.encounter).result).is_equal(Scenario.Result.WON)
	assert_bool(_says(f, "npc.surrender")).is_true()
	assert_int(f.world.relation(2, 1)).is_equal(Scenario.Relation.NEUTRAL)


# FT: FT-MIS-004
func test_the_clock_ends_it() -> void:
	var f: ScenarioFixture = _wave()
	f.world.damage.health[f.world.damage.hull_row(0)] = 1.0e15
	assert_int(f.run_until_end(60 * 250)).is_equal(Scenario.Result.WON)


# FT: FT-ARC-016
func test_relation_enum_matches_the_sim() -> void:
	assert_int(Scenario.Relation.FRIENDLY).is_equal(SimWorld.Relation.FRIENDLY)
	assert_int(Scenario.Relation.NEUTRAL).is_equal(SimWorld.Relation.NEUTRAL)
	assert_int(Scenario.Relation.HOSTILE).is_equal(SimWorld.Relation.HOSTILE)
	assert_int(CardView.State.EXPIRED).is_equal(StoryTable.State.EXPIRED)
