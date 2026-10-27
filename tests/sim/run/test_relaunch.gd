extends GdUnitTestSuite
## M4 relaunch and start points (#11, owner M4-Q2, 2026-10-28): RelaunchShipCommand under each
## side's RelaunchPolicy, the asymmetric holdout scored by time, and where each side starts
## (RunSetup.start_sites, PROVISIONAL).


static func destroy(f: FleetFixture, ship: int) -> void:
	DamageSystem.damage_hull(f.world, ship, INF, -1)


static func relaunch(f: FleetFixture, ship: int) -> RelaunchShipCommand:
	var c: RelaunchShipCommand = RelaunchShipCommand.new()
	c.ship = ship
	f.world.submit(c)
	return c


static func of_kind(events: Array[SimEvent], kind: StringName) -> Array[SimEvent]:
	return events.filter(func(e: SimEvent) -> bool: return e.kind == kind)


## Every table's rows of ships other than `ship` (knowledge rows are per contact, so all of
## them but those about `ship`).
static func others(w: SimWorld, ship: int) -> Array:
	var out: Array = []
	for t: SimTable in w.tables():
		if t == w.sites or t == w.encounters:
			continue
		for col: Array in t.columns():
			var values: Array = []
			for r: int in t.size():
				if t.ship_ids[r] != ship:
					values.append(col[1][r])
			out.append([col[0], values])
	return out


# FT: FT-MIS-011, FT-MIS-012, FT-MIS-023
# A relaunch resets only that ship's run progress: credits back to the run's purse, no
# encounters done, hull whole, back at its start point; its relaunch count goes up and its
# kills stay. Against a twin world that got no relaunch, every other ship's rows are the
# same, so the others carry on as they were.
func test_relaunch_resets_only_that_ship() -> void:
	var twins: Array[FleetFixture] = []
	for k: int in 2:
		var f: FleetFixture = FleetFixture.make(SessionRules.Mode.HOLDOUT, 3)
		var w: SimWorld = f.world
		var start: Vector3 = w.ship_starts[1]
		f.step(5)
		Economy.add_credits(w, 1, 900)
		Economy.add_credits(w, 0, 300)
		w.run.encounters_done[1] = 2
		w.run.kills[1] = 1
		w.kin.place(1, start.x + 5000.0, start.y, start.z)
		destroy(f, 1)
		var gone: Array[SimEvent] = of_kind(f.step(1), SessionOutcome.EVENT_ELIMINATED)
		assert_int(int(gone[0].value)).is_equal(SessionRules.HOLDOUT_LIVES)
		twins.append(f)
	var f: FleetFixture = twins[0]
	var w: SimWorld = f.world
	var start: Vector3 = w.ship_starts[1]
	relaunch(f, 1)
	var back: Array[SimEvent] = of_kind(f.step(1), SessionOutcome.EVENT_RELAUNCHED)
	twins[1].step(1)
	assert_int(back.size()).is_equal(1)
	assert_int(int(back[0].value)).is_equal(SessionRules.HOLDOUT_LIVES - 1)
	assert_int(w.run.status[1]).is_equal(RunTable.Status.IN_PLAY)
	assert_int(w.run.outcome[1]).is_equal(RunTable.Outcome.NONE)
	assert_int(w.run.encounters_done[1]).is_equal(0)
	assert_int(w.run.relaunches[1]).is_equal(1)
	assert_int(w.run.kills[1]).is_equal(1)
	assert_int(Economy.credits(w, 1)).is_equal(f.setup.run_def.start_credits)
	assert_float(DamageSystem.hull_fraction(w, 1)).is_equal(1.0)
	assert_float(w.kin.relative_to_point(1, start.x, start.y, start.z).length()).is_less(50.0)
	assert_array(others(w, 1)).is_equal(others(twins[1].world, 1))
	assert_int(Economy.credits(w, 0)).is_equal(f.setup.run_def.start_credits + 300)


# FT: FT-MIS-011
# RelaunchShipCommand refuses a ship in play, an AI ship, and a ship whose side has no
# relaunch: co-op's default policy is none (D91).
func test_relaunch_refusals() -> void:
	var f: FleetFixture = FleetFixture.make(SessionRules.Mode.COOP, 2)
	var in_play: RelaunchShipCommand = relaunch(f, 0)
	destroy(f, 1)
	f.step(2)
	var no_policy: RelaunchShipCommand = relaunch(f, 1)
	var no_ship: RelaunchShipCommand = relaunch(f, 99)
	f.step(1)
	assert_bool(in_play.accepted).is_false()
	assert_bool(no_policy.accepted).is_false()
	assert_bool(no_ship.accepted).is_false()
	assert_int(f.world.run.status[1]).is_equal(RunTable.Status.DESTROYED)


