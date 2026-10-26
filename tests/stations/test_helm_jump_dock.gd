extends HelmSuite
## Helm's jump and dock (#10): named sites are selectable like contacts, show on the
## compass and the HUD, J jumps to the selected site or mark once it is faced, H docks at
## the selected dockable site and undocks when docked, and the spool shows in the read-out.
## The fixture's ship has its own yawed, pitched and rolled frame; site 5 is 20 km dead
## ahead, site 6 the same off to the side, site 0 Kestrel Yard at the origin.

const AHEAD: int = 5
const ASIDE: int = 6


func before_test() -> void:
	await super.before_test()
	var q: Quaternion = StationFixture.own_rotation()
	_ctx().view.sites = [
		_site(0, "Kestrel Yard", StationFixture.OWN_POS + q * Vector3(0, 0, 10000.0), true),
		_site(AHEAD, "Vesper", StationFixture.OWN_POS + q * Vector3(0, 0, -20000.0), true),
		_site(ASIDE, "Cinder", StationFixture.OWN_POS + q * Vector3(20000.0, 0, 0), false),
	]
	_ctx().interp.revision += 1


func _site(id: int, name_key: String, pos: Vector3, dockable: bool) -> Dictionary:
	return {
		"id": id,
		"name_key": name_key,
		"kind": &"station" if dockable else &"nav",
		"dockable": dockable,
		"radius": 3000.0,
		"pos": pos,
	}


func _toasts() -> Array:
	var out: Array = []
	_ctx().crew.toast.connect(func(key: String, _a: Dictionary) -> void: out.append(key))
	return out


# FT: FT-HLM-016, FT-SPA-015
# A site is selectable like a contact: the picture lists it with its offset, the compass
# dot is filled for the site ahead and hollow behind, and selecting it sends
# helm_select_target with the site id and no ship or point.
func test_a_site_is_selectable_and_shows_on_the_compass() -> void:
	var sites: Array[Dictionary] = _ctx().picture().sites
	assert_int(sites.size()).is_equal(3)
	assert_str(sites[1]["label"]).is_equal("Vesper")
	_ctx().crew.select("site", AHEAD)
	var local: Vector3 = _ctx().selection_local()
	assert_float(local.length()).is_equal_approx(20000.0, 1.0)
	assert_bool(HelmHud.compass_filled(local)).is_true()
	assert_float(local.normalized().angle_to(Vector3.FORWARD)).is_less(0.001)
	_frame()
	var t: Dictionary = _cmds("helm_select_target").back()
	assert_int(t["site_id"]).is_equal(AHEAD)
	assert_int(t["target_ship"]).is_equal(-1)
	assert_bool(t["point"]).is_false()
	_ctx().crew.select("site", ASIDE)
	assert_bool(HelmHud.compass_filled(_ctx().selection_local())).is_true()
	_ctx().crew.select("site", 0)
	assert_bool(HelmHud.compass_filled(_ctx().selection_local())).is_false()
	var kinds: Array = _panel.hud.markers().map(func(e: Dictionary) -> String: return e["kind"])
	assert_array(kinds).contains(["site"])


# FT: FT-HLM-013, FT-HLM-016
# J with a faced site sends helm_jump to it (site id, kind SITE); with the site off the
# bow, or with nothing or a contact selected, it sends nothing and toasts why.
func test_j_jumps_to_the_selected_site_once_faced() -> void:
	var toasts: Array = _toasts()
	_tap_key("J")
	assert_array(_cmds("helm_jump")).is_empty()
	assert_array(toasts).contains(["toast.jump_select"])
	_ctx().crew.select("contact", StationFixture.H2)
	_tap_key("J")
	assert_array(_cmds("helm_jump")).is_empty()
	_ctx().crew.select("site", ASIDE)
	_tap_key("J")
	assert_array(_cmds("helm_jump")).is_empty()
	assert_array(toasts).contains(["toast.jump_face"])
	_ctx().crew.select("site", AHEAD)
	_tap_key("J")
	assert_int(_cmds("helm_jump").size()).is_equal(1)
	var j: Dictionary = _cmds("helm_jump")[0]
	assert_int(j["target_kind"]).is_equal(0)
	assert_int(j["target_id"]).is_equal(AHEAD)
	# The controller has it on the radial.
	_radial("jump")
	assert_int(_cmds("helm_jump").size()).is_equal(2)


# FT: FT-HLM-013, FT-HLM-016
# A free mark is a jump target too (kind MARK, its point) once it is faced: Bravo, off the
# bow, is refused with a toast; a mark 20 km dead ahead goes.
func test_j_jumps_to_a_selected_mark() -> void:
	var toasts: Array = _toasts()
	_ctx().crew.select("mark", StationFixture.BRAVO_SLOT)
	_tap_key("J")
	assert_array(_cmds("helm_jump")).is_empty()
	assert_array(toasts).contains(["toast.jump_face"])
	var q: Quaternion = StationFixture.own_rotation()
	var ahead: Vector3 = StationFixture.OWN_POS + q * Vector3(0, 0, -20000.0)
	_ctx().crew.handle_event(
		{
			"type": "marks",
			"payload":
			{
				"ship": StationFixture.SHIP,
				"marks":
				[
					{
						"slot": 3,
						"name": "Fore",
						"contact": -1,
						"x": ahead.x,
						"y": ahead.y,
						"z": ahead.z,
						"by": "Ana"
					}
				]
			}
		},
		StationFixture.NOW_MS
	)
	_ctx().crew.select("mark", 3)
	_tap_key("J")
	var j: Dictionary = _cmds("helm_jump").back()
	assert_int(j["target_kind"]).is_equal(1)
	assert_float(Vector3(j["x"], j["y"], j["z"]).distance_to(ahead)).is_less(1.0)


# FT: FT-HLM-013
# H docks at the selected dockable site, refuses a site that can't be docked at or a
# non-site with a toast, and undocks when the HELM block says the ship is docked; the
# controller radial has both.
func test_h_docks_and_undocks() -> void:
	var toasts: Array = _toasts()
	_tap_key("H")
	assert_array(_cmds("helm_dock")).is_empty()
	assert_array(toasts).contains(["toast.dock_select"])
	_ctx().crew.select("site", ASIDE)
	_tap_key("H")
	assert_array(_cmds("helm_dock")).is_empty()
	_ctx().crew.select("site", AHEAD)
	_tap_key("H")
	assert_int(_cmds("helm_dock").back()["site_id"]).is_equal(AHEAD)
	_helm_block()["docked_site"] = AHEAD
	_tap_key("H")
	assert_int(_cmds("helm_undock").size()).is_equal(1)
	_radial("dock")
	assert_int(_cmds("helm_undock").size()).is_equal(2)


# FT: FT-HLM-013, FT-HLM-016
# The HELM block's jump_left and docked_site reach the panel (the HUD read-out turns the
# ticks into seconds), and the radial no longer reserves dock and jump.
func test_spool_and_docked_state_reach_the_panel() -> void:
	_helm_block()["jump_left"] = 150
	_helm_block()["docked_site"] = AHEAD
	_frame()
	assert_int(_panel.helm_block()["jump_left"]).is_equal(150)
	assert_float(float(_panel.helm_block()["jump_left"]) / NetCodec.TICK_HZ).is_equal(2.5)
	assert_str(tr("helm.jump_spool") % 2.5).is_equal("JUMP in 2.5 s")
	assert_array(HelmPanel.RADIAL).contains(["dock", "jump"])


func _helm_block() -> Dictionary:
	return _ctx().view.blocks[StationViews.Section.HELM]
