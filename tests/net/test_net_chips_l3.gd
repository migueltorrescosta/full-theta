extends GdUnitTestSuite
## L3 tests of request chips (NetChips, ChipsSection) and the host's lobby toggles over
## loopback: sending and answering, silent expiry, Hard switching chips off, the hold fire
## chip from Comms to Weapons, player-initiated only, and the cooperative events counted per pair.

const PLAYER: int = NetHarness.PLAYER
const CHIPS: StationViews.Section = StationViews.Section.CHIPS
const SECRET: String = "s3cret"

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


## A server with a host (Captain, so it holds no station) and one client per station.
func _crew(server: NetServer) -> Dictionary:
	var out: Dictionary = {}
	out["host"] = await h.welcomed(server, "host", "", SECRET)
	await h.pick(out["host"], "captain")
	for station: String in StationViews.CREW:
		out[station] = await h.joined(server, station, station)
	return out


func _rejected(c: NetClient, from: int, type: int = NetProtocol.Type.CHIP) -> String:
	var e: Dictionary = await h.next_event(
		c,
		NetProtocol.EVENT_REQUEST_REJECTED,
		from,
		func(ev: Dictionary) -> bool: return ev["payload"]["request"] == type
	)
	return e.get("payload", {}).get("reason", "")


func _chips(c: NetClient) -> Array:
	return c.view.blocks.get(CHIPS, {}).get("chips", [])


func _count(server: NetServer, pair: String, kind: String) -> int:
	return server.session.coop.count_of(pair, kind)


# FT: FT-PAIR-021, FT-PAIR-013, FT-STN-010
# Helm sends a boost chip; it shows on Engineering and on Helm, on no other station; the
# chip list is the data file's. Engineering answers it, Helm hears so, and the pair's
# counts show a chip sent and answered.
func test_a_chip_is_sent_shown_and_answered() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var crew: Dictionary = await _crew(server)
	var helm: NetClient = crew["helm"]
	var eng: NetClient = crew["engineering"]
	var from: int = h.mark(helm)
	helm.send_chip("boost")
	assert_bool(await h.until(func() -> bool: return _chips(eng).size() == 1)).is_true()
	var row: Dictionary = _chips(eng)[0]
	assert_int(row["chip"]).is_equal(NetChips.index_of("boost"))
	assert_int(row["from"]).is_equal(StationViews.CREW.find("helm"))
	assert_int(row["to"]).is_equal(StationViews.CREW.find("engineering"))
	assert_int(row["arg"]).is_equal(-1)
	assert_int(row["expires"] - row["sent"]).is_equal(int(NetChips.def().expiry_s * 60.0))
	assert_bool(await h.until(func() -> bool: return _chips(helm).size() == 1)).is_true()
	await h.wait(300)
	for other: String in ["weapons", "science", "relay", "comms"]:
		assert_array(_chips(crew[other])).override_failure_message(other).is_empty()
	assert_int(_count(server, "p1", CoopEvents.CHIP_SENT)).is_equal(1)
	assert_int(_count(server, "p1", CoopEvents.CHIP_ANSWERED)).is_equal(0)
	# Only the receiving station answers.
	var wrong: int = h.mark(helm)
	helm.answer_chip(row["id"], true)
	assert_str(await _rejected(helm, wrong)).is_equal(NetChips.NOT_YOURS)
	eng.answer_chip(row["id"], true)
	assert_bool(await h.until(func() -> bool: return _chips(eng).is_empty())).is_true()
	var heard: Dictionary = await h.next_event(helm, NetProtocol.EVENT_CHIP_ANSWER, from)
	assert_str(heard["payload"]["chip"]).is_equal("boost")
	assert_bool(heard["payload"]["accept"]).is_true()
	assert_int(_count(server, "p1", CoopEvents.CHIP_ANSWERED)).is_equal(1)
	assert_int(server.session.coop.cooperative("p1")).is_equal(1)
	# A declined chip is no cooperative event.
	helm.send_chip("boost")
	assert_bool(await h.until(func() -> bool: return _chips(eng).size() == 1)).is_true()
	eng.answer_chip(_chips(eng)[0]["id"], false)
	assert_bool(await h.until(func() -> bool: return _chips(eng).is_empty())).is_true()
	assert_int(_count(server, "p1", CoopEvents.CHIP_DECLINED)).is_equal(1)
	assert_int(server.session.coop.cooperative("p1")).is_equal(1)