# FT: FT-MIS-011, FT-MIS-014
# The holdout (M4-Q2): the small side relaunches without limit; the finite side has
# HOLDOUT_LIVES relaunches. The session ends when the finite side has no ship and no life
# left, scored by the tick its last ship left play; the small side's losses never end it.
func test_holdout_is_asymmetric_and_scored_by_time() -> void:
	var f: FleetFixture = FleetFixture.make(SessionRules.Mode.HOLDOUT, 2)
	var w: SimWorld = f.world
	assert_int(w.team_of(0)).is_equal(SessionRules.HOLDOUT_SMALL_TEAM)
	assert_int(w.team_of(1)).is_equal(SessionRules.HOLDOUT_FINITE_TEAM)
	for i: int in 5:
		destroy(f, 0)
		var gone: Array[SimEvent] = of_kind(f.step(1), SessionOutcome.EVENT_ELIMINATED)
		assert_int(int(gone[0].value)).is_equal(-1)
		relaunch(f, 0)
		f.step(1)
	assert_int(w.run.relaunches[0]).is_equal(5)
	var events: Array[SimEvent] = []
	for life: int in SessionRules.HOLDOUT_LIVES + 1:
		f.step(30)
		destroy(f, 1)
		events = f.step(1)
		var gone: Array[SimEvent] = of_kind(events, SessionOutcome.EVENT_ELIMINATED)
		assert_int(int(gone[0].value)).is_equal(SessionRules.HOLDOUT_LIVES - life)
		if life < SessionRules.HOLDOUT_LIVES:
			assert_bool(f.outcome().over()).is_false()
			relaunch(f, 1)
			f.step(1)
			assert_int(w.run.status[1]).is_equal(RunTable.Status.IN_PLAY)
	var out: SessionOutcome = f.outcome()
	assert_int(out.reason).is_equal(SessionOutcome.Reason.HOLDOUT_OVER)
	assert_int(out.held_ticks).is_equal(w.tick - 1)
	assert_array(Array(out.winners)).is_empty()
	assert_int(of_kind(events, SessionOutcome.EVENT_SESSION_OVER).size()).is_equal(1)
	var spent: RelaunchShipCommand = relaunch(f, 1)
	f.step(1)
	assert_bool(spent.accepted).is_false()


# FT: FT-MIS-023
# Co-op starts every ship at Kestrel Yard, 100 m apart. PvP starts each side at its own
# site, as far apart as the map allows: six free-for-all ships at six different sites, the
# first at the yard; a team's ships share a site, apart from the other team's. Each ship's
# faction knows its start site.
func test_start_sites() -> void:
	var coop: FleetFixture = FleetFixture.make(SessionRules.Mode.COOP, 3)
	for id: int in 3:
		assert_int(coop.world.ship_start_site[id]).is_equal(0)
		assert_vector(coop.world.ship_starts[id]).is_equal(Vector3(id * 100.0, 0.0, 0.0))
	var lss: FleetFixture = FleetFixture.make(SessionRules.Mode.LAST_STANDING, 6)
	var seen: Dictionary[int, bool] = {}
	for id: int in 6:
		var site: int = lss.world.ship_start_site[id]
		seen[site] = true
		assert_bool(lss.world.sites.is_known(site, lss.world.faction_of(id))).is_true()
		assert_int(SiteTable.at_site(lss.world, id)).is_equal(site)
	assert_int(seen.size()).is_equal(6)
	assert_int(lss.world.ship_start_site[0]).is_equal(0)
	var teams: Array[int] = [0, 1, 1, 0]
	var t: FleetFixture = FleetFixture.make(SessionRules.Mode.TEAMS, 4, teams)
	var starts: Dictionary[int, int] = t.world.ship_start_site
	assert_int(starts[0]).is_equal(starts[3])
	assert_int(starts[1]).is_equal(starts[2])
	assert_int(starts[0]).is_not_equal(starts[1])
	# the second side takes the site farthest from the yard
	var far: int = RunSetup._farthest_site(t.world, PackedInt32Array([0]))
	assert_int(starts[1]).is_equal(far)
