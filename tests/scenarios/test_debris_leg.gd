extends GdUnitTestSuite
## The debris leg (FT-MIS-041, D234, FT-MIS-026): the run puts the map leg's debris on the
## route, Weapons destroys a piece with the existing mount, and crossing to the yard ends the
## encounter; impulse flight between two named sites reaches them.


# FT: FT-MIS-041
func test_the_leg_has_debris_on_the_route_and_weapons_destroys_it() -> void:
	var f: ScenarioFixture = ScenarioFixture.make()
	f.begin(&"debris_leg", &"vesper_beacon")
	f.run(3)
	var pieces: Array[int] = f.ships_of(&"m3_debris")
	assert_int(pieces.size()).is_equal(6)
	var from: Vector3 = f.world.sites.point3(f.site)
	var yard: Vector3 = f.world.sites.point3(0)
	for id: int in pieces:
		# On the route: within the lateral spread of the line between the sites.
		var rel: Vector3 = f.world.kin.relative_to_point(id, from.x, from.y, from.z)
		var line: Vector3 = yard - from
		var along: float = -rel.dot(line.normalized())
		assert_float(along).is_between(0.0, line.length())
		assert_float((-rel - line.normalized() * along).length()).is_less(200.0)
	# Weapons shoots the nearest piece: the ship waits 3 km short of it with the bow on it.
	var target: int = pieces[0]
	f.world.kin.place(
		0, f.world.kin.px[target] - 3000.0, f.world.kin.py[target], f.world.kin.pz[target]
	)
	f.world.kin.rot[0] = Quaternion(Basis.looking_at(Vector3(1, 0, 0), Vector3.UP))
	f.run(2)
	assert_bool(KnowledgeSystem.is_detected(f.world, f.world.faction_of(0), target)).is_true()
	var crew: ScriptedCrew = ScriptedCrew.new(0, target)
	for i: int in 1800:
		crew.act(f.world)
		f.tick()
		if f.world.run.status[target] != RunTable.Status.IN_PLAY:
			break
	assert_int(f.world.run.status[target]).is_not_equal(RunTable.Status.IN_PLAY)


# FT: FT-MIS-041
func test_arriving_at_the_yard_ends_the_leg() -> void:
	var f: ScenarioFixture = ScenarioFixture.make()
	f.begin(&"debris_leg", &"vesper_beacon")
	f.run(3)
	var yard: Vector3 = f.world.sites.point3(0)
	f.world.kin.place(0, yard.x, yard.y, yard.z)
	assert_int(f.run_until_end(10)).is_equal(Scenario.Result.WON)


# FT: FT-MIS-026
# Impulse flight between two named sites in the one cube: the yard to Vesper Beacon.
func test_impulse_flight_reaches_the_next_site() -> void:
	var f: ScenarioFixture = ScenarioFixture.make()
	var vesper: int = f.world.sites.open(f.world, &"vesper_beacon")
	var select: SelectTargetCommand = SelectTargetCommand.new()
	select.site_id = vesper
	assert_bool(f.send(select)).is_true()
	var helm: HelmInputCommand = HelmInputCommand.new()
	helm.face = true
	helm.approach = true
	assert_bool(f.send(helm)).is_true()
	for i: int in 60 * 900:
		f.world.step()
		if SiteTable.at_site(f.world, 0) == vesper:
			break
	assert_int(SiteTable.at_site(f.world, 0)).is_equal(vesper)
	assert_float(absf(f.world.kin.px[0])).is_less(f.world.kin.period / 2.0)


