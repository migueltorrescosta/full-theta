class_name PairCases
extends RefCounted
## The pair tests' table (spec §7.4, FT-PAIR-015): for each pair except P12, its scenario's
## harness, the two crew scripts and the metrics co-op must beat solo on. The gain each needs is
## PairHarness.min_gain(id). test_pair_gains.gd runs every row; P12 has no row (it asserts that
## purchases reach COND, test_p12_engineering_comms.gd).

const IDS: Array[String] = [
	"p1", "p2", "p3", "p4", "p5", "p6", "p7", "p8", "p9", "p10", "p11", "p13", "p14", "p15"
]
const LOWER: PairHarness.Better = PairHarness.Better.LOWER
const HIGHER: PairHarness.Better = PairHarness.Better.HIGHER


## One row: {harness: PairHarness, coop: Callable, solo: Callable, better: Dictionary}, plus
## the P8 first-shot track qualities {coop_shots, solo_shots} that its crews fill in.
static func of(id: String) -> Dictionary:
	match id:
		"p1":
			# Heat past the threshold faults, and tight shield focus orders hull damage:
			# tests/sim/power/test_power.gd, tests/sim/shields/test_shields.gd.
			return _row(
				P1Scenario.harness(),
				P1Scenario.coop,
				P1Scenario.solo,
				{"time": LOWER, "hull_lost": LOWER}
			)
		"p2":
			# The arc rules are in tests/sim/combat/test_weapons.gd.
			return _row(P2Scenario.harness(), P2Scenario.coop, P2Scenario.solo, {"time": LOWER})
		"p3":
			return _row(
				P3Scenario.harness(),
				P3Scenario.coop_crew(),
				P3Scenario.solo_crew(),
				{"noise": LOWER, "scan_s": LOWER}
			)
		"p4":
			return _row(
				P4Scenario.harness(),
				P4Scenario.coop,
				P4Scenario.solo,
				{"hull_lost": LOWER, "propellant": LOWER}
			)
		"p5":
			return _row(
				P5Scenario.harness(), P5Scenario.coop_crew(), P5Scenario.solo, {"rep_lost": LOWER}
			)
		"p6":
			# Pips and the overheat lock: tests/sim/power/test_power.gd,
			# tests/sim/combat/test_ordnance.gd.
			return _row(P6Scenario.harness(), P6Scenario.coop, P6Scenario.solo, {"time": LOWER})
		"p7":
			return _row(
				P7Scenario.harness(), P7Scenario.coop_crew(), P7Scenario.solo, {"time": LOWER}
			)
		"p8":
			var coop_shots: Array[float] = []
			var solo_shots: Array[float] = []
			var row: Dictionary = _row(
				StrikeScenario.harness(),
				StrikeScenario.crew(true, false, true, coop_shots),
				StrikeScenario.crew(false, false, true, solo_shots),
				{"time": LOWER, "first_hit_s": LOWER}
			)
			row["coop_shots"] = coop_shots
			row["solo_shots"] = solo_shots
			return row
		"p9":
			return _row(
				P9Scenario.harness(),
				P9Scenario.coop,
				P9Scenario.solo,
				{"rep_lost": LOWER, "reward": HIGHER}
			)
		"p10":
			return _row(P10Scenario.harness(), P10Scenario.coop, P10Scenario.solo, {"time": LOWER})
		"p11":
			return _row(
				P11Scenario.harness(),
				P11Scenario.coop,
				P11Scenario.solo,
				{"damage": LOWER, "repair_time": LOWER}
			)
		"p13":
			return _row(
				P13Scenario.harness(),
				P13Scenario.coop_crew(),
				P13Scenario.solo_crew(),
				{"time": LOWER, "trace_peak": LOWER}
			)
		"p14":
			return _row(
				P14Scenario.harness(),
				P14Scenario.coop_crew(),
				P14Scenario.solo,
				{"reputation": HIGHER, "unlocked": HIGHER}
			)
		"p15":
			return _row(
				P15Scenario.harness(), P15Scenario.coop, P15Scenario.solo, {"seconds": LOWER}
			)
	return {}


static func _row(
	harness: PairHarness, coop: Callable, solo: Callable, better: Dictionary
) -> Dictionary:
	return {"harness": harness, "coop": coop, "solo": solo, "better": better}
