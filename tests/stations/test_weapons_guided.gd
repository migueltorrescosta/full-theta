extends GdUnitTestSuite
## Weapons (M2): ammunition types and guided ordnance on the station fixture
## (FT-WPN-006, FT-WPN-008, FT-STN-010). The fixture's corvette gets a second ammunition
## type on its bow mount, a missile.

const MISSILE: String = "res://content/weapons/m2_missile.tres"

var _toasts: Array[String] = []


func before() -> void:
	I18n.apply("en")


func before_test() -> void:
	_toasts = []


## A Weapons screen whose bow mount has the cannon and a missile; the MOUNTS block says
## which type is selected.
func _screen(ammo_type: int = 0) -> StationScreen:
	var ctx: StationContext = StationFixture.context("weapons", "user://test_weapons_guided.cfg")
	ctx.crew.claims["mount:0"] = {"session": StationFixture.SESSION, "name": "Ana"}
	ctx.crew.toast.connect(func(key: String, _a: Dictionary) -> void: _toasts.append(key))
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	add_child(s)
	var p: WeaponsPanel = _panel(s)
	p.set_process(false)
	var def: ShipDef = p.ship_def.duplicate()
	var mount: MountDef = def.mounts[0].duplicate()
	var alts: Array[WeaponDef] = [load(MISSILE) as WeaponDef]
	mount.alt_weapons = alts
	var mounts: Array[MountDef] = [mount]
	def.mounts = mounts
	p.ship_def = def
	var row: Dictionary = ctx.view.blocks[StationViews.Section.MOUNTS]["mounts"][0]
	row["ammo_type"] = ammo_type
	return s


func _panel(s: StationScreen) -> WeaponsPanel:
	return s.panels[0] as WeaponsPanel


func _ev(s: StationScreen, id: String) -> Dictionary:
	return {
		"id": id,
		"group": IntentTable.row(id)["group"],
		"target": IntentTable.target(id, "kbm", s.focused_station(), s.stations),
		"kind": IntentTable.row(id)["kind"],
		"pressed": true,
		"value": 1.0,
		"device": "kbm",
	}


func _commands(s: StationScreen, kind: String) -> Array:
	var out: Array = []
	for c: Array in StationFixture.sent(s.ctx).of("command"):
		if c[1][0]["kind"] == kind:
			out.append(c[1][0])
	return out


## Puts contact `id` at a ship-frame offset.
func _place(ctx: StationContext, id: int, local: Vector3) -> void:
	var p: Vector3 = StationFixture.OWN_POS + StationFixture.own_rotation() * local
	ctx.view.contacts["model"][id] = [
		NetCodec.quant_pos(p.x, p.y, p.z, ctx.view.p_units), Vector3i.ZERO, StationFixture.TICK
	]
	ctx.interp = SnapshotInterpolator.new()
	ctx.interp.p_units = ctx.view.p_units
	ctx.interp.push(ctx.view, StationFixture.NOW_MS - 100)
	ctx.interp.push(ctx.view, StationFixture.NOW_MS)
	ctx.interp.update(StationFixture.NOW_MS)


## Replaces the marks with Bravo (slot 1) attached to `contact` (-1: free) at the ship-frame
## offset.
func _mark(s: StationScreen, contact: int, local: Vector3) -> void:
	var p: Vector3 = StationFixture.OWN_POS + StationFixture.own_rotation() * local
	var m: Dictionary = {
		"slot": StationFixture.BRAVO_SLOT,
		"name": "Bravo",
		"contact": contact,
		"x": p.x,
		"y": p.y,
		"z": p.z,
		"by": "Ana",
	}
	s.ctx.crew.handle_event(
		{"type": "marks", "payload": {"ship": StationFixture.SHIP, "marks": [m]}},
		StationFixture.NOW_MS
	)


# FT: FT-WPN-006
# Ammo select cycles the mount's types through its claim (set_ammo_type, wrapping), the
# ammunition line names the selected type, and the mount list counts that type's rounds.
func test_ammo_select_cycles_the_types() -> void:
	var s: StationScreen = _screen()
	var p: WeaponsPanel = _panel(s)
	assert_bool(s.dispatch(_ev(s, "ammo_next"))).is_true()
	assert_array(_commands(s, "set_ammo_type")).is_equal(
		[{"kind": "set_ammo_type", "mount_index": 0, "ammo_type": 1}]
	)
	(
		assert_str(StationViews.item_of(SimCommands.from_dict(_commands(s, "set_ammo_type")[0])))
		. is_equal("mount:0")
	)
	var second: StationScreen = _screen(1)
	var q: WeaponsPanel = _panel(second)
	second.dispatch(_ev(second, "ammo_next"))
	assert_int(_commands(second, "set_ammo_type")[0]["ammo_type"]).is_equal(0)
	second.dispatch(_ev(second, "ammo_prev"))
	assert_int(_commands(second, "set_ammo_type")[1]["ammo_type"]).is_equal(0)
	assert_str(q._ammo_text()).is_equal("Ammo: Missile")
	assert_str(p._ammo_text()).is_equal("Ammo: Mass driver")
	assert_str(q.mount_rows()[0]).contains("/8")


