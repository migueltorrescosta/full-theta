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
# The raider's engines are shot up (the demand needs some engine damage, #35 A4) and Comms
# asks again each time a refusal's 25 s are over.
func test_a_surrender_the_crew_asked_for_ends_it() -> void:
	var f: ScenarioFixture = _wave()
	var raider: int = f.ships_of(&"m1_raider")[0]
	f.world.damage.health[f.world.damage.find_subsystem(raider, &"engines")] = 0.0
	var card: int = -1
	for c: CardView in f.api.cards_of(0):
		card = c.id
	var answer: AnswerHailCommand = AnswerHailCommand.new()
	answer.card = card
	assert_bool(f.send(answer)).is_true()
	var result: int = Scenario.Result.ACTIVE
	for i: int in 8:
		var reply: ReplyCommand = ReplyCommand.new()
		reply.card = card
		reply.option = &"o1"
		assert_bool(f.send(reply)).is_true()
		f.run(2)
		result = f.api.encounter(f.encounter).result
		if result != Scenario.Result.ACTIVE:
			break
		f.run(60 * 25)
	f.run(3)
	assert_int(f.api.encounter(f.encounter).result).is_equal(Scenario.Result.WON)
	assert_bool(_says(f, "npc.surrender")).is_true()
	assert_int(f.world.relation(2, 1)).is_equal(Scenario.Relation.NEUTRAL)


# FT: FT-MIS-004
# #35 A3: the clock ends it as partial, not won; the raiders stay in the run, hostile, and
# keep after the ship once the encounter is over.
func test_the_clock_ends_it_as_partial_and_the_raiders_stay() -> void:
	var f: ScenarioFixture = _wave()
	f.world.damage.health[f.world.damage.hull_row(0)] = 1.0e15
	var raiders: Array[int] = f.ships_of(&"m1_raider")
	for id: int in raiders:
		f.world.damage.health[f.world.damage.hull_row(id)] = 1.0e15
	assert_int(f.run_until_end(60 * 250)).is_equal(Scenario.Result.PARTIAL)
	f.run(60)
	raiders = f.ships_of(&"m1_raider")
	assert_int(raiders.size()).is_equal(2)
	assert_int(f.world.relation(2, f.world.faction_of(0))).is_equal(Scenario.Relation.HOSTILE)
	for id: int in raiders:
		assert_int(f.world.run.status[id]).is_equal(RunTable.Status.IN_PLAY)
		assert_int(f.world.ai.target[id]).is_equal(0)


# FT: FT-ARC-016
func test_relation_enum_matches_the_sim() -> void:
	assert_int(Scenario.Relation.FRIENDLY).is_equal(SimWorld.Relation.FRIENDLY)
	assert_int(Scenario.Relation.NEUTRAL).is_equal(SimWorld.Relation.NEUTRAL)
	assert_int(Scenario.Relation.HOSTILE).is_equal(SimWorld.Relation.HOSTILE)
	assert_int(CardView.State.EXPIRED).is_equal(StoryTable.State.EXPIRED)
	assert_array(Scenario.Result.keys()).is_equal(EncounterTable.Result.keys())


## The wave at a difficulty's enemy strength (Q14).
func _wave_at(strength: float) -> ScenarioFixture:
	var f: ScenarioFixture = ScenarioFixture.make()
	f.strength = strength
	f.begin(&"enemy_wave", SITE)
	f.run(60 * 80)
	return f


# FT: FT-MIS-003, FT-MIS-029
# Q14, owner 2026-10-26: the difficulty preset scales the raiders in the wave, rounded, at
# least one: Easy (0.5) one, Normal two, Hard (1.5) three.
func test_the_wave_scales_with_the_difficulty_strength() -> void:
	assert_int(_wave_at(0.5).ships_of(&"m1_raider").size()).is_equal(1)
	assert_int(_wave_at(1.0).ships_of(&"m1_raider").size()).is_equal(2)
	assert_int(_wave_at(1.5).ships_of(&"m1_raider").size()).is_equal(3)
	assert_int(_wave_at(0.1).ships_of(&"m1_raider").size()).is_equal(1)


# FT: FT-PAIR-004, FT-TST-022
# Review 2 L2: an answered hail is ACCEPTED, not OPEN, and the bot crew still follows it with
# the surrender demand (once the raider's engines are shot up, #35 A4); the demand sets the
# faction's intent for the raider (Q22: it was UNKNOWN) and the roll is logged.
func test_the_bot_crew_demands_surrender_after_the_hail_is_answered() -> void:
	var f: ScenarioFixture = _wave()
	var crew: BotCrew = BotCrew.new(BotProfiles.average(), 0, 5)
	var raider: int = f.ships_of(&"m1_raider")[0]
	f.world.damage.health[f.world.damage.find_subsystem(raider, &"engines")] = 0.0
	var row: int = f.world.knowledge.ensure_contact(1, raider)
	assert_int(f.world.knowledge.intent[row]).is_equal(KnowledgeTable.Intent.UNKNOWN)
	var replied: bool = false
	for i: int in 60 * 40:
		crew.act(f.world)
		f.tick()
		for c: SimCommand in f.world.command_log:
			replied = replied or (c is ReplyCommand and c.accepted)
		if replied:
			break
	assert_bool(replied).is_true()
	assert_int(f.world.knowledge.intent[row]).is_not_equal(KnowledgeTable.Intent.UNKNOWN)
