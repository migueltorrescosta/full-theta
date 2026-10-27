extends GdUnitTestSuite
## L3 tests of what ships of one session share over loopback (#11, E11, E12): allied ships
## share their faction's contact knowledge, callsigns and contract flags, but each keeps its
## own marks (FT-ARC-018, FT-SPA-023, FT-MIS-042); in PvP each ship's pair mechanics see only
## its own faction's knowledge and its own marks (FT-PAIR-016).

## An NPC faction clear of the crew factions (SessionRules.CREW_FACTIONS).
const NPC_FACTION: int = 2
const S = StationViews.Section

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


## A started session of two ships under `mode`: an "all" player on each (dev_all) and a
## Weapons player on each, ids [all-0, all-1, weapons-0, weapons-1].
func _session(mode: SessionRules.Mode) -> Array[NetClient]:
	var server: NetServer = h.fleet_server(mode, 2, [], true)
	var out: Array[NetClient] = []
	for ship: int in 2:
		out.append(await h.joined(server, "all-%d" % ship, StationViews.ALL, ship))
	for ship: int in 2:
		out.append(await h.joined(server, "weapons-%d" % ship, "weapons", ship))
	out[0].set_ready(true)
	out[1].set_ready(true)
	await h.until(func() -> bool: return server.world.tick > 2)
	return out


func _server() -> NetServer:
	return h.servers[0]


## Spawns an NPC 3 km ahead of the yard and waits until both crew factions detect it.
func _npc(server: NetServer) -> int:
	var c: SpawnShipCommand = SpawnShipCommand.new()
	c.enemy_key = server.world.catalog.keys()[0]
	c.faction = NPC_FACTION
	c.x = 3000.0
	server.world.submit(c)
	assert_bool(await h.until(func() -> bool: return c.tick >= 0 and c.accepted)).is_true()
	var w: SimWorld = server.world
	var seen: Callable = func() -> bool:
		return (
			KnowledgeSystem.is_detected(w, w.faction_of(0), c.result_id)
			and KnowledgeSystem.is_detected(w, w.faction_of(1), c.result_id)
		)
	assert_bool(await h.until(seen)).is_true()
	return c.result_id


## Puts a contract flag on the NPC in `faction`'s knowledge, as a Comms contract does.
func _flag(server: NetServer, faction: int, npc: int) -> void:
	var set_flag: SetContractFlagCommand = SetContractFlagCommand.new()
	set_flag.ship_id = 0
	set_flag.source = SimCommand.Source.SERVER
	set_flag.faction = faction
	set_flag.contact = npc
	set_flag.flag = KnowledgeTable.Flag.DISABLE
	server.world.submit(set_flag)


func _flags(c: NetClient) -> Array:
	return c.view.blocks.get(S.FEEDS, {}).get("flags", [])


## Puts the session on Easy with P9 (contract flags) shared, as Comms' press does, and waits for
## its next full view (test_contract_flags_l3.gd).
func _granted(server: NetServer, c: NetClient) -> bool:
	var s: NetSession = h.session_of(server, c)
	var fulls: int = c.view.full_count
	s.toggles = "easy"
	s.shares = [ViewFilter.CONTRACT_FLAGS]
	server.transport.set_view(s.id, s.view_key())
	return await h.until(func() -> bool: return c.view.full_count > fulls)


## Places a mark on the NPC from ship 0 and returns ship 0's marks event.
func _mark(c: NetClient, npc: int) -> Array:
	var from: int = h.mark(c)
	c.place_mark(-1, "Bogey", npc, Vector3.ZERO)
	var e: Dictionary = await h.next_event(c, NetProtocol.EVENT_MARKS, from)
	return [] if e.is_empty() else e["payload"]["marks"]


func _has_mark(marks: Array, npc: int) -> bool:
	return _slot_of(marks, npc) >= 0


func _slot_of(marks: Array, npc: int) -> int:
	for m: Dictionary in marks:
		if m["contact"] == npc:
			return m["slot"]
	return -1


