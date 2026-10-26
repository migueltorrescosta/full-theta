extends GdUnitTestSuite
## The seam between Relay's probes and Science (P13): a probe bubble gives its faction a
## KNOW row for a contact beyond sensor range, and Science's noise and scans read the same
## coverage.

const BLUE: int = 1
const RED: int = 2
const ME: int = 0
const FOE: int = 1


# The raider sits beyond the corvette's 20 km sensor range, 22 km away.
func _world() -> SimWorld:
	var w: SimWorld = SimWorld.new(3)
	w.science_def = ScienceFixture.science()
	w.spawn_ship(TestDefs.corvette(), BLUE)
	w.spawn_ship(TestDefs.raider(), RED, Vector3(0, 0, -22000))
	return w


# FT: FT-SCI-005, FT-PAIR-003
# A deployed probe over the contact detects it for the faction (a KNOW row), Science's
# coverage answers true without any Callable set, and the scan noise drops.
func test_probe_bubble_detects_and_lowers_noise() -> void:
	var w: SimWorld = _world()
	SimFixture.run(w, 2)
	assert_bool(KnowledgeSystem.is_detected(w, BLUE, FOE)).is_false()
	assert_bool(ScienceSystem.probe_covered(w, ME, FOE)).is_false()
	var far_noise: float = ScienceSystem.contact_noise(w, ME, FOE)
	var launch: LaunchProbeCommand = LaunchProbeCommand.new()
	launch.ship_id = ME
	launch.z = -21000.0
	w.submit(launch)
	# 21 km at 500 m/s is 42 s.
	SimFixture.run(w, 60 * 43)
	assert_int(w.probes.deployed[0]).is_equal(1)
	assert_bool(ScienceSystem.probe_covered(w, ME, FOE)).is_true()
	assert_bool(KnowledgeSystem.is_detected(w, BLUE, FOE)).is_true()
	assert_float(ScienceSystem.contact_noise(w, ME, FOE)).is_less(far_noise)
	# The other side's probes, and none at all, cover nothing.
	assert_bool(ProbeSystem.coverage_at(w, RED, Vector3(0, 0, -22000))).is_false()
