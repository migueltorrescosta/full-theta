extends GdUnitTestSuite
## E01: what each scan level reveals per faction in KNOW (FT-SCI-002, D28) and the
## weak-point and resistance reveals the damage side reads (FT-SIM-022, FT-SIM-023).

const ME: int = 0
const FOE: int = 1


func _set_conf(w: SimWorld, faction: int, conf: float) -> void:
	w.knowledge.scan_conf[w.knowledge.row_for(faction, FOE)] = conf


# FT: FT-SCI-002
# Each part of the card appears at its own threshold, in order, and the level counts them.
func test_card_parts_appear_at_their_thresholds() -> void:
	var w: SimWorld = ScienceFixture.world()
	var def: ScienceDef = w.science_def
	assert_int(ScienceKnowledge.level(w, 1, FOE)).is_equal(0)
	var steps: Array[float] = [
		def.reveal_class,
		def.reveal_identity,
		def.reveal_intent,
		def.reveal_hack,
		def.reveal_weak_points,
		def.reveal_resistances,
	]
	steps.sort()
	var last: int = 0
	for conf: float in steps:
		_set_conf(w, 1, conf)
		var level: int = ScienceKnowledge.level(w, 1, FOE)
		assert_int(level).is_greater(last)
		last = level
	assert_int(last).is_equal(6)
	_set_conf(w, 1, def.reveal_class)
	assert_bool(ScienceKnowledge.revealed(w, 1, FOE, ScienceKnowledge.CLASS)).is_true()
	assert_bool(ScienceKnowledge.revealed(w, 1, FOE, ScienceKnowledge.WEAK_POINTS)).is_false()


# FT: FT-SCI-002
# The identity threshold identifies the contact; knowledge is per faction.
func test_identity_and_factions() -> void:
	# Beyond the corvette's identify range (8 km), so only a scan identifies the raider.
	var w: SimWorld = ScienceFixture.world(15000.0)
	assert_bool(KnowledgeSystem.is_identified(w, 1, FOE)).is_false()
	ScienceFixture.scan_exactly(w)
	assert_bool(KnowledgeSystem.is_identified(w, 1, FOE)).is_true()
	assert_float(ScienceKnowledge.confidence(w, 2, ME)).is_equal(0.0)
	assert_bool(ScienceKnowledge.revealed(w, 2, ME, ScienceKnowledge.CLASS)).is_false()
	# A faction knows its own ships fully.
	assert_bool(ScienceKnowledge.revealed(w, 1, ME, ScienceKnowledge.RESISTANCES)).is_true()


# FT: FT-SIM-022, FT-SIM-023, FT-PAIR-003
# P7: weak points and resistances are withheld until the scan confidence reaches their
# thresholds, then listed; a lower later scan never lowers the confidence.
func test_weak_points_and_resistances_revealed_by_scan() -> void:
	var w: SimWorld = ScienceFixture.world(6000.0, true, ScienceFixture.weak_raider())
	var def: ScienceDef = w.science_def
	assert_array(ScienceKnowledge.weak_points(w, 1, FOE)).is_empty()
	assert_dict(ScienceKnowledge.resistances(w, 1, FOE)).is_empty()
	_set_conf(w, 1, def.reveal_weak_points)
	assert_bool(ScienceKnowledge.weak_points_known(w, 1, FOE)).is_true()
	assert_bool(ScienceKnowledge.resistances_known(w, 1, FOE)).is_false()
	assert_array(ScienceKnowledge.weak_points(w, 1, FOE)).is_equal(PackedInt32Array([0]))
	_set_conf(w, 1, def.reveal_resistances)
	assert_float(ScienceKnowledge.resistances(w, 1, FOE)[&"kinetic"]).is_equal(0.5)
	# The faction that did not scan learns nothing.
	assert_bool(ScienceKnowledge.weak_points_known(w, 2, ME)).is_false()
	# A worse scan keeps the best confidence.
	ScienceKnowledge.record(w, 1, FOE, 0.1)
	assert_float(ScienceKnowledge.confidence(w, 1, FOE)).is_equal(def.reveal_resistances)


# FT: FT-SCI-001
# The radar icon size input: detection confidence falls with range and is 0 undetected.
func test_detection_confidence_falls_with_range() -> void:
	var near: float = ScienceKnowledge.detection_confidence(ScienceFixture.world(3000.0), 1, FOE)
	var far: float = ScienceKnowledge.detection_confidence(ScienceFixture.world(15000.0), 1, FOE)
	assert_float(near).is_greater(far)
	assert_float(far).is_greater(0.0)
	(
		assert_float(ScienceKnowledge.detection_confidence(ScienceFixture.world(25000.0), 1, FOE))
		. is_equal(0.0)
	)
