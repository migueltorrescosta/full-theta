extends GdUnitTestSuite
## M4 session outcomes by mode (#11, E11, E12): OutcomeSystem.game_outcome() and the
## &"eliminated" and &"game_over" events on lobby-built worlds (FleetFixture). Runs are
## finished by setting a ship's encounter count and closing its run, the director's own
## command (FinishShipCommand); ships are destroyed as damage does.


## Closes the ship's run as the director does once it has played enough encounters.
static func finish(f: FleetFixture, ship: int) -> void:
	f.world.ships.encounters_done[ship] = f.setup.run_def.min_encounters
	var c: FinishShipCommand = FinishShipCommand.new()
	c.ship = ship
	f.world.submit(c)


## Destroys `ship` with a hit from `by` (-1: no ship), as DamageSystem does.
static func destroy(f: FleetFixture, ship: int, by: int = -1) -> void:
	DamageSystem.damage_hull(f.world, ship, INF, by)


static func of_kind(events: Array[SimEvent], kind: StringName) -> Array[SimEvent]:
	return events.filter(func(e: SimEvent) -> bool: return e.kind == kind)


# FT: FT-MIS-011, FT-MIS-012
# Destroying one ship of a co-op fleet takes it out of play with a LOSS and an
# &"eliminated" event (no relaunch in co-op); the other ships stay in play, keep their run
# progress, and the session goes on.
func test_destroyed_ship_leaves_play_and_the_rest_continue() -> void:
	var f: FleetFixture = FleetFixture.make(GameRules.Mode.COOP, 3).with_director()
	f.step(10)
	f.world.ships.encounters_done[0] = 2
	destroy(f, 1)
	var events: Array[SimEvent] = f.step(1)
	assert_int(f.world.ships.status[1]).is_equal(ShipStateTable.Status.DESTROYED)
	assert_int(f.world.ships.ship_outcome[1]).is_equal(ShipStateTable.ShipOutcome.LOSS)
	var gone: Array[SimEvent] = of_kind(events, GameOutcome.EVENT_ELIMINATED)
	assert_int(gone.size()).is_equal(1)
	assert_int(gone[0].ship_id).is_equal(1)
	assert_str(String(gone[0].tag)).is_equal("destroyed")
	# The policy's lives, whatever the purse (w-7v6): the client shows the short purse disabled.
	assert_int(int(gone[0].value)).is_equal(1)
	assert_array(Array(f.api.crew_ships())).is_equal([0, 2])
	assert_int(f.world.ships.encounters_done[0]).is_equal(2)
	f.step(60)
	for ship: int in [0, 2]:
		assert_int(f.world.ships.status[ship]).is_equal(ShipStateTable.Status.IN_PLAY)
	assert_bool(f.outcome().over()).is_false()


# FT: FT-MIS-013
# A co-op session is won when the fleet run's final objective is complete: OBJECTIVE, every
# ship that won a winner, &"game_over" once; a ship lost on the way is no winner.
func test_coop_won_by_the_final_objective() -> void:
	var f: FleetFixture = FleetFixture.make(GameRules.Mode.COOP, 3)
	destroy(f, 2)
	f.step(1)
	assert_bool(f.outcome().over()).is_false()
	finish(f, 0)
	finish(f, 1)
	var events: Array[SimEvent] = f.step(2)
	var out: GameOutcome = f.outcome()
	assert_int(out.reason).is_equal(GameOutcome.Reason.OBJECTIVE)
	assert_array(Array(out.winners)).is_equal([0, 1])
	var over: Array[SimEvent] = of_kind(events, GameOutcome.EVENT_GAME_OVER)
	assert_int(over.size()).is_equal(1)
	assert_int(int(over[0].value)).is_equal(GameOutcome.Reason.OBJECTIVE)
	assert_array(of_kind(f.step(5), GameOutcome.EVENT_GAME_OVER)).is_empty()


# FT: FT-MIS-013, FT-MIS-011
# A co-op fleet that loses every ship has lost the session.
func test_coop_all_lost() -> void:
	var f: FleetFixture = FleetFixture.make(GameRules.Mode.COOP, 2)
	destroy(f, 0)
	f.step(1)
	assert_bool(f.outcome().over()).is_false()
	destroy(f, 1)
	f.step(1)
	assert_int(f.outcome().reason).is_equal(GameOutcome.Reason.ALL_LOST)
	assert_array(Array(f.outcome().winners)).is_empty()


