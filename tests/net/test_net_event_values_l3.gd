extends GdUnitTestSuite
## L3: the sim events with exact values (EXACT_EVENTS) reach each station as its view may
## carry them (D224, FT-PAIR-010, FT-PAIR-019): Engineering exact, the others by the
## summaries toggle, Comms none.

const PLAYER: int = NetHarness.PLAYER

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


func _event(server: NetServer, kind: StringName, value: float, tag: StringName) -> SimEvent:
	var e: SimEvent = SimEvent.new()
	e.tick = server.world.tick
	e.kind = kind
	e.ship_id = PLAYER
	e.faction = server.world.faction_of(PLAYER)
	e.value = value
	e.tag = tag
	return e


## The value of the first event of a kind a client got since `from`, or -1.0 for none.
func _value(c: NetClient, kind: String, from: int) -> float:
	var seen: Array = h.events[c]
	for i: int in range(from, seen.size()):
		if seen[i]["type"] == kind:
			return float(seen[i]["payload"]["value"])
	return -1.0


# FT: FT-PAIR-010, FT-PAIR-019
func test_exact_values_follow_the_summaries_toggle_and_never_reach_comms() -> void:
	var server: NetServer = h.server()
	var eng: NetClient = await h.joined(server, "eng", "engineering")
	var helm: NetClient = await h.joined(server, "helm", "helm")
	var sci: NetClient = await h.joined(server, "sci", "science")
	var comms: NetClient = await h.joined(server, "comms", "comms")
	var band: float = HealthBand.quantise(0.4, DataToggles.def().band_edges)
	for row: Array in [["easy", 0.4], ["normal", band], ["hard", 0.0]]:
		for c: NetClient in [eng, helm, sci, comms]:
			h.session_of(server, c).toggles = row[0]
		var marks: Dictionary = {}
		for c: NetClient in [eng, helm, sci, comms]:
			marks[c] = h.mark(c)
		(
			server
			. session
			. after_ticks(
				[
					_event(server, &"shield_low", 0.4, &""),
					_event(server, &"fault", 7.0, &"engines"),
					_event(server, &"subsystem_damaged", 0.4, &"engines"),
					_event(server, &"hit", 0.4, &"plain"),
				]
			)
		)
		(
			assert_bool(await h.until(func() -> bool: return _value(sci, "hit", marks[sci]) >= 0.0))
			. is_true()
		)
		(
			assert_bool(
				await h.until(
					func() -> bool: return _value(eng, "subsystem_damaged", marks[eng]) >= 0.0
				)
			)
			. is_true()
		)
		await h.wait(200)
		var code: String = row[0]
		# Engineering: always exact.
		(
			assert_float(_value(eng, "shield_low", marks[eng]))
			. override_failure_message(code)
			. is_equal_approx(0.4, 0.001)
		)
		assert_float(_value(eng, "fault", marks[eng])).is_equal_approx(7.0, 0.001)
		assert_float(_value(eng, "subsystem_damaged", marks[eng])).is_equal_approx(0.4, 0.001)
		# Helm: the shield alert as its summary, the fault as a plain alert, no damage event.
		(
			assert_float(_value(helm, "shield_low", marks[helm]))
			. override_failure_message(code)
			. is_equal_approx(row[1], 0.001)
		)
		assert_float(_value(helm, "fault", marks[helm])).override_failure_message(code).is_equal(
			0.0
		)
		assert_float(_value(helm, "subsystem_damaged", marks[helm])).is_equal(-1.0)
		# Science: no shield alert, the fault with no value, no damage event.
		assert_float(_value(sci, "shield_low", marks[sci])).is_equal(-1.0)
		assert_float(_value(sci, "fault", marks[sci])).is_equal(0.0)
		assert_float(_value(sci, "subsystem_damaged", marks[sci])).is_equal(-1.0)
		# Comms gets none of them, at any setting, but still the plain alerts.
		for kind: String in ["shield_low", "fault", "subsystem_damaged"]:
			(
				assert_float(_value(comms, kind, marks[comms]))
				. override_failure_message(code + kind)
				. is_equal(-1.0)
			)
		assert_float(_value(comms, "hit", marks[comms])).is_equal_approx(0.4, 0.001)
