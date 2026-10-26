extends GdUnitTestSuite
## Weapons (T052): the turret panel on the station fixture, driven through intents and
## the input matcher, with a recording client. The fixture's corvette has one bow mount
## (15 degree half-arc, 0.5 rad/s traverse, 1500 m/s shots, 0.5 s cooldown).


func before() -> void:
	I18n.apply("en")


func _screen(claims: Dictionary = {"mount:0": StationFixture.SESSION}) -> StationScreen:
	var ctx: StationContext = StationFixture.context("weapons", "user://test_weapons_panel.cfg")
	for item: String in claims:
		var who: int = claims[item]
		ctx.crew.claims[item] = {"session": who, "name": "Ana" if who == ctx.crew.session else "Bo"}
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	add_child(s)
	_panel(s).set_process(false)
	return s


func _panel(s: StationScreen) -> WeaponsPanel:
	return s.panels[0] as WeaponsPanel


func _ev(s: StationScreen, id: String, device: String = "kbm", pressed: bool = true) -> Dictionary:
	return {
		"id": id,
		"group": IntentTable.row(id)["group"],
		"target": IntentTable.target(id, device, s.focused_station(), s.stations),
		"kind": IntentTable.row(id)["kind"],
		"pressed": pressed,
		"value": 1.0,
		"device": device,
	}


func _commands(s: StationScreen, kind: String) -> Array:
	var out: Array = []
	for c: Array in StationFixture.sent(s.ctx).of("command"):
		if c[1][0]["kind"] == kind:
			out.append(c[1][0])
	return out


## Moves contact `id` to a ship-frame offset, with a world velocity (m/s).
func _place(ctx: StationContext, id: int, local: Vector3, vel: Vector3 = Vector3.ZERO) -> void:
	var p: Vector3 = StationFixture.OWN_POS + StationFixture.own_rotation() * local
	var model: Dictionary = ctx.view.contacts["model"]
	model[id] = [
		NetCodec.quant_pos(p.x, p.y, p.z, ctx.view.p_units),
		NetCodec.quant_vel(vel),
		StationFixture.TICK
	]
	_repush(ctx)


## Sets the own ship's orientation in the snapshot and the interpolator.
func _turn_ship(ctx: StationContext, rot: Quaternion) -> void:
	ctx.view.kin["rot"] = rot
	_repush(ctx)


func _repush(ctx: StationContext) -> void:
	ctx.interp = SnapshotInterpolator.new()
	ctx.interp.p_units = ctx.view.p_units
	ctx.interp.push(ctx.view, StationFixture.NOW_MS - 100)
	ctx.interp.push(ctx.view, StationFixture.NOW_MS)
	ctx.interp.update(StationFixture.NOW_MS)


func _bearing(clock_deg: float, el_deg: float, range_m: float) -> Vector3:
	var b: float = deg_to_rad(clock_deg)
	var e: float = deg_to_rad(el_deg)
	return Vector3(sin(b) * cos(e), sin(e), -cos(b) * cos(e)) * range_m


