extends GdUnitTestSuite
## The shipped scenarios in a fleet (A2, #38 D1): the cards are faction-wide, any ship of the
## crew can answer, dock or demand a surrender, the ship that claims a card is paid, and the
## encounter can finish inside its limit at the hardest setting. Worlds are ScenarioFixture's.

const SITE: StringName = &"vesper_beacon"


func _fleet(scenario: StringName, ships: int, strength: float = 1.0) -> ScenarioFixture:
	var f: ScenarioFixture = ScenarioFixture.make(1, ships)
	f.strength = strength
	f.begin(scenario, SITE)
	f.run(3)
	return f


func _card(f: ScenarioFixture, ship: int, title: String) -> int:
	for c: CardView in f.api.cards_of(ship):
		if c.title_key == title:
			return c.id
	return -1


func _accept(f: ScenarioFixture, ship: int, card: int) -> void:
	var accept: AcceptCardCommand = AcceptCardCommand.new()
	accept.card = card
	assert_bool(f.send_as(ship, accept)).is_true()


# FT: FT-MIS-003, FT-MIS-023
# With 2 and with 6 ships every ship's Comms holds the hail card, and a surrender demanded by
# a ship that is not the first ends the encounter.
func test_any_ship_can_demand_the_surrender() -> void:
	for n: int in [2, 6]:
		var f: ScenarioFixture = _fleet(&"enemy_wave", n)
		var card: int = -1
		for ship: int in n:
			var hails: int = 0
			for c: CardView in f.api.cards_of(ship):
				hails += 1 if c.kind == CardSpec.Kind.HAIL else 0
				card = c.id if c.kind == CardSpec.Kind.HAIL else card
			assert_int(hails).is_equal(1)
		var last: int = n - 1
		var raider: int = f.ships_of(&"m1_raider")[0]
		f.world.damage.health[f.world.damage.find_subsystem(raider, &"engines")] = 0.0
		var answer: AnswerHailCommand = AnswerHailCommand.new()
		answer.card = card
		assert_bool(f.send_as(last, answer)).is_true()
		for i: int in 8:
			var reply: ReplyCommand = ReplyCommand.new()
			reply.card = card
			reply.option = &"o1"
			assert_bool(f.send_as(last, reply)).is_true()
			f.run(2)
			if f.api.encounter(f.encounter).result != Scenario.Result.ACTIVE:
				break
			f.run(60 * 25)
		f.run(3)
		assert_int(f.api.encounter(f.encounter).result).is_equal(Scenario.Result.WON)


# FT: FT-MIS-003, FT-MIS-023
# The first ship is destroyed: another ship still holds the hail and the encounter can finish.
func test_the_wave_goes_on_when_the_first_ship_is_lost() -> void:
	var f: ScenarioFixture = _fleet(&"enemy_wave", 3)
	f.kill(0)
	f.run(3)
	var hails: int = 0
	for c: CardView in f.api.cards_of(2):
		hails += 1 if c.kind == CardSpec.Kind.HAIL else 0
	assert_int(hails).is_equal(1)
	f.run(60 * 46)
	for id: int in f.ships_of(&"m1_raider"):
		f.kill(id)
	assert_int(f.run_until_end(10)).is_equal(Scenario.Result.WON)


# FT: FT-MIS-004, FT-MIS-021
# Both cards are on every ship's board; the ship that accepts the escort is the one paid.
func test_the_ship_that_claims_the_escort_is_paid() -> void:
	var f: ScenarioFixture = _fleet(&"rescue", 3)
	for ship: int in 3:
		assert_int(_card(f, ship, "comms.card.escort")).is_greater_equal(0)
		assert_int(_card(f, ship, "comms.card.salvage")).is_greater_equal(0)
	var before: Array[int] = []
	for ship: int in 3:
		before.append(Economy.credits(f.world, ship))
	_accept(f, 2, _card(f, 2, "comms.card.escort"))
	f.run(60 * 51)
	for id: int in f.ships_of(&"m1_raider"):
		f.kill(id)
	assert_int(f.run_until_end(30)).is_equal(Scenario.Result.WON)
	f.run(3)
	assert_int(Economy.credits(f.world, 2)).is_equal(before[2] + Rescue.ESCORT_REWARD)
	assert_int(Economy.credits(f.world, 0)).is_equal(before[0])
	assert_int(Economy.credits(f.world, 1)).is_equal(before[1])


# FT: FT-MIS-004
# Accepting the escort withdraws the salvage, so only one contract is ever live (R10-3).
func test_accepting_one_card_withdraws_the_other() -> void:
	var f: ScenarioFixture = _fleet(&"rescue", 2)
	var salvage: int = _card(f, 0, "comms.card.salvage")
	_accept(f, 1, _card(f, 1, "comms.card.escort"))
	f.run(3)
	assert_int(f.card_state(salvage)).is_equal(CardView.State.DECLINED)


# FT: FT-MIS-004, FT-MIS-021
# A salvage that timed out in range pays its partial share and changes no standing (D326,
# R17-10); another ship than the first near the freighter counts.
func test_a_timed_out_salvage_pays_in_part() -> void:
	var f: ScenarioFixture = _fleet(&"rescue", 2)
	var credits: int = Economy.credits(f.world, 1)
	_accept(f, 1, _card(f, 1, "comms.card.salvage"))
	f.run(60 * 51)
	var freighter: int = f.ships_of(&"m3_stranded")[0]
	var at: Vector3 = f.world.kin.relative(1, freighter)
	f.world.kin.place(
		1, f.world.kin.px[1] + at.x, f.world.kin.py[1] + at.y, f.world.kin.pz[1] + at.z - 300.0
	)
	for ship: int in 2:
		f.world.damage.health[f.world.damage.hull_row(ship)] = 1.0e15
	for id: int in f.ships_of(&"m1_raider"):
		f.world.damage.health[f.world.damage.hull_row(id)] = 1.0e15
	f.world.damage.health[f.world.damage.hull_row(freighter)] = 1.0e15
	assert_int(f.run_until_end(60 * 320)).is_equal(Scenario.Result.PARTIAL)
	f.run(3)
	assert_int(Economy.credits(f.world, 1)).is_equal(credits + Rescue.SALVAGE_REWARD / 2)
	assert_float(f.world.reputation.value_of(f.world.faction_of(0), 3)).is_equal(0.0)