# FT: FT-PAIR-021, FT-STN-010
# Every chip of §7.4 is in the data list with its sender and receiver, hold fire included.
func test_the_chip_list_is_the_spec_list() -> void:
	var want: Dictionary = {
		"boost": ["helm", "engineering", "p1"],
		"power": ["weapons", "engineering", "p6"],
		"bring_to_bear": ["weapons", "helm", "p2"],
		"sensor_power": ["science", "engineering", "p10"],
		"scan_mark": ["science", "helm", "p3"],
		"fabricate_probe": ["relay", "engineering", "p11"],
		"hold_fire": ["comms", "weapons", "p9"],
	}
	var def: ChipsDef = NetChips.def()
	assert_int(def.chips.size()).is_equal(7)
	for chip: ChipDef in def.chips:
		assert_array(want.keys()).contains([String(chip.id)])
		(
			assert_array(
				[
					String(chip.from_station),
					String(chip.to_station),
					CoopEvents.pair_of(String(chip.from_station), String(chip.to_station))
				]
			)
			. is_equal(want[String(chip.id)])
		)


# FT: FT-PAIR-021, FT-PAIR-009, FT-PAIR-012
# The sender must hold the chip's sender station and not its receiver (a joint view runs it
# as a direct action), the receiver must be played, an argument must make sense, and a chip
# already open is not sent twice.
func test_chip_rules() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var crew: Dictionary = await _crew(server)
	var cases: Array = [
		["weapons", "boost", -1, NetChips.NOT_YOURS],
		["comms", "hold_fire", 1, NetChips.BAD_ARG],
		["weapons", "bring_to_bear", 9, NetChips.BAD_ARG],
		["helm", "no_such_chip", -1, NetChips.BAD_CHIP],
	]
	for c: Array in cases:
		var client: NetClient = crew[c[0]]
		var from: int = h.mark(client)
		client.send_chip(c[1], c[2])
		assert_str(await _rejected(client, from)).override_failure_message(c[1]).is_equal(c[3])
	# A mount chip carries the mount index.
	crew["weapons"].send_chip("bring_to_bear", 0)
	assert_bool(await h.until(func() -> bool: return _chips(crew["helm"]).size() == 1)).is_true()
	assert_int(_chips(crew["helm"])[0]["arg"]).is_equal(0)
	var from: int = h.mark(crew["weapons"])
	crew["weapons"].send_chip("bring_to_bear", 0)
	assert_str(await _rejected(crew["weapons"], from)).is_equal(NetChips.ALREADY_OPEN)
	# A joint view holding both stations doesn't send a chip to itself.
	var tactical: NetClient = await h.joined(server, "tac", "tactical")
	from = h.mark(tactical)
	tactical.send_chip("bring_to_bear", 0)
	assert_str(await _rejected(tactical, from)).is_equal(NetChips.SAME_SCREEN)
	# The Captain sends none.
	from = h.mark(crew["host"])
	crew["host"].send_chip("boost")
	assert_str(await _rejected(crew["host"], from)).is_equal(ServerSession.NOT_CREW)
	# Nobody plays Engineering: the chip has no one to reach.
	var other: NetServer = h.server(false, 10.0, SECRET)
	var helm: NetClient = await h.joined(other, "solo", "helm")
	from = h.mark(helm)
	helm.send_chip("boost")
	assert_str(await _rejected(helm, from)).is_equal(NetChips.NOBODY)


