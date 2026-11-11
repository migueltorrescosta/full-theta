extends GdUnitTestSuite
## NetFleet maps the sim's SessionOutcome.winner_faction back to the lobby team for the
## `session_over` wire field (B5, #11): the inverse of SessionRules.faction_for, so the wire
## still carries teams.


static func _slots(teams: Array[int]) -> Array[ShipSlot]:
	var out: Array[ShipSlot] = []
	for i: int in teams.size():
		out.append(ShipSlot.of("Ship %d" % (i + 1), teams[i]))
	return out


# FT: FT-MIS-013
# Co-op: one faction, team 0; no winner faction is no team.
func test_coop_maps_to_team_zero() -> void:
	var r: SessionRules = SessionRules.new()
	var slots: Array[ShipSlot] = _slots([0, 0])
	assert_int(NetFleet.team_for_faction(slots, r, Factions.CREW)).is_equal(0)
	assert_int(NetFleet.team_for_faction(slots, r, -1)).is_equal(-1)


# FT: FT-MIS-034
# Teams and holdout: each team's faction maps back to that team.
func test_teams_map_each_faction_to_its_team() -> void:
	var r: SessionRules = SessionRules.of_mode(SessionRules.Mode.TEAMS)
	var slots: Array[ShipSlot] = _slots([0, 1, 1])
	assert_int(NetFleet.team_for_faction(slots, r, r.faction_for(0, 0))).is_equal(0)
	assert_int(NetFleet.team_for_faction(slots, r, r.faction_for(0, 1))).is_equal(1)
	var h: SessionRules = SessionRules.of_mode(SessionRules.Mode.HOLDOUT)
	var finite: int = NetFleet.team_for_faction(slots, h, h.holdout_finite_faction())
	assert_int(finite).is_equal(SessionRules.HOLDOUT_FINITE_TEAM)


# FT: FT-MIS-032, FT-MIS-033
# PvP free-for-all: ship i's faction maps to its own side; an NPC faction (2 to 4, once equal
# to a racer's team id) maps to no team.
func test_free_for_all_maps_each_ship_and_no_npc() -> void:
	var r: SessionRules = SessionRules.of_mode(SessionRules.Mode.RACE)
	var slots: Array[ShipSlot] = _slots([0, 1, 2, 3, 4, 5])
	for i: int in slots.size():
		assert_int(NetFleet.team_for_faction(slots, r, r.faction_for(i, i))).is_equal(i)
	for npc: int in Factions.NPC:
		assert_int(NetFleet.team_for_faction(slots, r, npc)).is_equal(-1)
