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