# FT: FT-MIS-041
# Review 2 M5: a ship still at the yard when the leg starts (the arrival timeout) has crossed
# nothing, so the encounter doesn't end at once; it ends when the ship has left and come back.
func test_a_ship_at_the_yard_has_not_crossed_the_leg() -> void:
	var f: ScenarioFixture = ScenarioFixture.make()
	f.begin(&"debris_leg", &"vesper_beacon")
	var yard: Vector3 = f.world.sites.point3(0)
	f.world.kin.place(0, yard.x, yard.y, yard.z)
	f.run(60 * 5)
	assert_int(f.api.encounter(f.encounter).result).is_equal(Scenario.Result.ACTIVE)
	assert_int(f.ships_of(&"m3_debris").size()).is_equal(6)
	var away: Vector3 = f.world.sites.point3(f.site)
	f.world.kin.place(0, away.x, away.y, away.z)
	f.run(5)
	f.world.kin.place(0, yard.x, yard.y, yard.z)
	assert_int(f.run_until_end(10)).is_equal(Scenario.Result.WON)


func _accepted_leg() -> Array:
	var f: ScenarioFixture = ScenarioFixture.make()
	f.begin(&"debris_leg", &"vesper_beacon")
	f.run(3)
	var card: int = f.api.cards_of(0)[0].id
	var accept: AcceptCardCommand = AcceptCardCommand.new()
	accept.card = card
	assert_bool(f.send(accept)).is_true()
	return [f, card]


func _dock_at_yard(f: ScenarioFixture) -> void:
	var yard: Vector3 = f.world.sites.point3(0)
	f.world.kin.place(0, yard.x, yard.y, yard.z)
	f.world.kin.vel[0] = Vector3.ZERO
	var dock: DockCommand = DockCommand.new()
	dock.site_id = 0
	assert_bool(f.send(dock)).is_true()
	f.run(2)


# FT: FT-PAIR-001, FT-MIS-019
# P5: the traffic-control offer is a docking clearance for the yard. Accepted, it opens an
# approach lane (30 s later, 540 s long); docking inside it pays the fee and keeps standing.
func test_a_cleared_dock_at_the_yard_pays_the_fee() -> void:
	var legs: Array = _accepted_leg()
	var f: ScenarioFixture = legs[0]
	var card: int = legs[1]
	var window: Array[int] = StoryRules.lane_window(f.world, card)
	var credits: int = Economy.credits(f.world, 0)
	f.run(window[0] - f.world.tick + 1)
	_dock_at_yard(f)
	assert_int(f.card_state(card)).is_equal(CardView.State.DONE)
	assert_int(Economy.credits(f.world, 0)).is_equal(credits + DebrisLeg.FEE)
	assert_float(f.world.reputation.value_of(f.world.faction_of(0), Factions.CIVIL)).is_equal(0.0)


# FT: FT-PAIR-001, FT-MIS-019
# Rushing in before the lane opens fails the card and costs standing, and pays nothing.
func test_an_uncleared_dock_at_the_yard_costs_standing() -> void:
	var legs: Array = _accepted_leg()
	var f: ScenarioFixture = legs[0]
	var card: int = legs[1]
	var credits: int = Economy.credits(f.world, 0)
	_dock_at_yard(f)
	assert_int(f.card_state(card)).is_equal(CardView.State.FAILED)
	assert_int(Economy.credits(f.world, 0)).is_equal(credits)
	assert_float(f.world.reputation.value_of(f.world.faction_of(0), Factions.CIVIL)).is_less(0.0)


# FT: FT-MIS-041, FT-MIS-021
# #35 A3: when the time runs out before the crossing the leg ends as partial; the P5
# clearance pays only on a cleared dock, so an accepted clearance that never docked lapses
# unpaid.
func test_running_out_of_time_ends_the_leg_as_partial_and_the_clearance_lapses() -> void:
	var legs: Array = _accepted_leg()
	var f: ScenarioFixture = legs[0]
	var card: int = legs[1]
	f.world.damage.health[f.world.damage.hull_row(0)] = 1.0e15
	var credits: int = Economy.credits(f.world, 0)
	assert_int(f.run_until_end(60 * 610)).is_equal(Scenario.Result.PARTIAL)
	f.run(3)
	assert_int(f.card_state(card)).is_not_equal(CardView.State.DONE)
	assert_int(Economy.credits(f.world, 0)).is_equal(credits)