# FT: FT-WPN-001, FT-WPN-002, FT-WPN-004, FT-WPN-006, FT-SIM-014, FT-M1-004
# The Weapons screen is the turret panel with the screen's disc radar as its inset; the
# mount list shows state, heat, ammo and claimer; the lead reticle is Lead's aim point;
# the corvette's mount carries four ammo types (D220), so ammo select sends the next one.
func test_turret_mount_list_lead_and_ammo() -> void:
	var s: StationScreen = _screen()
	await await_idle_frame()
	var p: WeaponsPanel = _panel(s)
	assert_object(p).is_not_null()
	assert_bool(p.focused).is_true()
	assert_bool(s.radar.is_visible_in_tree()).is_true()
	assert_int(p.mount_count()).is_equal(1)
	assert_array(p.mount_rows()).is_equal(["> 1 bow · ready · heat 15% · 380/400 · you"])
	s.ctx.crew.claims["mount:0"] = {"session": 99, "name": "Bo"}
	assert_str(p.mount_rows()[0]).ends_with("· Bo")
	s.ctx.crew.claims.erase("mount:0")
	assert_str(p.mount_rows()[0]).ends_with("· free")
	(s.ctx.view.blocks[StationViews.Section.MOUNTS]["mounts"][0] as Dictionary)["heat"] = 40.0
	assert_str(p.mount_rows()[0]).contains("hot")
	# Lead: a contact crossing at 200 m/s, 2 km ahead.
	var vel: Vector3 = StationFixture.own_rotation() * Vector3(200.0, 0.0, 0.0)
	_place(s.ctx, StationFixture.H2, Vector3(0.0, 0.0, -2000.0), vel)
	s.ctx.crew.select("contact", StationFixture.H2)
	var rel: Vector3 = (
		s.ctx.interp.offset_to(s.ctx.interp.contact_position(StationFixture.H2))
		- StationFixture.own_rotation() * Vector3(0, 0, -22)
	)
	var t: float = Lead.intercept_time(rel, vel, 1500.0)
	var want: Vector3 = Lead.aim_point(rel, vel, t).normalized()
	assert_vector(p.lead_dir(0, StationFixture.H2) as Vector3).is_equal_approx(
		want, Vector3.ONE * 1e-4
	)
	p.step(0.016)
	assert_object(p.project(want)).is_not_null()
	# Ammo select: the next type, no toast.
	var toasts: Array = []
	s.ctx.crew.toast.connect(func(k: String, _a: Dictionary) -> void: toasts.append(k))
	assert_bool(s.dispatch(_ev(s, "ammo_next"))).is_true()
	assert_array(toasts).is_empty()
	var switched: Array = _commands(s, "set_ammo_type")
	assert_int(switched.size()).is_equal(1)
	assert_int(int(switched[0]["ammo_type"])).is_equal(1)


# FT: FT-WPN-003, FT-WPN-004
# Camera swap cycles the mounts this player holds (1 to 4 jump, d-pad next/previous);
# a mount held by someone else is skipped; K / View+X claims or releases the camera
# mount.
func test_swap_between_claimed_mounts_and_claim() -> void:
	var s: StationScreen = _screen({"mount:0": StationFixture.SESSION, "mount:1": 99})
	var p: WeaponsPanel = _panel(s)
	var def: ShipDef = p.ship_def.duplicate()
	var mounts: Array[MountDef] = [def.mounts[0], def.mounts[0], def.mounts[0]]
	def.mounts = mounts
	p.ship_def = def
	s.ctx.crew.claims["mount:2"] = {"session": StationFixture.SESSION, "name": "Ana"}
	assert_int(p.mount).is_equal(0)
	s.dispatch(_ev(s, "mount_next", "pad"))
	assert_int(p.mount).is_equal(2)
	s.dispatch(_ev(s, "mount_next", "pad"))
	assert_int(p.mount).is_equal(0)
	s.dispatch(_ev(s, "mount_prev", "pad"))
	assert_int(p.mount).is_equal(2)
	s.dispatch(_ev(s, "mount_2"))
	assert_int(p.mount).is_equal(2)
	s.dispatch(_ev(s, "mount_1"))
	assert_int(p.mount).is_equal(0)
	assert_str(p.mount_rows()[1]).ends_with("· Bo")
	s.dispatch(_ev(s, "claim"))
	assert_array(StationFixture.sent(s.ctx).of("release_claim")).is_equal(
		[["release_claim", ["mount:0"]]]
	)
	s.ctx.crew.claims.erase("mount:0")
	s.dispatch(_ev(s, "claim", "pad"))
	assert_array(StationFixture.sent(s.ctx).of("claim")).is_equal([["claim", ["mount:0"]]])


# FT: FT-WPN-005, FT-M1-008
# Out of arc, the line gives the clock and height to turn the bow to; in arc, nothing.
func test_out_of_arc_gives_the_turn_direction() -> void:
	var s: StationScreen = _screen()
	var p: WeaponsPanel = _panel(s)
	assert_str(p.out_of_arc_text()).is_equal("")
	s.ctx.crew.select("contact", StationFixture.H2)
	assert_str(p.out_of_arc_text()).is_equal("H2 out of arc: turn 4 high")
	s.ctx.crew.select("contact", StationFixture.U3)
	assert_str(p.out_of_arc_text()).is_equal("U3 out of arc: turn 11 high")
	_place(s.ctx, StationFixture.U3, _bearing(-50.0, -10.0, 3000.0))
	assert_str(p.out_of_arc_text()).is_equal("U3 out of arc: turn 10 level")
	_place(s.ctx, StationFixture.U3, _bearing(8.0, 5.0, 3000.0))
	assert_str(p.out_of_arc_text()).is_equal("")


