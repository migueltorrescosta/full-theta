extends GdUnitTestSuite
## ContactPicture: radar items from the interpolated snapshot and the crew model.


func _ctx() -> StationContext:
	var ctx: StationContext = StationContext.new()
	ctx.clock = func() -> int: return 1000
	ctx.crew.ship = 0
	var v: SnapshotState = SnapshotState.new(0)
	v.tick = 100
	# Own ship at the origin, yawed 90° to port: world -X is its bow.
	v.kin = {"pos": Vector3i.ZERO, "rot": Quaternion(Vector3.UP, PI / 2.0)}
	v.contacts = {
		"model":
		{
			0: [Vector3i.ZERO, Vector3i.ZERO, 100],
			1: [Vector3i(-16000, 0, 0), Vector3i.ZERO, 100],
			2: [Vector3i(0, 1600, 0), Vector3i.ZERO, 100],
		},
		"info":
		{
			0: [SnapshotReader.FLAG_OWN, "Kestrel"],
			1: [1, "H1"],
			2: [SnapshotReader.FLAG_OWN, "Osprey"],
		},
	}
	ctx.snap = v
	ctx.interp.push(v, 0)
	return ctx


# FT: FT-STN-002, FT-SPA-001
func test_contacts_in_ship_frame_with_allegiance() -> void:
	var items: Array[Dictionary] = ContactPicture.build(_ctx()).items
	assert_int(items.size()).is_equal(2)
	var h1: Dictionary = items[0]
	assert_str(h1["label"]).is_equal("H1")
	assert_str(h1["allegiance"]).is_equal("H")
	# 1 km along world -X is dead ahead of the yawed ship.
	assert_vector(h1["local"]).is_equal_approx(Vector3(0, 0, -1000), Vector3.ONE * 0.01)
	assert_vector(h1["world"]).is_equal_approx(Vector3(-1000, 0, 0), Vector3.ONE * 0.01)
	# An own-faction ship by name counts as friendly; the own ship is not an item.
	assert_str(items[1]["label"]).is_equal("Osprey")
	assert_str(items[1]["allegiance"]).is_equal("F")


# FT: FT-SPA-014, FT-SPA-016
func test_marks_and_pings() -> void:
	var ctx: StationContext = _ctx()
	var marks: Array = [
		{"slot": 0, "name": "Alpha", "x": 0, "y": 0, "z": 500},
		{"slot": 1, "name": "Bravo", "contact": 1, "x": 0, "y": 100, "z": 0},
	]
	ctx.crew.handle_event({"type": "marks", "payload": {"ship": 0, "marks": marks}}, 1000)
	ctx.crew.handle_event(
		{"type": "ping", "payload": {"ship": 0, "kind": "contact", "id": 1}}, 1000
	)
	ctx.crew.handle_event({"type": "ping", "payload": {"ship": 0, "kind": "point", "x": 50}}, 1000)
	var items: Array[Dictionary] = ContactPicture.build(ctx).items
	var by_label: Dictionary = {}
	for it: Dictionary in items:
		by_label[it["label"]] = it
	assert_float(by_label["H1"]["pulse"]).is_equal(1.0)
	assert_str(by_label["Alpha"]["kind"]).is_equal("mark")
	# World +Z is the ship's port side (9 o'clock).
	assert_vector(by_label["Alpha"]["local"]).is_equal_approx(
		Vector3(-500, 0, 0), Vector3.ONE * 0.01
	)
	# Bravo is attached to H1: it follows the contact.
	assert_vector(by_label["Bravo"]["local"]).is_equal_approx(
		Vector3(0, 100, -1000), Vector3.ONE * 0.01
	)
	assert_str(by_label[""]["kind"]).is_equal("point")
	assert_float(by_label[""]["pulse"]).is_equal(1.0)


# FT: FT-STN-002
func test_context_builds_the_picture_once_and_again_on_change() -> void:
	var ctx: StationContext = _ctx()
	var first: ContactPicture = ctx.picture()
	assert_object(ctx.picture()).is_same(first)
	var marks: Array = [{"slot": 0, "x": 0, "y": 0, "z": 500}]
	ctx.crew.handle_event({"type": "marks", "payload": {"ship": 0, "marks": marks}}, 1000)
	var second: ContactPicture = ctx.picture()
	assert_object(second).is_not_same(first)
	assert_int(second.items.size()).is_equal(first.items.size() + 1)


