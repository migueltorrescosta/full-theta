extends GdUnitTestSuite
## The COMMS block (CommsView): what Comms' board carries for a ship, built from
## STORY, the economy and the module table, and the same from the net thread's copy of the
## world (SimCopy). It never holds Engineering data beyond the hull band (FT-PAIR-010).

const BLUE: int = StoryFixture.BLUE
const SITE: int = StoryFixture.SITE


func _docked() -> SimWorld:
	var w: SimWorld = StoryFixture.world()
	StoryFixture.spawn(w, TestDefs.corvette(), BLUE)
	w.economy.credits[0] = 2000
	StoryFixture.dock(w, 0)
	return w


func _post(w: SimWorld, spec: PostCardCommand) -> int:
	return StoryFixture.post(w, 0, spec)


# FT: FT-PAIR-010
# The block's fields are the schema's alone and none is an Engineering field: the
# Engineering block's names (spare parts, subsystems, shield figures) are nowhere in it,
# at any depth.
func test_no_engineering_field() -> void:
	var w: SimWorld = _docked()
	var own: Array = CommsView.block(w, 0).keys()
	assert_array(own).is_equal(
		StationViews.BLOCKS[StationViews.Section.COMMS].map(func(f: Array) -> String: return f[0])
	)
	var names: Array[String] = _names(StationViews.BLOCKS[StationViews.Section.COMMS])
	for field: Array in StationViews.BLOCKS[StationViews.Section.ENGINEERING]:
		assert_array(names).not_contains([field[0]])
	for banned: String in ["heat", "pips", "health", "spare_parts", "subsystems", "fault"]:
		assert_array(names).not_contains([banned])


func _names(schema: Array) -> Array[String]:
	var out: Array[String] = []
	for field: Array in schema:
		out.append(field[0])
		if field[1] is Array:
			out.append_array(_names(field[1][1]))
	return out


# FT: FT-COM-001, FT-COM-005, FT-COM-008
# A card row has its text keys, reward and time left, and the reputation range only where
# the data marks it visible; settled cards stay on the board, other ships' cards don't.
func test_card_rows() -> void:
	var w: SimWorld = _docked()
	var seen: PostCardCommand = StoryFixture.card(StoryTable.Kind.MISSION)
	seen.reward_credits = 250
	seen.rep_interaction = &"rep.complete_mission"
	seen.expires_s = 90.0
	var hidden: PostCardCommand = StoryFixture.card(StoryTable.Kind.CONTRACT)
	hidden.rep_interaction = &"rep.call_bluff"
	var a: int = _post(w, seen)
	var b: int = _post(w, hidden)
	var rows: Array = CommsView.block(w, 0)["cards"]
	assert_int(rows.size()).is_equal(2)
	assert_int(rows[a]["reward"]).is_equal(250)
	assert_bool(rows[a]["rep_vis"]).is_true()
	assert_float(rows[a]["rep_lo"]).is_equal(4.0)
	assert_float(rows[a]["rep_hi"]).is_equal(12.0)
	assert_float(rows[a]["expires"]).is_equal_approx(90.0, 0.1)
	assert_bool(rows[b]["rep_vis"]).is_false()
	assert_float(rows[b]["expires"]).is_equal(-1.0)
	assert_str(rows[a]["title"]).is_equal("comms.card.offer")
	assert_int(rows[b]["claimer"]).is_equal(-1)
	var claimed: Array = CommsView.block(w, 0, null, {"npc:1": [7, "Ana"]})["cards"]
	assert_int(claimed[1]["claimer"]).is_equal(7)
	var decline: DeclineCardCommand = DeclineCardCommand.new()
	decline.card = a
	assert_bool(StoryFixture.run(w, 0, decline)).is_true()
	assert_int(CommsView.block(w, 0)["cards"][a]["state"]).is_equal(StoryTable.State.DECLINED)
	assert_int(CommsView.block(w, 1 if w.ship_count() > 1 else 0)["cards"].size()).is_equal(2)