# FT: FT-WPN-009, FT-WPN-001, FT-M1-008
# Mouse aim sends one aim point; when the ship then yaws and rolls, the camera keeps the
# same world direction (no new aim needed), its up stays on the ship's deck plane, and
# in the sim the barrel slews to that held point at the traverse rate.
func test_aim_holds_in_world_while_the_ship_turns() -> void:
	var s: StationScreen = _screen()
	await await_idle_frame()
	var p: WeaponsPanel = _panel(s)
	var ctx: StationContext = s.ctx
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(60.0, -30.0)
	s.feed(motion)
	p.step(0.1)
	var aims: Array = _commands(s, "aim_mount")
	assert_int(aims.size()).is_equal(1)
	var aim: Vector3 = p.aim_dir(0)
	var rot0: Quaternion = StationFixture.own_rotation()
	var moved: float = (rot0 * Vector3.FORWARD).angle_to(aim)
	assert_float(moved).is_greater(0.02)
	assert_float(moved).is_less(0.27)
	# The ship yaws 5 degrees and rolls 20; the input is at rest.
	ctx.matcher.mouse_stick.value = Vector2.ZERO
	var rot1: Quaternion = (
		rot0 * Quaternion(Vector3.UP, deg_to_rad(5.0)) * Quaternion(Vector3.BACK, deg_to_rad(20.0))
	)
	_turn_ship(ctx, rot1)
	StationFixture.clock(ctx).ms += 200
	p.step(0.1)
	# The held point, seen from where the turned ship's mount now is.
	var point: Vector3 = Vector3(aims[0]["aim_x"], aims[0]["aim_y"], aims[0]["aim_z"])
	var held: Vector3 = (point - StationFixture.OWN_POS - rot1 * Vector3(0, 0, -22)).normalized()
	assert_float(held.angle_to(aim)).is_less(1e-3)
	assert_vector(p.aim_dir(0)).is_equal_approx(held, Vector3.ONE * 1e-4)
	assert_vector(-p.cam_basis.z).is_equal_approx(held, Vector3.ONE * 1e-4)
	assert_int(_commands(s, "aim_mount").size()).is_equal(1)
	# Camera roll follows the deck plane: up is the ship's up made square to the view.
	var deck_up: Vector3 = rot1 * Vector3.UP
	var want_up: Vector3 = (deck_up - held * held.dot(deck_up)).normalized()
	assert_vector(p.cam_basis.y).is_equal_approx(want_up, Vector3.ONE * 1e-4)
	# The sim side of the same command: the barrel slews at traverse rate and holds the
	# point while the ship turns.
	var def: ShipDef = load("res://content/ships/m1_corvette.tres")
	var world: SimWorld = SimWorld.new(1)
	var ship: int = world.spawn_ship(def, 0, StationFixture.OWN_POS, rot0)
	var cmd: Dictionary = aims[0].duplicate()
	var c: SimCommand = SimCommands.from_dict(cmd)
	c.ship_id = ship
	world.submit(c)
	for i: int in 10:
		world.step()
	var mount: MountDef = def.mounts[0]
	var slewed: float = mount.forward.angle_to(world.mounts.barrel[0])
	assert_float(slewed).is_equal_approx(minf(moved, 10 * mount.traverse_rate / 60.0), 2e-3)
	world.kin.rot[ship] = rot1
	for i: int in 60:
		world.step()
	var barrel_world: Vector3 = world.kin.to_world(ship, world.mounts.barrel[0])
	assert_vector(barrel_world).is_equal_approx(held, Vector3.ONE * 2e-3)


