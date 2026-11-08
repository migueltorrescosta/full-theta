extends GdUnitTestSuite
## WeaponsAim and WeaponsReadout (R13-7) without a scene: a panel set up on the station
## fixture but never added to the tree. The fixture's corvette has one bow mount (15 degree
## half-arc); its MOUNTS row reads 6 heat of 40 and 380 of 400 rounds.

const SETTINGS: String = "user://test_weapons_aim.cfg"


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _panel(mine: bool = true) -> WeaponsPanel:
	var ctx: StationContext = StationFixture.context("weapons", SETTINGS)
	if mine:
		ctx.crew.claims["mount:0"] = {"session": StationFixture.SESSION, "name": "Ana"}
	var p: WeaponsPanel = auto_free(WeaponsPanel.new())
	p.setup(ctx, "weapons")
	return p


func _aims_sent(p: WeaponsPanel) -> Array:
	var out: Array = []
	for c: Array in StationFixture.sent(p.ctx).of("command"):
		if c[1][0]["kind"] == "aim_mount":
			out.append(c[1][0])
	return out


func test_turn_toward_stops_at_the_angle() -> void:
	var to: Vector3 = Vector3(1, 0, -1).normalized()
	assert_vector(WeaponsAim.turn_toward(Vector3.FORWARD, to, 1.0)).is_equal(to)
	var part: Vector3 = WeaponsAim.turn_toward(Vector3.FORWARD, Vector3.RIGHT, 0.25)
	assert_float(Vector3.FORWARD.angle_to(part)).is_equal_approx(0.25, 1e-5)
	assert_float(part.x).is_greater(0.0)
	# Opposite directions still turn (about an axis off `from`).
	var back: Vector3 = WeaponsAim.turn_toward(Vector3.FORWARD, Vector3.BACK, 0.5)
	assert_float(Vector3.FORWARD.angle_to(back)).is_equal_approx(0.5, 1e-5)


# FT: FT-WPN-009
func test_aim_points_send_once_when_moved() -> void:
	var p: WeaponsPanel = _panel()
	var aim: WeaponsAim = p.aim
	var dir: Vector3 = aim.aim_dir(0)
	aim.set_aim_dir(0, dir)
	assert_bool(aim.dirty.has(0)).is_true()
	aim.flush(StationFixture.NOW_MS, false)
	assert_int(_aims_sent(p).size()).is_equal(1)
	assert_bool(aim.dirty.is_empty()).is_true()
	assert_vector(aim.aim_dir(0)).is_equal_approx(dir, Vector3.ONE * 1e-4)
	# The same point again is not news; a moved one waits AIM_SEND_MS unless forced.
	aim.set_aim_dir(0, dir)
	assert_bool(aim.dirty.is_empty()).is_true()
	aim.set_aim_dir(0, dir.rotated(Vector3.UP, 0.05))
	aim.flush(StationFixture.NOW_MS + 1, false)
	assert_int(_aims_sent(p).size()).is_equal(1)
	aim.flush(StationFixture.NOW_MS + 1, true)
	assert_int(_aims_sent(p).size()).is_equal(2)


# FT: FT-SIM-011, FT-WPN-009
func test_aim_stops_at_the_arc_edge() -> void:
	var p: WeaponsPanel = _panel()
	var rot: Quaternion = p.ctx.interp.own_rotation()
	var m: MountDef = p.ship_def.mounts[0]
	assert_bool(p.aim.in_arc(0, rot * m.forward)).is_true()
	assert_bool(p.aim.in_arc(0, rot * -m.forward)).is_false()
	p.aim.aim_within_arc(0, rot * Vector3.RIGHT)
	var local: Vector3 = rot.inverse() * p.aim.aim_dir(0)
	assert_float(m.forward.angle_to(local)).is_equal_approx(m.arc_half_angle, 1e-3)


# FT: FT-WPN-004
func test_readout_mount_list_and_state() -> void:
	var p: WeaponsPanel = _panel()
	assert_str(WeaponsReadout.mount_state(p, 0)).is_equal("ready")
	assert_array(WeaponsReadout.mount_rows(p)).is_equal(
		["> 1 bow · ready · heat 15% · 380/400 · you"]
	)
	p.ctx.view.blocks[StationViews.Section.MOUNTS]["mounts"][0]["ammo"] = 0
	assert_str(WeaponsReadout.mount_state(p, 0)).is_equal("empty")
	var free: WeaponsPanel = _panel(false)
	assert_str(WeaponsReadout.mount_rows(free)[0]).ends_with("· free")
	assert_str(WeaponsReadout.ammo_text(free)).starts_with("Ammo: ")


# FT: FT-WPN-005
func test_readout_clock_words() -> void:
	assert_str(WeaponsReadout.clock_words(Vector3.FORWARD)).is_equal("12 level")
	assert_str(WeaponsReadout.clock_words(Vector3(1, 1, 0))).is_equal("3 high")