# FT: FT-PAIR-021, FT-PAIR-012
# Hold fire (D191) goes from Comms to Weapons and carries a detected contact: Weapons gets it
# with the contact's id, Comms again at once is refused as open, and an undetected contact is
# a bad argument. Nothing else receives it.
func test_hold_fire_goes_from_comms_to_weapons() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var crew: Dictionary = await _crew(server)
	var w: SimWorld = server.world
	var comms: NetClient = crew["comms"]
	var from: int = h.mark(comms)
	comms.send_chip("hold_fire", NetHarness.ENEMY)
	assert_str(await _rejected(comms, from)).is_equal(NetChips.BAD_ARG)
	w.knowledge.detected[w.knowledge.ensure_contact(w.faction_of(PLAYER), NetHarness.ENEMY)] = 1
	comms.send_chip("hold_fire", NetHarness.ENEMY)
	assert_bool(await h.until(func() -> bool: return _chips(crew["weapons"]).size() == 1)).is_true()
	var row: Dictionary = _chips(crew["weapons"])[0]
	assert_int(row["chip"]).is_equal(NetChips.index_of("hold_fire"))
	assert_int(row["arg"]).is_equal(NetHarness.ENEMY)
	assert_int(row["from"]).is_equal(StationViews.CREW.find("comms"))
	assert_int(row["to"]).is_equal(StationViews.CREW.find("weapons"))
	from = h.mark(comms)
	comms.send_chip("hold_fire", NetHarness.ENEMY)
	assert_str(await _rejected(comms, from)).is_equal(NetChips.ALREADY_OPEN)
	await h.wait(300)
	for other: String in ["helm", "science", "relay", "engineering"]:
		assert_array(_chips(crew[other])).override_failure_message(other).is_empty()
	crew["weapons"].answer_chip(row["id"], true)
	assert_bool(await h.until(func() -> bool: return _chips(crew["weapons"]).is_empty())).is_true()
	assert_int(_count(server, "p9", CoopEvents.CHIP_SENT)).is_equal(1)
	assert_int(_count(server, "p9", CoopEvents.CHIP_ANSWERED)).is_equal(1)


# FT: FT-PAIR-009, FT-PAIR-017, FT-PAIR-018
# On Hard chips are off; the host's toggle change reaches every session's view at once, so
# the same message works on Easy and is refused on Hard.
func test_hard_switches_chips_off() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var crew: Dictionary = await _crew(server)
	var host: NetClient = crew["host"]
	var helm: NetClient = crew["helm"]
	host.set_toggles("hard")
	(
		assert_bool(await h.until(func() -> bool: return server.session.toggles.encode() == "hard"))
		. is_true()
	)
	(
		assert_bool(
			await h.until(func() -> bool: return h.session_of(server, helm).toggles == "hard")
		)
		. is_true()
	)
	var from: int = h.mark(helm)
	helm.send_chip("boost")
	assert_str(await _rejected(helm, from)).is_equal(NetChips.OFF)
	host.set_toggles("normal")
	(
		assert_bool(
			await h.until(func() -> bool: return h.session_of(server, helm).toggles == "normal")
		)
		. is_true()
	)
	helm.send_chip("boost")
	(
		assert_bool(await h.until(func() -> bool: return _chips(crew["engineering"]).size() == 1))
		. is_true()
	)
	# An edited set with the chips toggle off refuses them on any preset.
	var custom: DataToggles = DataToggles.of_preset("easy").with_value(&"chips", 0)
	host.set_toggles(custom.encode())
	(
		assert_bool(
			await h.until(
				func() -> bool: return h.session_of(server, helm).toggles == custom.encode()
			)
		)
		. is_true()
	)
	from = h.mark(crew["weapons"])
	crew["weapons"].send_chip("power")
	assert_str(await _rejected(crew["weapons"], from)).is_equal(NetChips.OFF)
	assert_int(server.session.chips.open_of(PLAYER).size()).is_equal(1)