# FT: FT-RLY-004, FT-SCI-005
# Deployed probes (the RELAY block, which Science gets too) show as zone items with their
# bubble radius; a probe still flying does not.
func test_deployed_probes_show_their_bubble() -> void:
	var ctx: StationContext = _ctx()
	ctx.snap.blocks[StationCatalogue.Section.RELAY] = {
		"probes":
		[
			{"serial": 0, "deployed": true, "pos": Vector3(0, 0, -3000), "range": 8000.0},
			{"serial": 1, "deployed": false, "pos": Vector3(0, 0, -1000), "range": 8000.0},
		]
	}
	var zones: Array = ContactPicture.build(ctx).items.filter(
		func(it: Dictionary) -> bool: return it["kind"] == "zone"
	)
	assert_int(zones.size()).is_equal(1)
	assert_str(zones[0]["zone"]).is_equal("probe")
	assert_float(zones[0]["radius"]).is_equal(8000.0)


# FT: FT-STN-002
func test_contacts_by_range_sorts_once_and_copies() -> void:
	var pic: ContactPicture = ContactPicture.build(_ctx())
	var near: Array[Dictionary] = pic.contacts_by_range()
	(
		assert_array(near.map(func(it: Dictionary) -> String: return it["label"]))
		. is_equal(["Osprey", "H1"])
	)
	# The first call fills the cache; later calls and limits read it.
	(
		assert_array(pic.contacts_by_range(1).map(func(it: Dictionary) -> int: return it["id"]))
		. is_equal([2])
	)
	assert_array(pic.contacts_by_range(9)).has_size(2)
	# A caller reordering its copy leaves the picture's order alone.
	near.reverse()
	assert_int(pic.contacts_by_range()[0]["id"]).is_equal(2)
	# Marks and points are not contacts.
	var items: Array[Dictionary] = pic.items
	items.append({"kind": "mark", "id": 0, "label": "A", "local": Vector3.ZERO})
	assert_array(pic.contacts_by_range()).has_size(2)


# FT: FT-SPA-003
func test_chip_of_is_composed_once_and_follows_a_moved_item() -> void:
	var pic: ContactPicture = ContactPicture.build(_ctx())
	var it: Dictionary = pic.items[0]
	var chip: String = ContactPicture.chip_of(it)
	assert_str(chip).is_equal(ChipText.chip(it["label"], it["local"]))
	assert_str(it["chip_text"]).is_equal(chip)
	# Planted text is what the cache answers while the item is unchanged ...
	it["chip_text"] = "cached"
	assert_str(ContactPicture.chip_of(it)).is_equal("cached")
	# ... and a new offset or label composes it again.
	it["local"] = Vector3(0, 0, -9000)
	assert_str(ContactPicture.chip_of(it)).is_equal(ChipText.chip(it["label"], it["local"]))


# FT: FT-STN-002
func test_the_picture_cache_sees_a_mark_edited_in_place_but_copies_nothing() -> void:
	var ctx: StationContext = _ctx()
	var marks: Array = [{"slot": 0, "name": "Alpha", "x": 0, "y": 0, "z": 500}]
	ctx.crew.handle_event({"type": "marks", "payload": {"ship": 0, "marks": marks}}, 1000)
	var first: ContactPicture = ctx.picture()
	assert_object(ctx.picture()).is_same(first)
	# The key holds hashes, not copies of the model.
	for part: Variant in ctx._picture_key:
		assert_bool(part is Array or part is Dictionary).is_false()
	ctx.crew.marks[0]["name"] = "Alfa"
	var second: ContactPicture = ctx.picture()
	assert_object(second).is_not_same(first)
	(
		assert_bool(second.items.any(func(it: Dictionary) -> bool: return it["label"] == "Alfa"))
		. is_true()
	)


# FT: FT-RLY-001
func test_mark_label_names_the_contact_a_mark_is_attached_to() -> void:
	var ctx: StationContext = _ctx()
	assert_str(ChipText.mark_label({"name": "Alpha", "contact": -1}, ctx.snap)).is_equal("Alpha")
	assert_str(ChipText.mark_label({"name": "Alpha"}, ctx.snap)).is_equal("Alpha")
	assert_str(ChipText.mark_label({"name": "Bravo", "contact": 1}, ctx.snap)).is_equal(
		"Bravo · H1"
	)
