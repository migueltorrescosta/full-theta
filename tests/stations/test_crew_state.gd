extends GdUnitTestSuite
## CrewState: the client model built from Welcome, the Catalogue and events.

const NOW: int = StationFixture.NOW_MS


func _crew() -> CrewState:
	return StationFixture.context("tactical").crew


func _ev(type: String, payload: Dictionary) -> Dictionary:
	return {"seq": 1, "tick": 0, "type": type, "payload": payload}


# FT: FT-STN-008
func test_alert_events_set_the_level_and_crew_rule() -> void:
	var crew: CrewState = _crew()
	assert_bool(crew.is_crew()).is_true()
	crew.handle_event(_ev("alert", {"ship": 0, "level": 2, "by": "Bo"}), NOW)
	assert_int(crew.alert).is_equal(CrewState.ALERT_RED)
	assert_str(crew.alert_by).is_equal("Bo")
	# Another ship's alert is not ours.
	crew.handle_event(_ev("alert", {"ship": 5, "level": 1, "by": "X"}), NOW)
	assert_int(crew.alert).is_equal(CrewState.ALERT_RED)
	assert_bool(StationFixture.context("viewer").crew.is_crew()).is_false()
	assert_bool(StationFixture.context("captain").crew.is_crew()).is_false()


# FT: FT-SPA-012, FT-SPA-015
func test_marks_list_replaces_and_drops_a_deleted_selection() -> void:
	var crew: CrewState = _crew()
	assert_int(crew.marks.size()).is_equal(1)
	assert_str(crew.mark_in_slot(StationFixture.BRAVO_SLOT)["name"]).is_equal("Bravo")
	crew.select("mark", StationFixture.BRAVO_SLOT)
	var marks: Array = []
	for slot: int in [0, 2]:
		marks.append({"slot": slot, "name": "", "contact": 2, "site": 0, "x": 0, "y": 0, "z": 0})
	crew.handle_event(_ev("marks", {"ship": 0, "marks": marks}), NOW)
	(
		assert_array(crew.marks.map(func(m: Dictionary) -> String: return m["name"]))
		. is_equal(["Alpha", "Charlie"])
	)
	assert_dict(crew.selection).is_empty()


# FT: FT-SPA-016, FT-SPA-031
func test_pings_pulse_three_seconds_and_copies_are_silent() -> void:
	var crew: CrewState = _crew()
	var chimes: Array = []
	crew.pinged.connect(func(p: Dictionary) -> void: chimes.append(p))
	var p: Dictionary = {"ship": 0, "kind": "contact", "id": 2, "site": 0, "x": 0, "y": 0}
	p.merge({"z": 0, "by": "Ana", "copy": false})
	crew.handle_event(_ev("ping", p), NOW)
	assert_float(crew.pulse("contact", 2, NOW)).is_equal(1.0)
	assert_float(crew.pulse("contact", 2, NOW + 1500)).is_equal_approx(0.5, 0.01)
	var copy: Dictionary = p.duplicate()
	copy["copy"] = true
	copy["by"] = "Bo"
	crew.handle_event(_ev("ping", copy), NOW + 100)
	assert_int(chimes.size()).is_equal(1)
	assert_array(crew.pings[0]["copies"]).is_equal(["Bo"])
	assert_float(crew.pulse("contact", 2, NOW + CrewState.PING_MS)).is_equal(0.0)
	assert_bool(crew.select_pinged(NOW + 200)).is_true()
	assert_dict(crew.selection).is_equal({"kind": "contact", "id": 2})
	assert_dict(crew.last_ping(NOW + CrewState.PING_MS + 1)).is_empty()


# FT: FT-STN-009
func test_cycle_wraps_through_the_given_order() -> void:
	var crew: CrewState = _crew()
	crew.cycle("contact", [3, 2])
	assert_int(crew.selection["id"]).is_equal(3)
	crew.cycle("contact", [3, 2])
	assert_int(crew.selection["id"]).is_equal(2)
	crew.cycle("contact", [3, 2])
	assert_int(crew.selection["id"]).is_equal(3)


func test_claims_pause_votes_and_run_reset() -> void:
	var crew: CrewState = _crew()
	crew.handle_event(_ev("claim", {"ship": 0, "item": "flight", "session": 7, "name": "Ana"}), NOW)
	assert_str(crew.claimer("flight")).is_equal("Ana")
	crew.handle_event(_ev("claim", {"ship": 0, "item": "flight", "session": -1, "name": ""}), NOW)
	assert_str(crew.claimer("flight")).is_equal("")
	crew.handle_event(_ev("pause", {"ship": 0, "uncovered": ["helm"], "crew": 2}), NOW)
	crew.handle_event(_ev("abandon_votes", {"ship": 0, "voters": ["Ana"], "needed": 2}), NOW)
	assert_bool(crew.paused.has(0)).is_true()
	assert_int(crew.votes[0]["needed"]).is_equal(2)
	crew.handle_event(_ev("resume", {"tick": 9}), NOW)
	assert_bool(crew.paused.is_empty() and crew.votes.is_empty()).is_true()
	# The server puts a finished ship back in the lobby: the run's state clears.
	crew.select("contact", 2)
	var lobby: Dictionary = crew.lobby[0].duplicate()
	lobby["started"] = false
	crew.handle_event(_ev("lobby", lobby), NOW)
	assert_bool(crew.marks.is_empty()).is_true()
	assert_dict(crew.selection).is_empty()
	assert_bool(crew.is_started()).is_false()


func test_refusals_become_toasts_and_mission_time_counts_from_start() -> void:
	var crew: CrewState = _crew()
	var toasts: Array = []
	crew.toast.connect(func(key: String, _a: Dictionary) -> void: toasts.append(key))
	var r: Dictionary = {"request": 0, "reason": "marks_full"}
	crew.handle_event(_ev("request_rejected", r), NOW)
	crew.handle_event(_ev("picked", {"ship": 0, "entry": "helm", "reason": "breaks_coverage"}), NOW)
	assert_array(toasts).is_equal(["toast.marks_full", "toast.breaks_coverage"])
	assert_str(crew.entry).is_equal("tactical")
	assert_float(crew.mission_seconds(StationFixture.START_TICK + 120)).is_equal(2.0)
