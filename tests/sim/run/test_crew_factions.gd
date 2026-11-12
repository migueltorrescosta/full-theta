extends GdUnitTestSuite
## The sim knows sides only as factions (B5, #11): RunSetup maps each slot's lobby team to a
## faction once (SessionRules.faction_for), and no crew faction is ever an NPC faction.
## Regression: SimWorld.team_of used to return the slot's team (0 to 5) for a crewed ship and
## the faction for an NPC, so ships 2 to 4 of a race had the same side as the raiders (2),
## freighters (3) and debris (4).


# FT: FT-ARC-018, FT-MIS-032
# In every mode, a full lobby's crewed ships never share a faction with an NPC, and a race
# ship's site copies are keyed by its own faction, never an NPC's.
func test_crew_sides_never_equal_an_npc_faction() -> void:
	for mode: int in SessionRules.MODE_NAMES.size():
		var f: FleetFixture = FleetFixture.make(mode as SessionRules.Mode, SessionRules.MAX_SHIPS)
		var w: SimWorld = f.world
		var label: String = SessionRules.MODE_NAMES[mode]
		assert_object(w).override_failure_message(label).is_not_null()
		var crew: PackedInt32Array = f.ships()
		var copies: int = 0
		var npcs: Array[int] = []
		for npc: int in Factions.NPC:
			npcs.append(
				w.spawn_ship(f.setup.run_def.player_ship, npc, CubePoint.make(0.0, 5000.0, 0.0))
			)
		for id: int in crew:
			var side: int = w.faction_of(id)
			assert_bool(Factions.NPC.has(side)).override_failure_message(label).is_false()
			for npc: int in npcs:
				assert_int(side).override_failure_message(label).is_not_equal(w.faction_of(npc))
			var key: StringName = SiteTable.copy_key(w, &"site", id)
			if key != &"site":
				copies += 1
				assert_str(String(key)).is_equal("site@%d" % side)
		if mode == SessionRules.Mode.RACE:
			assert_int(copies).is_greater(0)


# FT: FT-MIS-032
# A race gives ship i the i-th crew faction: Factions.CREW, then Factions.CREW_SIDES.
func test_race_factions_follow_the_slots() -> void:
	var f: FleetFixture = FleetFixture.make(SessionRules.Mode.RACE, SessionRules.MAX_SHIPS)
	assert_int(f.world.faction_of(0)).is_equal(Factions.CREW)
	for i: int in Factions.CREW_SIDES.size():
		assert_int(f.world.faction_of(i + 1)).is_equal(Factions.CREW_SIDES[i])
