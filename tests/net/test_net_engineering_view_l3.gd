extends GdUnitTestSuite
## Engineering sees no threat positions beyond the radar (FT-ENG-007): real snapshots
## from a server over loopback, while Helm, on the same ship, gets ship models and
## tracers. Engineering's positions are its own ship (KIN) and the radar's contacts
## (CONTACTS) only; its ENGINEERING block holds no position.

const PLAYER: int = NetHarness.PLAYER
const S = StationViews.Section

var h: NetHarness


func before_test() -> void:
	h = NetHarness.new(self)


func after_test() -> void:
	await h.free_all()


# FT: FT-ENG-007, FT-NET-009
func test_engineering_gets_no_near_or_projectiles_and_only_radar_contacts() -> void:
	var server: NetServer = h.server()
	var helm: NetClient = await h.joined(server, "helm", "helm")
	var weapons: NetClient = await h.joined(server, "weapons", "weapons")
	var eng: NetClient = await h.joined(server, "engineering", "engineering")
	server.session.launch(PLAYER)
	eng.keep_raw = true
	weapons.fire()
	# Helm sees the shot as a tracer: there is something Engineering could have seen.
	(
		assert_bool(await h.until(func() -> bool: return not helm.view.projectiles.is_empty()))
		. is_true()
	)
	await h.wait(300)
	assert_int(eng.view.rejected).is_equal(0)
	assert_int(eng.raw_snapshots.size()).is_greater(3)
	for seq: int in eng.raw_snapshots:
		var data: PackedByteArray = eng.raw_snapshots[seq]
		var n: int = data[SnapshotBuilder.HEADER_BYTES - 1]
		var at: int = SnapshotBuilder.HEADER_BYTES
		for i: int in n:
			assert_array([S.NEAR, S.PROJECTILES]).not_contains([int(data[at])])
			at += 3 + data.decode_u16(at + 1)
	assert_array(eng.view.kinds).not_contains([S.NEAR, S.PROJECTILES])
	assert_dict(eng.view.near).is_empty()
	assert_dict(eng.view.projectiles).is_empty()
	# The contacts it holds are the radar's: the same section Helm's radar draws.
	var ids: Callable = func(c: NetClient) -> Array:
		var out: Array = c.view.contacts.get("model", {}).keys()
		out.sort()
		return out
	assert_array(ids.call(eng)).is_equal(ids.call(helm))
	# No ENGINEERING field is a position; the one vector is the own shield focus.
	var block: Dictionary = eng.view.blocks[S.ENGINEERING]
	for key: String in block:
		if block[key] is Vector3:
			assert_str(key).is_equal("shield_focus")
			assert_float((block[key] as Vector3).length()).is_equal_approx(1.0, 0.01)