# FT: FT-PAIR-013
# An unanswered chip expires silently: no event tells anyone, the chip leaves every list, and
# the count for the debrief shows it expired and not answered. Paused sim time doesn't age it.
func test_an_unanswered_chip_expires_silently() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var crew: Dictionary = await _crew(server)
	var helm: NetClient = crew["helm"]
	var eng: NetClient = crew["engineering"]
	helm.send_chip("boost")
	assert_bool(await h.until(func() -> bool: return _chips(eng).size() == 1)).is_true()
	var marks: Array = [h.mark(helm), h.mark(eng)]
	var expiry_ticks: int = int(NetChips.def().expiry_s * 60.0)
	for i: int in expiry_ticks - 120:
		server.world.step()
	server.world.drain_events()
	await h.wait(200)
	assert_int(_chips(eng).size()).is_equal(1)
	for i: int in 130:
		server.world.step()
	server.world.drain_events()
	assert_bool(await h.until(func() -> bool: return _chips(eng).is_empty())).is_true()
	assert_bool(await h.until(func() -> bool: return _chips(helm).is_empty())).is_true()
	assert_int(_count(server, "p1", CoopEvents.CHIP_EXPIRED)).is_equal(1)
	assert_int(_count(server, "p1", CoopEvents.CHIP_ANSWERED)).is_equal(0)
	assert_int(server.session.coop.cooperative("p1")).is_equal(0)
	# Silent: neither station got an event of any kind about it.
	for c: NetClient in [helm, eng]:
		var seen: Array = (h.events[c] as Array).slice(marks[0] if c == helm else marks[1])
		for e: Dictionary in seen:
			assert_str(e["type"]).is_not_equal(NetProtocol.EVENT_CHIP_ANSWER)
			assert_str(e["type"]).is_not_equal(NetProtocol.EVENT_REQUEST_REJECTED)


# FT: FT-PAIR-012
# Chips are player-initiated only: a running encounter with a full crew and no chip sent
# makes none, and the server code has no way to open one but a CHIP message.
func test_chips_are_player_initiated_only() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var crew: Dictionary = await _crew(server)
	assert_bool(await h.start(server, crew["helm"])).is_true()
	await h.wait(1500)
	for station: String in StationViews.CREW:
		assert_array(_chips(crew[station])).override_failure_message(station).is_empty()
	assert_array(server.session.chips.open_of(PLAYER)).is_empty()
	assert_dict(server.session.coop.counts()).is_empty()


# FT: FT-PAIR-013
# The cooperative events are written to the session log: one `coop` line per event and
# counters per pair and kind, which the debrief of #10 reads.
func test_cooperative_events_are_written_to_the_session_log() -> void:
	var server: NetServer = h.server(false, 10.0, SECRET)
	var path: String = "user://test-coop-%d.jsonl" % Time.get_ticks_usec()
	assert_int(server.start_session_log(path)).is_equal(OK)
	var crew: Dictionary = await _crew(server)
	crew["science"].send_chip("scan_mark")
	assert_bool(await h.until(func() -> bool: return _chips(crew["helm"]).size() == 1)).is_true()
	crew["helm"].answer_chip(_chips(crew["helm"])[0]["id"], true)
	(
		assert_bool(
			await h.until(
				func() -> bool: return _count(server, "p3", CoopEvents.CHIP_ANSWERED) == 1
			)
		)
		. is_true()
	)
	var counters: Dictionary = server.session_log.counters()
	assert_int(counters["coop.p3.chip_sent"]).is_equal(1)
	assert_int(counters["coop.p3.chip_answered"]).is_equal(1)
	var lines: Array = []
	for line: String in FileAccess.get_file_as_string(path).split("\n", false):
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary and parsed["kind"] == "coop":
			lines.append(parsed)
	assert_int(lines.size()).is_equal(2)
	assert_str(lines[0]["coop"]).is_equal("chip_sent")
	assert_str(lines[1]["pair"]).is_equal("p3")
	var debrief: Array = server.session.coop.debrief()
	assert_int(debrief.size()).is_equal(1)
	assert_int(debrief[0]["events"]).is_equal(1)
	assert_array(debrief[0]["stations"]).is_equal(["helm", "science"])
	server.session_log.close()
	DirAccess.remove_absolute(path)
