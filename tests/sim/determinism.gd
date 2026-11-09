class_name Determinism
extends RefCounted
## One way to assert "the same seed gives the same run" (FT-SIM-002): `assert_deterministic`
## plays a scenario twice, `assert_replays` compares a second play with a result the test
## already has (so a scenario that a test plays anyway is not played a third time). The
## callable builds and runs the scenario and returns a comparable value, usually a state hash.


## Plays `run` twice and asserts both results are equal.
static func assert_deterministic(suite: GdUnitTestSuite, run: Callable, label: String = "") -> void:
	assert_replays(suite, run.call(), run, label)


## Plays `run` once and asserts its result equals `first`, a result the test already holds.
static func assert_replays(
	suite: GdUnitTestSuite, first: Variant, run: Callable, label: String = ""
) -> void:
	var again: Variant = run.call()
	(
		suite
		. assert_bool(first == again)
		. override_failure_message("%s: the second run differs: %s vs %s" % [label, first, again])
		. is_true()
	)