# FT: FT-MIS-032, FT-MIS-014
# A race is won by the first ship to complete the final run objective, not by the others
# that finish later; combat between racers is allowed: their factions are hostile and a
# racer destroyed by another counts a kill for it, while the race goes on.
func test_race_first_to_finish_with_combat() -> void:
	var f: FleetFixture = FleetFixture.make(GameRules.Mode.RACE, 3)
	var w: SimWorld = f.world
	assert_int(w.relation(w.faction_of(0), w.faction_of(1))).is_equal(SimWorld.Relation.HOSTILE)
	destroy(f, 2, 0)
	f.step(1)
	assert_int(w.ships.kills[0]).is_equal(1)
	assert_bool(f.outcome().over()).is_false()
	finish(f, 1)
	var events: Array[SimEvent] = f.step(1)
	finish(f, 0)
	events.append_array(f.step(1))
	var out: GameOutcome = f.outcome()
	assert_int(out.reason).is_equal(GameOutcome.Reason.FIRST_TO_FINISH)
	assert_array(Array(out.winners)).is_equal([1])
	assert_int(w.ships.ship_outcome[0]).is_equal(ShipStateTable.ShipOutcome.WIN)
	assert_int(w.ships.finish_tick[1]).is_less(w.ships.finish_tick[0])
	assert_int(of_kind(events, GameOutcome.EVENT_GAME_OVER).size()).is_equal(1)


# FT: FT-MIS-033, FT-MIS-014
# Last ship standing is won by the last ship not destroyed, and only then.
func test_last_ship_standing() -> void:
	var f: FleetFixture = FleetFixture.make(GameRules.Mode.LAST_STANDING, 3)
	destroy(f, 0, 1)
	f.step(1)
	assert_bool(f.outcome().over()).is_false()
	destroy(f, 2, 1)
	var events: Array[SimEvent] = f.step(1)
	var out: GameOutcome = f.outcome()
	assert_int(out.reason).is_equal(GameOutcome.Reason.LAST_STANDING)
	assert_array(Array(out.winners)).is_equal([1])
	assert_int(f.world.ships.kills[1]).is_equal(2)
	assert_int(of_kind(events, GameOutcome.EVENT_GAME_OVER).size()).is_equal(1)


# FT: FT-MIS-034, FT-MIS-014
# Two teams, one faction each: allies are friendly to each other and hostile to the other
# team. Under LAST_TEAM_STANDING the team with a ship left wins, every ship of it a winner
# (a destroyed ally too), and a kill of an ally is no PvP kill.
func test_teams_last_team_standing() -> void:
	var teams: Array[int] = [0, 1, 0, 1]
	var f: FleetFixture = FleetFixture.make(GameRules.Mode.TEAMS, 4, teams)
	var w: SimWorld = f.world
	assert_int(w.relation(w.faction_of(0), w.faction_of(2))).is_equal(SimWorld.Relation.FRIENDLY)
	assert_int(w.relation(w.faction_of(0), w.faction_of(1))).is_equal(SimWorld.Relation.HOSTILE)
	destroy(f, 2, 0)
	destroy(f, 1, 0)
	f.step(1)
	assert_int(w.ships.kills[0]).is_equal(1)
	assert_bool(f.outcome().over()).is_false()
	destroy(f, 3, 0)
	f.step(1)
	var out: GameOutcome = f.outcome()
	assert_int(out.reason).is_equal(GameOutcome.Reason.LAST_STANDING)
	assert_int(out.winner_faction).is_equal(w.faction_of(0))
	assert_array(Array(out.winners)).is_equal([0, 2])


# FT: FT-MIS-034, FT-MIS-014
# Under the host's FIRST_TO_FINISH rule the first team to complete its run wins, all its
# ships the winners.
func test_teams_first_to_finish() -> void:
	var teams: Array[int] = [0, 1, 0, 1]
	var f: FleetFixture = FleetFixture.make(GameRules.Mode.TEAMS, 4, teams)
	f.rules.team_win = GameRules.TeamWin.FIRST_TO_FINISH
	destroy(f, 0, 1)
	destroy(f, 2, 1)
	f.step(1)
	assert_bool(f.outcome().over()).is_false()
	finish(f, 3)
	f.step(1)
	var out: GameOutcome = f.outcome()
	assert_int(out.reason).is_equal(GameOutcome.Reason.FIRST_TO_FINISH)
	assert_int(out.winner_faction).is_equal(f.world.faction_of(1))
	assert_array(Array(out.winners)).is_equal([1, 3])


# FT: FT-MIS-014
# An abandon in PvP is a forfeit: the ship is eliminated with the tag "forfeit"; in co-op it
# is "abandoned".
func test_abandon_is_a_forfeit_in_pvp() -> void:
	for mode: GameRules.Mode in [GameRules.Mode.RACE, GameRules.Mode.COOP]:
		var f: FleetFixture = FleetFixture.make(mode, 2)
		var c: AbandonShipCommand = AbandonShipCommand.new()
		c.ship_id = 1
		f.world.submit(c)
		var gone: Array[SimEvent] = of_kind(f.step(1), GameOutcome.EVENT_ELIMINATED)
		assert_int(gone.size()).is_equal(1)
		var tag: String = "forfeit" if mode == GameRules.Mode.RACE else "abandoned"
		assert_str(String(gone[0].tag)).is_equal(tag)
	var race: FleetFixture = FleetFixture.make(GameRules.Mode.RACE, 2)
	finish(race, 0)
	race.step(1)
	assert_array(Array(race.outcome().winners)).is_equal([0])