# FT: FT-MIS-041, FT-MIS-023
# Any ship reaching the yard after the leg wins it, whichever is first; the ship that docks in
# the lane is paid.
func test_a_later_ship_reaching_the_yard_wins_the_leg() -> void:
	var f: ScenarioFixture = _fleet(&"debris_leg", 3)
	var yard: Vector3 = f.world.sites.point3(0)
	f.world.kin.place(1, yard.x, yard.y, yard.z)
	assert_int(f.run_until_end(10)).is_equal(Scenario.Result.WON)


# FT: FT-MIS-041
# The lane card is on every ship's board, and a leg that ends by a flee fails the accepted
# clearance: docking in its lane afterwards pays nothing (A8, R10-2).
func test_a_fled_leg_fails_its_clearance() -> void:
	var f: ScenarioFixture = _fleet(&"debris_leg", 2)
	var card: int = _card(f, 1, "comms.card.lane_run")
	assert_int(card).is_greater_equal(0)
	assert_int(_card(f, 0, "comms.card.lane_run")).is_equal(card)
	_accept(f, 1, card)
	f.api.end_encounter(f.encounter, Scenario.Result.FLED)
	f.run(3)
	assert_int(f.card_state(card)).is_equal(CardView.State.FAILED)
	f.run(60 * 40)
	var credits: int = Economy.credits(f.world, 1)
	var yard: Vector3 = f.world.sites.point3(0)
	f.world.kin.place(1, yard.x + 500.0, yard.y, yard.z)
	f.world.kin.vel[1] = Vector3.ZERO
	var dock: DockCommand = DockCommand.new()
	dock.site_id = 0
	assert_bool(f.send_as(1, dock)).is_true()
	f.run(3)
	assert_int(Economy.credits(f.world, 1)).is_equal(credits)


# FT: FT-MIS-004, FT-MIS-021
# An encounter that ends LOST fails an accepted escort at once, with the failure's standing
# change, instead of leaving it to lapse (A8, R17-12), and the contract flag comes off the
# freighter (R17-13).
func test_a_lost_rescue_fails_the_escort_and_clears_the_flag() -> void:
	var f: ScenarioFixture = _fleet(&"rescue", 2)
	var card: int = _card(f, 0, "comms.card.escort")
	_accept(f, 0, card)
	var freighter: int = f.ships_of(&"m3_stranded")[0]
	var row: int = f.world.knowledge.row_for(f.world.faction_of(0), freighter)
	assert_int(f.world.knowledge.flag[row]).is_equal(KnowledgeTable.Flag.PROTECT)
	f.api.end_encounter(f.encounter, Scenario.Result.LOST)
	f.run(3)
	assert_int(f.card_state(card)).is_equal(CardView.State.FAILED)
	assert_int(f.world.knowledge.flag[row]).is_equal(KnowledgeTable.Flag.NONE)
	assert_float(f.world.reputation.value_of(f.world.faction_of(0), 3)).is_less(0.0)


# FT: FT-MIS-004, FT-MIS-023
# The rescue's raiders are capped so the last one arrives with time to fight, at every
# preset's strength and fleet size (R10-6); enemy_wave stays inside its limit too.
func test_the_raiders_always_fit_the_time_limit() -> void:
	var def: DirectorDef = ScenarioFixture.make().world.run_def.director
	for preset: StringName in [&"easy", &"normal", &"hard"]:
		for ships: int in [1, 3, 6]:
			var strength: float = (
				float(def.strength_per_preset[preset]) * Director.fleet_multiplier(def, ships)
			)
			var count: int = Rescue.raider_count(strength)
			assert_int(count).is_between(1, Rescue.MAX_RAIDERS)
			assert_float(Rescue.last_raider_s(count)).is_less(Rescue.MAX_S - 100.0)
			var wave: int = Scenario.count_for(EnemyWave.COUNT, strength)
			var last: float = (
				EnemyWave.SECOND_AFTER_S + EnemyWave.NEXT_EVERY_S * maxi(wave - 2, 0)
			)
			assert_float(last).is_less(EnemyWave.MAX_S - 40.0)


# FT: FT-MIS-004, FT-MIS-023
# Hard with six ships: the rescue spawns every capped raider and killing them wins it.
func test_a_hard_six_ship_rescue_can_be_won() -> void:
	var def: DirectorDef = ScenarioFixture.make().world.run_def.director
	var strength: float = float(def.strength_per_preset[&"hard"]) * Director.fleet_multiplier(def, 6)
	var f: ScenarioFixture = _fleet(&"rescue", 6, strength)
	var seen: Dictionary[int, bool] = {}
	for i: int in 60 * 290:
		for id: int in f.ships_of(&"m1_raider"):
			seen[id] = true
			f.kill(id)
		f.tick()
		if f.api.encounter(f.encounter).result > Scenario.Result.ACTIVE:
			break
	assert_int(f.api.encounter(f.encounter).result).is_equal(Scenario.Result.WON)
	assert_int(seen.size()).is_equal(Rescue.MAX_RAIDERS)