# FT: FT-STN-017
# Comfort: roll locked to the deck plane by default, to the target's deck plane (NEAR
# orientation) or to the player's cosmetic reference plane; reduced field of view.
func test_comfort_roll_lock_and_reduced_fov() -> void:
	var s: StationScreen = _screen()
	var p: WeaponsPanel = _panel(s)
	var ctx: StationContext = s.ctx
	var rot: Quaternion = StationFixture.own_rotation()
	p.step(0.016)
	assert_vector(p.cam_basis.y).is_equal_approx(rot * Vector3.UP, Vector3.ONE * 1e-4)
	assert_float(p.fov).is_equal(WeaponsPanel.FOV_DEG)
	ctx.settings.comfort = true
	ctx.settings.roll_lock = "reference"
	ctx.settings.reference_plane = Quaternion(Vector3.BACK, deg_to_rad(90.0))
	ctx.settings.reduced_fov = true
	p.step(0.016)
	var fwd: Vector3 = -p.cam_basis.z
	var ref_up: Vector3 = Vector3.LEFT
	var want: Vector3 = (ref_up - fwd * fwd.dot(ref_up)).normalized()
	assert_vector(p.cam_basis.y).is_equal_approx(want, Vector3.ONE * 1e-4)
	assert_float(p.fov).is_less(WeaponsPanel.FOV_DEG)
	# Target lock: the selected contact's orientation; without one, the deck.
	ctx.settings.roll_lock = "target"
	ctx.crew.select("contact", StationFixture.H2)
	p.step(0.016)
	assert_vector(p.cam_basis.y).is_equal_approx(rot * Vector3.UP, Vector3.ONE * 1e-4)
	var target_rot: Quaternion = Quaternion(Vector3.FORWARD, deg_to_rad(40.0))
	ctx.view.near[StationFixture.H2] = [
		NetCodec.pack_quat(target_rot), Vector3i.ZERO, StationFixture.TICK
	]
	p.step(0.016)
	var t_up: Vector3 = NetCodec.unpack_quat(NetCodec.pack_quat(target_rot)) * Vector3.UP
	fwd = -p.cam_basis.z
	want = (t_up - fwd * fwd.dot(t_up)).normalized()
	assert_vector(p.cam_basis.y).is_equal_approx(want, Vector3.ONE * 1e-4)
	ctx.settings.comfort = false
	p.step(0.016)
	assert_vector(p.cam_basis.y).is_equal_approx(rot * Vector3.UP, Vector3.ONE * 1e-4)
	assert_float(p.fov).is_equal(WeaponsPanel.FOV_DEG)


# FT: FT-SIM-015
# Aim assist acts on controller aiming only: the same deflection near the selected
# contact's lead point turns the aim exactly as asked with the mouse, and slower and
# toward the lead with the right stick; far from the lead the stick gets no assist.
func test_aim_assist_on_controller_only() -> void:
	var s: StationScreen = _screen()
	var p: WeaponsPanel = _panel(s)
	var ctx: StationContext = s.ctx
	var rot: Quaternion = StationFixture.own_rotation()
	_place(ctx, StationFixture.H2, _bearing(2.0, 0.0, 2000.0))
	ctx.crew.select("contact", StationFixture.H2)
	var lead: Vector3 = p.lead_dir(0, StationFixture.H2)
	var start: Vector3 = rot * Vector3.FORWARD
	var results: Dictionary = {}
	for device: String in ["kbm", "pad", "pad_far"]:
		p.set_aim_dir(0, start)
		if device == "pad_far":
			_place(ctx, StationFixture.H2, _bearing(10.0, 0.0, 2000.0))
		ctx.matcher.mouse_stick.value = Vector2.ZERO
		var stick: InputEventJoypadMotion = InputEventJoypadMotion.new()
		stick.axis = JOY_AXIS_RIGHT_Y
		stick.axis_value = 0.0
		ctx.matcher.feed(stick, ctx.now_ms())
		if device == "kbm":
			ctx.matcher.mouse_stick.value = Vector2(0.0, -0.5)
			ctx.matcher.device = IntentTable.KBM
		else:
			stick.axis_value = -0.6
			ctx.matcher.feed(stick, ctx.now_ms())
		var y: float = ctx.matcher.axis("aim_y")
		var up: Vector3 = rot * Vector3.UP
		var right: Vector3 = start.cross(up).normalized()
		var pure: Vector3 = start.rotated(right, -y * WeaponsPanel.AIM_RATE * 0.1)
		p.step(0.1)
		results[device] = [p.aim_dir(0), pure]
	var kbm: Array = results["kbm"]
	assert_vector(kbm[0]).is_equal_approx(kbm[1], Vector3.ONE * 1e-4)
	var pad: Array = results["pad"]
	assert_float((pad[0] as Vector3).angle_to(lead)).is_less((pad[1] as Vector3).angle_to(lead))
	assert_float((pad[0] as Vector3).angle_to(start)).is_less((pad[1] as Vector3).angle_to(start))
	var far: Array = results["pad_far"]
	assert_vector(far[0]).is_equal_approx(far[1], Vector3.ONE * 1e-4)