# FT: FT-COM-007, FT-COM-008
# An open conversation shows its NPC line and replies; a reply that needs a scan fact is
# disabled until the fact is in, and carries the science icon only where verify_chip is
# granted (P14).
func test_open_node_and_verify_icon() -> void:
	var w: SimWorld = _docked()
	StoryFixture.spawn(w, TestDefs.raider(), StoryFixture.RED, Vector3(0.0, 0.0, -5000.0))
	w.step()
	var hail: HailCommand = HailCommand.new()
	hail.target = 1
	assert_bool(StoryFixture.run(w, 0, hail)).is_true()
	var easy: ViewFilter = ViewFilter.of("comms", "easy")
	var hard: ViewFilter = ViewFilter.of("comms", "hard")
	var nodes: Array = CommsView.block(w, 0, easy)["nodes"]
	assert_int(nodes.size()).is_equal(1)
	assert_str(nodes[0]["line"]).is_equal("npc.hail_trader")
	var options: Array = nodes[0]["options"]
	assert_int(options.size()).is_equal(4)
	assert_bool(options[2]["enabled"]).is_false()
	assert_bool(options[2]["verify"]).is_false()
	assert_bool(options[0]["enabled"]).is_true()
	# Easy and the shortcut shared: Science's icon shows on the option that needs a fact.
	var shared: ViewFilter = ViewFilter.of("comms", "easy#verify_chip")
	assert_bool(CommsView.block(w, 0, shared)["nodes"][0]["options"][2]["verify"]).is_true()
	assert_bool(CommsView.block(w, 0, hard)["nodes"][0]["options"][2]["verify"]).is_false()
	Story.learn_fact(w, BLUE, 1, "cargo")
	assert_bool(CommsView.block(w, 0, shared)["nodes"][0]["options"][2]["enabled"]).is_true()


# FT: FT-COM-004, FT-COM-009, FT-MIS-036
# Docked at an offer card's site the block lists the market's goods with their sale price
# and caps, the dock repairs, and each module for each slot of its type with the trade-in
# of what is fitted; undocked it lists none, and the fitted modules are always listed.
func test_offers_and_trade_in_lines() -> void:
	var w: SimWorld = _docked()
	_post(w, StoryFixture.card(StoryTable.Kind.OFFER, &"", SITE))
	var block: Dictionary = CommsView.block(w, 0)
	assert_bool(block["docked"]).is_true()
	assert_int(block["site"]).is_equal(SITE)
	assert_int(block["credits"]).is_equal(2000)
	var items: Array = block["offers"].map(func(o: Dictionary) -> String: return o["item"])
	assert_array(items).is_equal(
		[
			"ammo:m1_cannon",
			"parts",
			"probes",
			"propellant",
			"repair:engines",
			"repair:sensors",
			"repair:thrusters",
			"repair:weapons"
		]
	)
	var parts: Dictionary = block["offers"][1]
	assert_int(parts["price"]).is_equal(25)
	assert_int(parts["sell"]).is_equal(12)
	assert_int(parts["stock"]).is_equal(20)
	var engine: Array = block["modules"].filter(func(m: Dictionary) -> bool: return m["slot"] == 0)
	(
		assert_array(engine.map(func(m: Dictionary) -> String: return m["module"]))
		. is_equal(["hx2_afterburner", "bx3_reactor"])
	)
	assert_int(engine[0]["trade_in"]).is_equal(0)
	ModuleSystem.fit(w, 0, 0, load("res://content/modules/hx2_afterburner.tres") as ModuleDef)
	block = CommsView.block(w, 0)
	var swap: Dictionary = block["modules"][1]
	assert_str(swap["module"]).is_equal("bx3_reactor")
	assert_str(swap["old"]).is_equal("hx2_afterburner")
	assert_int(swap["trade_in"]).is_equal(450)
	(
		assert_array(block["fitted"].map(func(f: Dictionary) -> String: return f["module"]))
		. is_equal(["hx2_afterburner", ""])
	)
	StoryFixture.dock(w, 0, 9)
	block = CommsView.block(w, 0)
	assert_bool(block["docked"]).is_true()
	assert_array(block["offers"]).is_empty()
	assert_array(block["modules"]).is_empty()
	assert_int(block["fitted"].size()).is_equal(2)


# FT: FT-PAIR-010, FT-NET-040
# The hull is a band at every damage level, and the board built from the net thread's copy
# of the world (SimCopy) equals the one from the world itself.
func test_hull_band_and_the_copy_matches() -> void:
	var w: SimWorld = _docked()
	_post(w, StoryFixture.card(StoryTable.Kind.OFFER, &"", SITE))
	var hull: int = w.damage.hull_row(0)
	var max_hull: float = w.defs[0].hull_max
	for pair: Array in [[1.0, 0], [0.6, 1], [0.4, 2], [0.1, 3]]:
		w.damage.health[hull] = max_hull * pair[0]
		assert_int(CommsView.block(w, 0)["hull_band"]).is_equal(pair[1])
	var copy: SimWorld = SimCopy.of(w)
	assert_dict(CommsView.block(copy, 0)).is_equal(CommsView.block(w, 0))
	var bytes: PackedByteArray = NetBlock.encode(CommsView.SCHEMA, CommsView.block(w, 0))
	var back: Dictionary = NetBlock.decode(CommsView.SCHEMA, bytes)
	assert_int(back["credits"]).is_equal(2000)
	assert_str(back["offers"][1]["item"]).is_equal("parts")
	assert_int(back["cards"].size()).is_equal(1)
