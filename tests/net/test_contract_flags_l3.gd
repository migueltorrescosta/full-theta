extends GdUnitTestSuite
## Contract target flags are held in the faction's KNOW and reach Weapons only under the
## P9 toggle (FT-MIS-042, D82, FT-PAIR-007): over loopback, a Weapons view needs the
## contract_flags shortcut on and shared; a joint view holding Comms needs no press
## (FT-JNT-005); the flags of a contact nobody detects aren't sent.

const PLAYER: int = CommsL3.PLAYER
const ENEMY: int = CommsL3.ENEMY
const S = StationViews.Section

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


func _flags(c: NetClient) -> Array:
	return c.view.blocks.get(S.FEEDS, {}).get("flags", [])


## Puts the session on a toggle code and shared shortcuts, and waits for its next full view.
func _view(server: NetServer, c: NetClient, code: String, shares: Array[StringName]) -> bool:
	var s: NetSession = h.session_of(server, c)
	var fulls: int = c.view.full_count
	s.toggles = code
	s.shares = shares
	server.transport.set_view(s.id, s.view_key())
	return await h.until(func() -> bool: return c.view.full_count > fulls)


# FT: FT-MIS-042
# The flag a contract put on a detected contact is in Weapons' FEEDS block only when
# contract_flags is on and shared; Normal and Hard keep it off; a joint view with Comms
# has it without a press.
func test_flags_reach_weapons_only_with_p9_granted() -> void:
	var server: NetServer = h.server()
	var weapons: NetClient = await h.joined(server, "weapons", "weapons")
	var parley: NetClient = await h.joined(server, "parley", "parley")
	server.session.launch(PLAYER)
	var set_flag: SetContractFlagCommand = SetContractFlagCommand.new()
	set_flag.ship_id = PLAYER
	set_flag.source = SimCommand.Source.SERVER
	set_flag.faction = server.world.faction_of(PLAYER)
	set_flag.contact = ENEMY
	set_flag.flag = KnowledgeTable.Flag.DISABLE
	server.world.submit(set_flag)
	var row: Array = [{"contact": ENEMY, "flag": KnowledgeTable.Flag.DISABLE}]
	assert_bool(await h.until(func() -> bool: return _flags(parley) == row)).is_true()
	# Easy, nothing shared: Weapons alone has the contact but not the flag.
	await h.wait(300)
	assert_bool(weapons.view.contacts.get("model", {}).has(ENEMY)).is_true()
	assert_array(_flags(weapons)).is_empty()
	# Shared on Easy: it arrives (Comms' press, F; here the session is set directly).
	assert_bool(await _view(server, weapons, "easy", [ViewFilter.CONTRACT_FLAGS])).is_true()
	assert_array(_flags(weapons)).is_equal(row)
	# Normal and Hard have the toggle off: sharing changes nothing.
	for code: String in ["normal", "hard"]:
		assert_bool(await _view(server, weapons, code, [ViewFilter.CONTRACT_FLAGS])).is_true()
		assert_array(_flags(weapons)).override_failure_message(code).is_empty()
	assert_bool(await _view(server, weapons, "normal:1011000", [])).is_true()
	assert_array(_flags(weapons)).is_empty()


# FT: FT-MIS-042
# The view filter decides per toggle code and shared set, with no server: the flag rows
# survive only where the shortcut is granted, and the signatures differ so the sections
# are encoded apart.
func test_view_filter_grants_the_flags() -> void:
	var w: SimWorld = StoryFixture.duel()
	w.step()
	w.knowledge.flag[w.knowledge.ensure_contact(StoryFixture.BLUE, 1)] = KnowledgeTable.Flag.PROTECT
	assert_bool(KnowledgeSystem.is_detected(w, StoryFixture.BLUE, 1)).is_true()
	var want: Array = [{"contact": 1, "flag": KnowledgeTable.Flag.PROTECT}]
	var cases: Array = [
		["weapons", "easy", false],
		["weapons", "easy#contract_flags", true],
		["weapons", "normal#contract_flags", false],
		["weapons", "hard#contract_flags", false],
		["parley", "hard", true],
		["comms", "hard", true],
		["captain", "hard", true],
	]
	var signatures: Dictionary = {}
	for c: Array in cases:
		var f: ViewFilter = ViewFilter.of(c[0], c[1])
		var bytes: PackedByteArray = StationViews.block_bytes(S.FEEDS, w, 0, f)
		var got: Array = NetBlock.decode(StationViews.BLOCKS[S.FEEDS], bytes)["flags"]
		if c[2]:
			assert_array(got).override_failure_message(str(c)).is_equal(want)
		else:
			assert_array(got).override_failure_message(str(c)).is_empty()
		signatures[f.signature(S.FEEDS)] = c[2]
	assert_int(signatures.size()).is_greater(1)
