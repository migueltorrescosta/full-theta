extends GdUnitTestSuite
## The pure rules of marks, the alert level and pings (CrewMarks, CrewPings).

const SHIP: int = 0
const CREW: CrewMarks.Role = CrewMarks.Role.CREW
const RELAY: CrewMarks.Role = CrewMarks.Role.RELAY
const CAPTAIN: CrewMarks.Role = CrewMarks.Role.CAPTAIN
const NONE: CrewMarks.Role = CrewMarks.Role.NONE

var m: CrewMarks


func before_test() -> void:
	m = CrewMarks.new()


static func _free(x: float, site: int = 0) -> Dictionary:
	return {"contact": -1, "site": site, "x": x, "y": 0.0, "z": 0.0}


static func _on(contact: int) -> Dictionary:
	return {"contact": contact, "site": -1, "x": 0.0, "y": 0.0, "z": 0.0}


func _fill(role: CrewMarks.Role = CREW, session: int = 1) -> void:
	for k: int in CrewMarks.SLOTS:
		assert_str(m.place(SHIP, role, session, "Ana", -1, "", _free(k))).is_empty()


# FT: FT-SPA-012, FT-SPA-022
func test_eight_named_slots_then_marks_full() -> void:
	_fill()
	var names: Array = m.marks_of(SHIP).map(func(d: Dictionary) -> String: return d["name"])
	assert_array(names).is_equal(CrewMarks.DEFAULT_NAMES)
	assert_str(m.place(SHIP, CREW, 1, "Ana", -1, "", _free(0))).is_equal(CrewMarks.MARKS_FULL)
	assert_str(m.place(SHIP, CREW, 1, "Ana", 3, "", _free(0))).is_equal(CrewMarks.MARKS_FULL)
	assert_str(m.place(SHIP, CAPTAIN, 9, "Cap", 3, "", _free(0))).is_equal(CrewMarks.MARKS_FULL)
	# Relay must name the slot it replaces.
	assert_str(m.place(SHIP, RELAY, 2, "Rui", -1, "", _free(0))).is_equal(CrewMarks.MARKS_FULL)
	assert_str(m.place(SHIP, RELAY, 2, "Rui", 3, "Rally", _on(1))).is_empty()
	var d: Dictionary = m.marks_of(SHIP)[3]
	assert_dict(d).is_equal(
		{
			"slot": 3,
			"name": "Rally",
			"contact": 1,
			"site": -1,
			"x": 0.0,
			"y": 0.0,
			"z": 0.0,
			"by": "Rui"
		}
	)
	assert_int(m.marks_of(SHIP).size()).is_equal(8)


# FT: FT-SPA-013, FT-SPA-022
func test_an_occupied_slot_is_taken_for_non_relay() -> void:
	assert_str(m.place(SHIP, CREW, 1, "Ana", 2, "", _free(5.0))).is_empty()
	assert_str(m.place(SHIP, CREW, 1, "Ana", 2, "", _free(6.0))).is_equal(CrewMarks.SLOT_TAKEN)
	assert_str(m.place(SHIP, CAPTAIN, 9, "Cap", 2, "", _free(6.0))).is_equal(CrewMarks.SLOT_TAKEN)
	assert_str(m.place(SHIP, CAPTAIN, 9, "Cap", -1, "", _free(6.0))).is_empty()
	assert_str(m.marks_of(SHIP)[0]["by"]).is_equal("Cap")
	assert_str(m.place(SHIP, NONE, 7, "Vic", -1, "", _free(6.0))).is_equal(CrewMarks.NOT_CREW)


# FT: FT-SPA-013, FT-RLY-003
func test_only_relay_edits_others_marks_and_the_captain_never_edits() -> void:
	assert_str(m.place(SHIP, CREW, 1, "Ana", 0, "", _free(5.0))).is_empty()
	for role: CrewMarks.Role in [CREW, CAPTAIN]:
		var why: String = CrewMarks.NOT_YOURS if role == CREW else CommandGate.NOT_ALLOWED
		assert_str(m.rename(SHIP, role, 2, 0, "X")).is_equal(why)
		assert_str(m.move(SHIP, role, 2, 0, _free(1.0))).is_equal(why)
		assert_str(m.delete(SHIP, role, 2, 0)).is_equal(why)
	# The Captain can't edit even its own.
	assert_str(m.place(SHIP, CAPTAIN, 9, "Cap", 1, "", _free(5.0))).is_empty()
	assert_str(m.delete(SHIP, CAPTAIN, 9, 1)).is_equal(CommandGate.NOT_ALLOWED)
	# The owner edits its own.
	assert_str(m.rename(SHIP, CREW, 1, 0, "  Home  ")).is_empty()
	assert_str(m.marks_of(SHIP)[0]["name"]).is_equal("Home")
	assert_str(m.rename(SHIP, CREW, 1, 0, "")).is_empty()
	assert_str(m.marks_of(SHIP)[0]["name"]).is_equal("Alpha")
	# Relay renames, attaches, moves and deletes any.
	assert_str(m.rename(SHIP, RELAY, 2, 1, "Cap's")).is_empty()
	assert_str(m.move(SHIP, RELAY, 2, 0, _on(1))).is_empty()
	assert_int(m.marks_of(SHIP)[0]["contact"]).is_equal(1)
	assert_str(m.move(SHIP, RELAY, 2, 0, _free(7.0, 0))).is_empty()
	assert_int(m.marks_of(SHIP)[0]["contact"]).is_equal(-1)
	assert_str(m.delete(SHIP, RELAY, 2, 1)).is_empty()
	assert_bool(m.has_mark(SHIP, 1)).is_false()
	assert_str(m.delete(SHIP, RELAY, 2, 1)).is_equal(CrewMarks.BAD_MARK)


