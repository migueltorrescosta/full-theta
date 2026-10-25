extends GdUnitTestSuite
## The seam between Science's own-ship scan and Engineering's fault diagnosis (P10): the
## scan names the cause of every unknown fault, and only the scan does.

const CAUSES: Array[StringName] = [&"coolant_leak", &"short", &"software"]


func _world() -> SimWorld:
	var def: ShipDef = TestDefs.corvette().duplicate()
	var subs: Array[SubsystemDef] = []
	for s: SubsystemDef in def.subsystems:
		var copy: SubsystemDef = s.duplicate()
		if copy.id == &"engines":
			copy.fault_causes = CAUSES
		subs.append(copy)
	def.subsystems = subs
	var w: SimWorld = SimWorld.new(4)
	w.science_def = ScienceFixture.science()
	w.spawn_ship(def, 1, 0)
	return w


# FT: FT-SIM-025, FT-ENG-006, FT-PAIR-003
# A fault's cause stays hidden until Science finishes the own-ship scan; the scan reveals
# it without picking it for Engineering (prefill is the Easy toggle's, later).
func test_own_ship_scan_reveals_fault_causes() -> void:
	var w: SimWorld = _world()
	assert_bool(DamageSystem.inflict_fault(w, 0, &"engines", &"short", 1e6)).is_true()
	assert_str(DamageSystem.known_fault_cause(w, 0, &"engines")).is_equal("")
	ScienceFixture.do(w, ScienceSelfScanCommand.new())
	assert_str(DamageSystem.known_fault_cause(w, 0, &"engines")).is_equal("")
	var events: Array[SimEvent] = SimFixture.run(w, int(w.science_def.self_scan_s * 60.0) + 2)
	assert_int(SimFixture.of_kind(events, &"fault_cause_revealed").size()).is_equal(1)
	assert_str(DamageSystem.known_fault_cause(w, 0, &"engines")).is_equal("short")
	var r: int = w.damage.find_subsystem(0, &"engines")
	assert_str(w.damage.fault_pick[r]).is_equal("")
