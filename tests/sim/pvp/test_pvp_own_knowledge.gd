extends GdUnitTestSuite
## FT-PAIR-016 on the sim side (#11, E12): in PvP each ship's pair mechanics use only its own
## faction's knowledge and its own marks. A lobby-built race (FleetFixture) puts the two
## rival ships at different sites; a neutral contact sits by ship 0 only.

const HZ: int = SimWorld.HZ
const NEUTRAL: int = 3


# FT: FT-PAIR-016
# Ship 0's faction detects and names the contact; ship 1's faction does not. Helm's target
# pick (P2, P4) and Science's scan-position mark (P3) work from the ship's own faction's
# knowledge: ship 1 is refused on a contact only its rival knows. The mark is ship 0's own:
# ship 1's mark stays empty.
func test_rivals_use_only_their_own_knowledge_and_marks() -> void:
	var f: FleetFixture = FleetFixture.make(SessionRules.Mode.RACE, 2)
	var w: SimWorld = f.world
	var mine: int = w.faction_of(0)
	var rival: int = w.faction_of(1)
	assert_int(mine).is_not_equal(rival)
	assert_float(f.api.distance(0, 1)).is_greater(100000.0)
	var at: Vector3 = w.ship_starts[0] + Vector3(0.0, 0.0, -3000.0)
	w.set_relation(NEUTRAL, mine, SimWorld.Relation.NEUTRAL)
	w.set_relation(NEUTRAL, rival, SimWorld.Relation.NEUTRAL)
	var contact: int = w.spawn_ship(TestDefs.raider(), NEUTRAL, at)
	f.step(2 * HZ)
	assert_bool(KnowledgeSystem.is_detected(w, mine, contact)).is_true()
	assert_bool(KnowledgeSystem.is_detected(w, rival, contact)).is_false()
	assert_str(KnowledgeSystem.callsign(w, mine, contact)).is_not_empty()
	assert_str(KnowledgeSystem.callsign(w, rival, contact)).is_empty()
	var picks: Array[SelectTargetCommand] = []
	var marks: Array[ScienceMarkCommand] = []
	for ship: int in 2:
		var pick: SelectTargetCommand = SelectTargetCommand.new()
		pick.ship_id = ship
		pick.target_ship = contact
		w.submit(pick)
		picks.append(pick)
		var mark: ScienceMarkCommand = ScienceMarkCommand.new()
		mark.ship_id = ship
		mark.contact = contact
		w.submit(mark)
		marks.append(mark)
	f.step(1)
	assert_bool(picks[0].accepted).is_true()
	assert_bool(picks[1].accepted).is_false()
	assert_bool(marks[0].accepted).is_true()
	assert_bool(marks[1].accepted).is_false()
	assert_int(w.science.mark_contact[0]).is_equal(contact)
	assert_int(w.science.mark_contact[1]).is_equal(-1)
	assert_int(w.helm.target_ship[1]).is_equal(-1)