# FT: FT-WPN-008, FT-STN-010
# Guided fire goes to the contact a selected mark is attached to, else to the selected
# contact; the mount is aimed at it first.
func test_guided_fire_at_a_mark_on_a_contact() -> void:
	var s: StationScreen = _screen(1)
	var ahead: Vector3 = Vector3(0.0, 0.0, -2000.0)
	_place(s.ctx, StationFixture.H2, ahead)
	_mark(s, StationFixture.H2, ahead)
	s.ctx.crew.select("mark", StationFixture.BRAVO_SLOT)
	assert_dict(_panel(s).guided_goal()).is_equal({"target": StationFixture.H2})
	assert_bool(s.dispatch(_ev(s, "fire_guided"))).is_true()
	var fired: Array = _commands(s, "fire_guided")
	assert_int(fired.size()).is_equal(1)
	assert_dict(fired[0]).is_equal(
		{"kind": "fire_guided", "mount_index": 0, "target": StationFixture.H2}
	)
	assert_array(_commands(s, "aim_mount")).is_not_empty()
	var cmd: SimCommand = SimCommands.from_dict(fired[0])
	assert_str(StationViews.item_of(cmd)).is_equal("mount:0")
	assert_str(StationViews.station_of_command(cmd.kind())).is_equal("weapons")
	# The selected contact works without a mark; the cooldown holds a second press.
	s.ctx.crew.select("contact", StationFixture.H2)
	assert_dict(_panel(s).guided_goal()).is_equal({"target": StationFixture.H2})
	s.dispatch(_ev(s, "fire_guided"))
	assert_int(_commands(s, "fire_guided").size()).is_equal(1)


# FT: FT-WPN-008
# A free mark in space is refused (D209): no goal, no command, and the toast says to select a
# mark on a tracked contact.
func test_guided_fire_at_a_free_mark_is_refused() -> void:
	var s: StationScreen = _screen(1)
	_mark(s, -1, Vector3(0.0, 0.0, -3000.0))
	s.ctx.crew.select("mark", StationFixture.BRAVO_SLOT)
	assert_dict(_panel(s).guided_goal()).is_empty()
	s.dispatch(_ev(s, "fire_guided"))
	assert_array(_commands(s, "fire_guided")).is_empty()
	assert_array(_toasts).is_equal(["toast.guided_no_mark"])


# FT: FT-WPN-008
# Nothing to send, and why: no selection, a mark on a contact out of view (or on no
# contact), a target out of arc, or ammunition that isn't guided.
func test_guided_fire_refusals_say_why() -> void:
	var s: StationScreen = _screen(1)
	s.dispatch(_ev(s, "fire_guided"))
	assert_array(_toasts).is_equal(["toast.guided_no_mark"])
	_mark(s, 99, Vector3(0.0, 0.0, -2000.0))
	s.ctx.crew.select("mark", StationFixture.BRAVO_SLOT)
	s.dispatch(_ev(s, "fire_guided"))
	assert_array(_toasts).is_equal(["toast.guided_no_mark", "toast.guided_no_mark"])
	_place(s.ctx, StationFixture.H2, Vector3(2000.0, 0.0, 0.0))
	s.ctx.crew.select("contact", StationFixture.H2)
	s.dispatch(_ev(s, "fire_guided"))
	assert_str(_toasts[-1]).is_equal("toast.guided_out_of_arc")
	var cannon: StationScreen = _screen(0)
	_place(cannon.ctx, StationFixture.H2, Vector3(0.0, 0.0, -2000.0))
	cannon.ctx.crew.select("contact", StationFixture.H2)
	cannon.dispatch(_ev(cannon, "fire_guided"))
	assert_str(_toasts[-1]).is_equal("toast.not_guided")
	assert_array(_commands(s, "fire_guided")).is_empty()
	assert_array(_commands(cannon, "fire_guided")).is_empty()


# FT: FT-SIM-013
# An overheat-locked mount shows as locked and doesn't send fire.
func test_locked_mount_shows_and_holds_fire() -> void:
	var s: StationScreen = _screen()
	var p: WeaponsPanel = _panel(s)
	s.ctx.view.blocks[StationViews.Section.MOUNTS]["mounts"][0]["locked"] = true
	assert_str(p.mount_rows()[0]).contains("locked")
	assert_bool(p._try_fire(0, s.ctx.now_ms())).is_false()