# FT: FT-SPA-014
func test_free_marks_wrap_onto_the_site_and_keep_64_bits() -> void:
	m.period = 200_000.0
	assert_str(m.place(SHIP, CREW, 1, "Ana", -1, "", _free(150_000.0))).is_empty()
	assert_float(m.marks_of(SHIP)[0]["x"]).is_equal(-50_000.0)
	var fine: float = 99_999.123456789
	assert_str(m.place(SHIP, CREW, 1, "Ana", -1, "", _free(fine))).is_empty()
	assert_float(m.marks_of(SHIP)[1]["x"]).is_equal(fine)
	assert_str(m.place(SHIP, CREW, 1, "Ana", -1, "", _free(NAN))).is_equal(CrewMarks.BAD_MARK)
	assert_str(m.place(SHIP, CREW, 1, "Ana", -1, "", _free(1.0, -1))).is_equal(CrewMarks.BAD_MARK)
	assert_str(m.place(SHIP, CREW, 1, "Ana", 8, "", _free(1.0))).is_equal(CrewMarks.BAD_MARK)


# FT: FT-STN-008
func test_alert_from_crew_only_and_reset() -> void:
	assert_int(m.alert(SHIP)).is_equal(CrewMarks.ALERT_NORMAL)
	assert_str(m.set_alert(SHIP, CREW, CrewMarks.ALERT_RED)).is_empty()
	assert_str(m.set_alert(SHIP, CAPTAIN, 1)).is_equal(CrewMarks.NOT_CREW)
	assert_str(m.set_alert(SHIP, NONE, 1)).is_equal(CrewMarks.NOT_CREW)
	assert_str(m.set_alert(SHIP, RELAY, 3)).is_equal(CrewMarks.BAD_LEVEL)
	assert_int(m.alert(SHIP)).is_equal(CrewMarks.ALERT_RED)
	_fill()
	m.reset(SHIP)
	assert_int(m.alert(SHIP)).is_equal(CrewMarks.ALERT_NORMAL)
	assert_array(m.marks_of(SHIP)).is_empty()


func test_roles_of_entries() -> void:
	assert_int(CrewMarks.role_of("ops")).is_equal(RELAY)
	assert_int(CrewMarks.role_of("relay")).is_equal(RELAY)
	assert_int(CrewMarks.role_of("tactical")).is_equal(CREW)
	assert_int(CrewMarks.role_of("captain")).is_equal(CAPTAIN)
	assert_int(CrewMarks.role_of("viewer")).is_equal(NONE)
	assert_int(CrewMarks.role_of("")).is_equal(NONE)


# FT: FT-SPA-017
func test_ping_rate_limit_is_per_session() -> void:
	var p: CrewPings = CrewPings.new()
	for i: int in 3:
		assert_bool(p.take(1, 0)).is_true()
	assert_bool(p.take(1, 0)).is_false()
	assert_bool(p.take(2, 0)).is_true()
	assert_bool(p.take(1, 499_000)).is_false()
	assert_bool(p.take(1, 501_000)).is_true()


# FT: FT-SPA-031
func test_a_ping_on_an_item_pinged_by_another_within_3_s_is_a_copy() -> void:
	var p: CrewPings = CrewPings.new()
	assert_str(p.copy_of(SHIP, "contact", 1, -1, 1, "Ana", 0)).is_empty()
	assert_str(p.copy_of(SHIP, "contact", 1, -1, 2, "Rui", 1_000_000)).is_equal("Ana")
	# The pinger's own repeat, another item, another ship: not copies.
	assert_str(p.copy_of(SHIP, "contact", 1, -1, 1, "Ana", 1_500_000)).is_empty()
	assert_str(p.copy_of(SHIP, "contact", 2, -1, 2, "Rui", 1_500_000)).is_empty()
	assert_str(p.copy_of(1, "contact", 1, -1, 2, "Rui", 1_500_000)).is_empty()
	assert_str(p.copy_of(SHIP, "point", -1, 0, 2, "Rui", 1_600_000)).is_empty()
	assert_str(p.copy_of(SHIP, "point", -1, 0, 1, "Ana", 1_600_000)).is_empty()
	# Past 3 s it is a new ping.
	assert_str(p.copy_of(SHIP, "contact", 1, -1, 2, "Rui", 4_600_000)).is_empty()