# FT: FT-WPN-001, FT-SIM-012
# Holding fire sends one `fire` per weapon cooldown on the camera mount, after its aim;
# not on a mount someone else holds, nor with the aim out of arc. Fire-all aims every
# held mount at the selected contact's lead and fires those in arc (FT-JNT-008's hook).
func test_fire_hold_cooldown_claims_and_fire_all() -> void:
	var s: StationScreen = _screen()
	var p: WeaponsPanel = _panel(s)
	var ctx: StationContext = s.ctx
	var clock: StationFixture.Clock = StationFixture.clock(ctx)
	s.dispatch(_ev(s, "fire"))
	p.step(0.016)
	p.step(0.016)
	assert_int(_commands(s, "fire").size()).is_equal(1)
	clock.ms += 500
	p.step(0.016)
	assert_int(_commands(s, "fire").size()).is_equal(2)
	s.dispatch(_ev(s, "fire", "kbm", false))
	clock.ms += 1000
	p.step(0.016)
	assert_int(_commands(s, "fire").size()).is_equal(2)
	# Someone else's mount: no shot.
	ctx.crew.claims["mount:0"] = {"session": 99, "name": "Bo"}
	s.dispatch(_ev(s, "fire", "pad"))
	p.step(0.016)
	assert_int(_commands(s, "fire").size()).is_equal(2)
	s.dispatch(_ev(s, "fire", "pad", false))
	ctx.crew.claims["mount:0"] = {"session": StationFixture.SESSION, "name": "Ana"}
	# Fire-all at a contact out of arc: nothing; in arc: aim at its lead, then fire.
	ctx.crew.select("contact", StationFixture.H2)
	clock.ms += 1000
	assert_int(p.fire_claimed_at(StationFixture.H2)).is_equal(0)
	_place(ctx, StationFixture.H2, _bearing(5.0, 3.0, 1500.0))
	var before: int = _commands(s, "aim_mount").size()
	assert_int(p.fire_claimed_at(StationFixture.H2)).is_equal(1)
	var aims: Array = _commands(s, "aim_mount")
	assert_int(aims.size()).is_equal(before + 1)
	var sent: Array = StationFixture.sent(ctx).sent
	assert_str(sent[-1][1][0]["kind"]).is_equal("fire")
	assert_str(sent[-2][1][0]["kind"]).is_equal("aim_mount")
	assert_vector(p.aim_dir(0)).is_equal_approx(
		p.lead_dir(0, StationFixture.H2) as Vector3, Vector3.ONE * 1e-3
	)


# FT: FT-STN-003, FT-STN-009
# Select falls through to fire over empty space (owner decision in #7): the bracket or
# chip under the pointer (or, on a controller, the reticle) selects; elsewhere nothing.
func test_select_over_brackets_only() -> void:
	var s: StationScreen = _screen()
	await await_idle_frame()
	var p: WeaponsPanel = _panel(s)
	_place(s.ctx, StationFixture.H2, _bearing(0.0, 0.0, 2000.0))
	p.step(0.016)
	p.queue_redraw()
	await await_idle_frame()
	var at: Vector2 = p.project(StationFixture.own_rotation() * Vector3.FORWARD)
	assert_dict(p.item_at(at)).is_equal({"kind": "contact", "id": StationFixture.H2})
	assert_dict(p.item_at(at + Vector2(0, 120))).is_empty()
	assert_bool(s.dispatch(_ev(s, "select", "pad"))).is_true()
	assert_dict(s.ctx.crew.selection).is_equal({"kind": "contact", "id": StationFixture.H2})