# FT: FT-ARC-018, FT-SPA-023
# Allied ships share the faction's contacts and callsigns, but a mark stays on its ship; a
# Relay may send it to the ally's inbox.
func test_allies_share_contacts_and_callsigns_not_marks() -> void:
	var crews: Array[NetClient] = await _session(SessionRules.Mode.COOP)
	var server: NetServer = _server()
	var npc: int = await _npc(server)
	var same: Callable = func() -> bool:
		return crews[0].view.callsign(npc) != "" and crews[1].view.callsign(npc) != ""
	assert_bool(await h.until(same)).is_true()
	assert_str(crews[1].view.callsign(npc)).is_equal(crews[0].view.callsign(npc))
	var callsign: String = KnowledgeSystem.callsign(server.world, server.world.faction_of(0), npc)
	assert_str(crews[0].view.callsign(npc)).is_equal(callsign)
	var from: int = h.mark(crews[1])
	var slot: int = _slot_of(await _mark(crews[0], npc), npc)
	assert_int(slot).is_greater_equal(0)
	await h.wait(200)
	for e: Dictionary in h.events_of(crews[1], NetProtocol.EVENT_MARKS):
		assert_bool(_has_mark(e["payload"]["marks"], npc)).is_false()
	crews[0].send_mark(slot, 1)
	assert_dict(await h.next_event(crews[1], NetProtocol.EVENT_INBOX, from)).is_not_empty()


# FT: FT-MIS-042
# A contract flag one ship's contract set is in the faction's knowledge, so an allied ship's
# Weapons sees it under the P9 toggle (and not without it); honouring it costs the faction no
# reputation.
func test_allied_weapons_see_the_contract_flag() -> void:
	var crews: Array[NetClient] = await _session(SessionRules.Mode.COOP)
	var server: NetServer = _server()
	var npc: int = await _npc(server)
	var faction: int = server.world.faction_of(0)
	var standing: float = server.world.reputation.value_of(faction, NPC_FACTION)
	_flag(server, faction, npc)
	var row: Array = [{"contact": npc, "flag": KnowledgeTable.Flag.DISABLE}]
	assert_bool(await h.until(func() -> bool: return _flags(crews[1]) == row)).is_true()
	await h.wait(300)
	assert_array(_flags(crews[3])).is_empty()
	assert_bool(await _granted(server, crews[3])).is_true()
	assert_array(_flags(crews[3])).is_equal(row)
	await h.wait(300)
	assert_float(server.world.reputation.value_of(faction, NPC_FACTION)).is_equal(standing)


# FT: FT-PAIR-016
# In PvP (a race) each ship's pair mechanics use only its own faction's knowledge and marks:
# ship 0's contract flag reaches its own Weapons with P9 but not the rival's, the rival's
# callsigns are its own faction's, ship 0's mark stays its own and can't be sent to the rival.
func test_pvp_ships_use_only_their_own_knowledge_and_marks() -> void:
	var crews: Array[NetClient] = await _session(SessionRules.Mode.RACE)
	var server: NetServer = _server()
	var w: SimWorld = server.world
	assert_int(w.faction_of(0)).is_not_equal(w.faction_of(1))
	var npc: int = await _npc(server)
	_flag(server, w.faction_of(0), npc)
	for c: NetClient in [crews[2], crews[3]]:
		assert_bool(await _granted(server, c)).is_true()
	var row: Array = [{"contact": npc, "flag": KnowledgeTable.Flag.DISABLE}]
	assert_bool(await h.until(func() -> bool: return _flags(crews[2]) == row)).is_true()
	await h.wait(300)
	assert_array(_flags(crews[3])).is_empty()
	for ship: int in 2:
		var want: String = KnowledgeSystem.callsign(w, w.faction_of(ship), npc)
		var got: Callable = func() -> bool: return crews[ship].view.callsign(npc) == want
		assert_bool(await h.until(got)).is_true()
	var from: int = h.mark(crews[0])
	var slot: int = _slot_of(await _mark(crews[0], npc), npc)
	assert_int(slot).is_greater_equal(0)
	crews[0].send_mark(slot, 1)
	var e: Dictionary = await h.next_event(crews[0], NetProtocol.EVENT_REQUEST_REJECTED, from)
	assert_str(e["payload"]["reason"]).is_equal(CrewRelay.BAD_TARGET)
	for ev: Dictionary in h.events_of(crews[1], NetProtocol.EVENT_MARKS):
		assert_bool(_has_mark(ev["payload"]["marks"], npc)).is_false()
