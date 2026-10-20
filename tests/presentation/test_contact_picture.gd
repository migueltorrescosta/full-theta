extends GdUnitTestSuite
## ContactPicture: radar items from the interpolated snapshot and the crew model.


func _ctx() -> StationContext:
	var ctx: StationContext = StationContext.new()
	ctx.clock = func() -> int: return 1000
	ctx.crew.ship = 0
	var v: NetViewState = NetViewState.new(0)
	v.tick = 100
	# Own ship at the origin, yawed 90° to port: world -X is its bow.
	v.kin = {"site": 0, "pos": Vector3i.ZERO, "rot": Quaternion(Vector3.UP, PI / 2.0)}
	v.contacts = {
		"model":
		{
			0: [Vector3i.ZERO, Vector3i.ZERO, 100],
			1: [Vector3i(-16000, 0, 0), Vector3i.ZERO, 100],
			2: [Vector3i(0, 1600, 0), Vector3i.ZERO, 100],
		},
		"info":
		{
			0: [ContactsSection.FLAG_OWN, "Kestrel"],
			1: [1, "H1"],
			2: [ContactsSection.FLAG_OWN, "Osprey"],
		},
	}
	ctx.view = v
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
