extends GdUnitTestSuite
## Session outcome edge cases (A9, A11, R10-7, R09-4, R17-5): mutual kills and draws, ships
## finishing on the same tick, a team that won and was then destroyed, and HOLDOUT's time cap.


func _destroy(f: FleetFixture, ship: int, by: int = -1) -> void:
	DamageSystem.damage_hull(f.world, ship, INF, by)


## Closes the ship's run as the director does once it has played enough encounters.
func _finish(f: FleetFixture, ship: int) -> void:
	f.world.run.encounters_done[ship] = f.setup.run_def.min_encounters
	var c: CloseRunCommand = CloseRunCommand.new()
	c.ship = ship
	f.world.submit(c)


# FT: FT-MIS-033, FT-MIS-014
# Every remaining ship destroyed on the same tick is a draw: ALL_LOST, nobody named a winner.
func test_a_mutual_kill_is_a_draw() -> void:
	var f: FleetFixture = FleetFixture.make(SessionRules.Mode.LAST_STANDING, 2)
	_destroy(f, 0, 1)
	_destroy(f, 1, 0)
	f.step(1)
	var out: SessionOutcome = f.outcome()
	assert_int(out.reason).is_equal(SessionOutcome.Reason.ALL_LOST)
	assert_array(Array(out.winners)).is_empty()
	assert_int(f.world.run.kills[0]).is_equal(1)
	assert_int(f.world.run.kills[1]).is_equal(1)


# FT: FT-MIS-034
# Two teams wiped out on the same tick: also ALL_LOST.
func test_two_teams_destroyed_together_is_a_draw() -> void:
	var teams: Array[int] = [0, 1]
	var f: FleetFixture = FleetFixture.make(SessionRules.Mode.TEAMS, 2, teams)
	_destroy(f, 0, 1)
	_destroy(f, 1, 0)
	f.step(1)
	assert_int(f.outcome().reason).is_equal(SessionOutcome.Reason.ALL_LOST)


# FT: FT-MIS-032
# Two racers closing their runs on the same tick both finish first: both are winners.
func test_a_same_tick_finish_is_shared() -> void:
	var f: FleetFixture = FleetFixture.make(SessionRules.Mode.RACE, 3)
	_finish(f, 0)
	_finish(f, 2)
	f.step(2)
	var out: SessionOutcome = f.outcome()
	assert_int(out.reason).is_equal(SessionOutcome.Reason.FIRST_TO_FINISH)
	assert_array(Array(out.winners)).is_equal([0, 2])


# FT: FT-MIS-034
# A team that completed its run and was then destroyed does not stand: the team that destroyed
# it is the last one standing (R17-5), not the finished-then-dead team by the first-to-finish
# fallback.
func test_a_team_that_won_and_was_destroyed_does_not_stand() -> void:
	var teams: Array[int] = [0, 1, 0, 1]
	var f: FleetFixture = FleetFixture.make(SessionRules.Mode.TEAMS, 4, teams)
	_finish(f, 0)
	_finish(f, 2)
	f.step(2)
	assert_int(f.world.run.outcome[0]).is_equal(RunTable.Outcome.WIN)
	assert_bool(f.outcome().over()).is_false()
	_destroy(f, 0, 1)
	_destroy(f, 2, 3)
	f.step(1)
	var out: SessionOutcome = f.outcome()
	assert_int(out.reason).is_equal(SessionOutcome.Reason.LAST_STANDING)
	assert_int(out.team).is_equal(1)
	assert_array(Array(out.winners)).is_equal([1, 3])


# FT: FT-MIS-011
# A ship that won and was then destroyed still emits &"eliminated" (R17-5), once, tagged destroyed;
# its win stays.
func test_a_ship_that_won_and_was_destroyed_is_eliminated() -> void:
	var f: FleetFixture = FleetFixture.make(SessionRules.Mode.COOP, 2)
	_finish(f, 0)
	f.step(2)
	assert_int(f.world.run.outcome[0]).is_equal(RunTable.Outcome.WIN)
	_destroy(f, 0)
	var gone: Array[SimEvent] = f.step(2).filter(
		func(e: SimEvent) -> bool: return e.kind == SessionOutcome.EVENT_ELIMINATED
	)
	assert_int(gone.size()).is_equal(1)
	assert_int(gone[0].ship_id).is_equal(0)
	assert_str(str(gone[0].tag)).is_equal("destroyed")
	assert_int(f.world.run.outcome[0]).is_equal(RunTable.Outcome.WIN)


func _holdout() -> FleetFixture:
	var teams: Array[int] = [0, 1]
	return FleetFixture.make(SessionRules.Mode.HOLDOUT, 2, teams)


# FT: FT-MIS-014, FT-MIS-011
# HOLDOUT is capped (D264, A11): while the finite side holds the session runs, and when
# HOLDOUT_CAP_S have passed with a ship of it in play, it wins.
func test_the_holdout_side_wins_when_the_timer_runs_out() -> void:
	var f: FleetFixture = _holdout()
	var cap: int = ceili(SessionRules.HOLDOUT_CAP_S * SimWorld.HZ)
	f.world.tick = cap - 3
	f.step(1)
	assert_bool(f.outcome().over()).is_false()
	f.step(3)
	var out: SessionOutcome = f.outcome()
	assert_int(out.reason).is_equal(SessionOutcome.Reason.HOLDOUT_OVER)
	assert_int(out.team).is_equal(SessionRules.HOLDOUT_FINITE_TEAM)
	assert_array(Array(out.winners)).is_equal([1])
	assert_int(out.held_ticks).is_equal(cap)


# FT: FT-MIS-014
# The finite side's last ship out with lives left does not hold: at the cap the session is
# over with no winner and its score the tick it went out.
func test_a_holdout_side_with_no_ship_in_play_at_the_cap_has_not_held() -> void:
	var f: FleetFixture = _holdout()
	f.world.tick = 100
	_destroy(f, 1, 0)
	f.step(1)
	assert_bool(f.outcome().over()).is_false()
	f.world.tick = ceili(SessionRules.HOLDOUT_CAP_S * SimWorld.HZ)
	var out: SessionOutcome = f.outcome()
	assert_int(out.reason).is_equal(SessionOutcome.Reason.HOLDOUT_OVER)
	assert_array(Array(out.winners)).is_empty()
	assert_int(out.held_ticks).is_equal(f.world.run.finish_tick[1])
