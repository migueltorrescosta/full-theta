# gdlint: disable=max-public-methods
class_name WeaponsPanel
extends StationPanel
## Weapons (§5.2, W-B turret camera, D49; T052). Focused, the panel is the turret camera
## of one mount (FT-WPN-001): stars and contacts (SpaceView, D107) with brackets and
## chips, the mount's arc edge, where the barrel points, the lead reticle on the selected
## contact (Lead, shared/, FT-SIM-014), an out-of-arc line with the clock and height to
## turn to (FT-WPN-005), and the mount list with state and claimer (FT-WPN-004). The
## screen's disc radar is the inset (FT-WPN-002). Docked, it shows the mount list and
## the target line only.
##
## Aim: the aim axes turn the camera mount's aim at AIM_RATE. The aim is a
## point, like the sim's (`aim_mount`, FT-WPN-009): it holds in world space while the
## ship turns, the barrel slews to it at the mount's traverse rate (sim), and the camera
## looks at it with its roll on the deck plane (ComfortCamera, FT-STN-017). Light aim
## assist acts on controller input only (FT-SIM-015, D25). Fire holds send `fire` at the
## weapon's cooldown; docked in Tactical's cockpit, the KB/M fire holds fire every
## claimed mount at the selected target (FT-JNT-008). Mount defs come from the ship's
## ShipDef in content/.
##
## On a phone (#28 follow-up, D287, D289) WeaponsTouch puts one right rail over the full-width
## view (landscape) or a controls block under it (upright), with the pages Fire, Mounts and
## Crew: a drag aims, FIRE holds `fire`, and the buttons send the same intents as the keys.
## The panel is in the phone frame (`in_frame`): its read-outs sit under the view-top row.
## On a tablet (#32) WeaponsTablet docks two rails at the screen's edges and puts an aim pad
## over the view; the rest of the panel is the desktop arrangement.

## A touch control sent `id` (tests: taps send what the keys send).
signal touch_intent(id: String)

## Vertical field of view (degrees).
const FOV_DEG: float = 60.0
## Aim turn rate at full deflection (rad/s, PROVISIONAL).
const AIM_RATE: float = 0.8
## Controller aim assist (FT-SIM-015, PROVISIONAL, asked of the owner): within
## ASSIST_CONE (rad) of the selected contact's lead point, while the stick moves, the
## turn rate drops to ASSIST_SLOW and the aim drifts to the lead at up to ASSIST_PULL
## (rad/s at full deflection). Never with KB/M, never with the stick at rest.
const ASSIST_CONE: float = 0.07
const ASSIST_SLOW: float = 0.6
const ASSIST_PULL: float = 0.1
## Contact ship models: ProceduralShip is about 5 units long; ships are about 50 m.
const SHIP_SCALE: float = 10.0
## The device name the touch rails' intents carry.
const TOUCH: String = "touch"
## The least side (device-independent px) of a phone window; the smallest phones have 320.
const PHONE_MIN_SIDE: float = 300.0

## Index of the camera mount in ShipDef.mounts.
var mount: int = 0
var ship_def: ShipDef = null
## The camera basis and field of view of the last frame (world axes).
var cam_basis: Basis = Basis.IDENTITY
var fov: float = FOV_DEG

## The mounts' aim points and fire times (WeaponsAim).
var aim: WeaponsAim = WeaponsAim.new(self)
var _firing: bool = false
var _firing_all: bool = false
var _view: SubViewportContainer
## The turret camera's view, from the camera mount.
var _space: SpaceView
var _overlay: WeaponsTurretOverlay
## The phone arrangement while the form is a phone's and the panel is focused, else null.
var _touch: WeaponsTouch = null
## The tablet's docked rails and aim pad (#32) while the focused panel is on a tablet.
var _tablet: WeaponsTablet = null
var _screen: StationScreen = null


func _setup() -> void:
	in_frame = true
	# The Crew page shows the share buttons (CrewPage).
	shows_shares = true
	ship_def = ctx.ship_def()
	_build_view()
	_overlay = WeaponsTurretOverlay.new(self)
	add_child(_overlay)
	mount = _first_mount()


func _ready() -> void:
	_screen = screen()
	if _screen != null:
		_screen.form_changed.connect(func(_f: LayoutMode.Form) -> void: _apply_form())
		# A tablet keeps its form in a rotation: only its dock's arrangement changes.
		_screen.resized.connect(_apply_tablet)
	_apply_form()


func _mode_changed() -> void:
	_view.visible = focused
	if not focused:
		_firing = false
		_firing_all = false
	_apply_form()


## Focused on a phone the panel draws its own radar inset and takes the whole screen (#28).
func full_screen() -> bool:
	return focused and mount_count() > 0 and phone_form() >= 0


## The view's free part: beside the rail on its side, the view above the controls upright.
func view_rect() -> Rect2:
	return _touch.view_rect() if _touch != null else super()


## The phone form this panel lays out for, or -1 for the tablet and desktop arrangement.
## A window with a side under PHONE_MIN_SIDE (a headless run's 64 px) is no phone.
func phone_form() -> int:
	if not is_inside_tree():
		return -1
	var form: LayoutMode.Form = LayoutMode.form_of(self)
	var dp: Vector2 = LayoutMode.dp_size_of(get_viewport())
	if not LayoutMode.is_phone(form) or minf(dp.x, dp.y) < PHONE_MIN_SIDE:
		return -1
	return form


## Builds, swaps or removes the phone arrangement for the current form and focus.
func _apply_form() -> void:
	if _view == null or not is_inside_tree():
		return
	_apply_tablet.call_deferred()
	var form: int = phone_form()
	var want: bool = focused and mount_count() > 0 and form >= 0
	if _touch != null and want and _touch.form == form:
		return
	if _touch != null:
		for c: Control in [_view, _overlay]:
			c.reparent(self, false)
			c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		move_child(_view, 0)
		_touch.queue_free()
		remove_child(_touch)
		_touch = null
		pages = null
	if want:
		# On its side the screen shows only the focused panel; upright a joint view keeps
		# the screen's radar under its docked panels.
		var own_radar: bool = (
			form == LayoutMode.Form.PHONE_LANDSCAPE or _screen == null or _screen.panels.size() == 1
		)
		_touch = WeaponsTouch.new(self, form as LayoutMode.Form, own_radar)
		add_child(_touch)
		_touch.take_view(_view, _overlay)
		if _screen != null:
			_touch.pad.long_press = _screen.frame.long_press
			_touch.pad.now_ms = ctx.now_ms
		pages = _touch.pages
		_touch.refresh()


## Builds, rebuilds (a rotation) or drops the tablet's docked rails for the focused panel.
func _apply_tablet() -> void:
	var dock: TabletDock = sync_tablet(
		_tablet.dock if _tablet != null else null,
		(
			focused
			and _screen != null
			and mount_count() > 0
			and LayoutMode.form_of(self) == LayoutMode.Form.TABLET
			and TabletDock.fits(LayoutMode.dp_size_of(get_viewport()))
		),
		func() -> void:
			remove_child(_tablet)
			_tablet.queue_free()
			_tablet = null,
		func(portrait: bool) -> TabletDock:
			_tablet = WeaponsTablet.new(self, portrait)
			add_child(_tablet)
			return _tablet.dock
	)
	if dock != null:
		_tablet.refresh()


## The tablet arrangement, or null (tests and shots).
func tablet() -> WeaponsTablet:
	return _tablet


## The phone arrangement, or null (tests and shots).
func touch() -> WeaponsTouch:
	return _touch


# --- Touch (#28): the rails send the same intents as the keys and the pad. ---


## A rail button's press intent (`mount_next`, `ammo_next`, `fire_guided`).
func touch_press(id: String) -> void:
	touch_intent.emit(id)
	handle_intent({"id": id, "pressed": true, "device": TOUCH})


## A held rail button (`fire`): pressed on the finger's down, released on its up.
func touch_hold(down: bool, id: String) -> void:
	if down:
		touch_intent.emit(id)
	handle_intent({"id": id, "pressed": down, "device": TOUCH})


## Claim or Release: the screen's common `claim` intent.
func touch_claim() -> void:
	touch_intent.emit("claim")
	if _screen != null:
		_screen.dispatch({"id": "claim", "target": "screen", "pressed": true, "device": TOUCH})


## A finger dragged `relative` px across the view turns the camera mount's aim by the angle
## it covers on screen (drag right: aim right). No aim assist (controller only, D25).
func touch_aim(relative: Vector2) -> void:
	if mount_count() == 0:
		return
	var f: float = _overlay.focal()
	var yaw: float = relative.x / f
	var pitch: float = relative.y / f * (-1.0 if ctx.matcher.invert_pitch else 1.0)
	var dir: Vector3 = aim_dir(mount)
	var basis: Basis = _look(dir)
	aim.aim_within_arc(mount, dir.rotated(basis.y, -yaw).rotated(basis.x, -pitch))


## A tap on the view (`global_pos` in viewport px) selects the bracket under it.
func touch_select(global_pos: Vector2) -> void:
	var item: Dictionary = item_at(get_global_transform().affine_inverse() * global_pos)
	if not item.is_empty():
		ctx.crew.select(item["kind"], item["id"])


func _process(delta: float) -> void:
	step(delta)


## One frame: aim from the axes, aim and fire sends, camera and overlay. Public so tests
## can step it with a fixed delta.
func step(delta: float) -> void:
	if mount_count() == 0:
		_overlay.queue_redraw()
		return
	var now: int = ctx.now_ms()
	_turn_aim(delta)
	aim.flush(now, false)
	if not focused and (_firing or _firing_all):
		# Tactical's cockpit (FT-JNT-008): the KB/M fire buttons fire every claimed mount
		# at the selected target.
		fire_claimed_at(selected_contact())
	else:
		if _firing:
			_try_fire(mount, now)
		if _firing_all:
			fire_claimed_at(selected_contact(), mount)
	_update_camera()
	_overlay.layout_targets()
	_overlay.queue_redraw()
	if _touch != null:
		_touch.refresh()
	if _tablet != null:
		_tablet.refresh()


func handle_intent(ev: Dictionary) -> bool:
	var id: String = ev["id"]
	var pressed: bool = bool(ev.get("pressed", true))
	match id:
		"fire":
			_firing = pressed
		"fire_all":
			_firing_all = pressed
		"mount_1", "mount_2", "mount_3", "mount_4":
			if pressed:
				select_mount(int(id.right(1)) - 1)
		"mount_prev", "mount_next":
			if pressed:
				swap(1 if id == "mount_next" else -1)
		"ammo_next", "ammo_prev":
			if pressed:
				cycle_ammo(1 if id == "ammo_next" else -1)
		"fire_guided":
			if pressed:
				fire_guided(mount)
		_:
			return false
	return true


## Brackets and chips under the pointer (§5.0); empty space falls through, so LMB fires
## (owner decision in #7). On a controller the screen asks at the centre: the reticle.
func item_at(screen_pos: Vector2) -> Dictionary:
	if not focused:
		return {}
	var global: Vector2 = get_global_transform() * screen_pos
	var radar: DiscRadar = _touch.radar if _touch != null else null
	if radar != null and radar.is_visible_in_tree() and radar.get_global_rect().has_point(global):
		return radar.item_at(radar.get_global_transform().affine_inverse() * global)
	var at: Vector2 = _overlay.get_global_transform().affine_inverse() * global
	for t: Dictionary in _overlay.targets:
		if (t["rect"] as Rect2).has_point(at):
			return {"kind": t["item"]["kind"], "id": t["item"]["id"]}
	return {}


## The reticle: the centre of the turret view, in the panel's coordinates.
func cursor_pos() -> Vector2:
	return get_global_transform().affine_inverse() * _overlay.get_global_rect().get_center()


## The cockpit and the turret look forward: a mark attaches to the tapped contact or none
## is placed (FT-SPA-030).
func marks_attach_only() -> bool:
	return focused


## The weapon of mount i's selected ammunition type.
func weapon_of(i: int) -> WeaponDef:
	var types: Array[WeaponDef] = ship_def.mounts[i].ammo_types()
	return types[clampi(int(mount_row(i).get("ammo_type", 0)), 0, types.size() - 1)]


## Switches the camera mount to the next (or previous) ammunition type it has; false, with
## a toast, when it has only one or this client may not use it.
func cycle_ammo(direction: int) -> bool:
	if mount_count() == 0 or not is_usable(mount):
		return false
	var n: int = ship_def.mounts[mount].ammo_types().size()
	if n < 2:
		ctx.crew.toast.emit("toast.one_ammo", {})
		return false
	var now: int = int(mount_row(mount).get("ammo_type", 0))
	ctx.intents.command(
		{"kind": "set_ammo_type", "mount_index": mount, "ammo_type": posmod(now + direction, n)}
	)
	return true


## What guided ordnance would fly at (FT-WPN-008, D209): {"target": contact id} for the
## selected contact, or for a selected mark attached to a contact in view; {} when nothing
## usable is selected: a free mark, or a mark on a contact out of view, is not a goal.
func guided_goal() -> Dictionary:
	var s: Dictionary = ctx.crew.selection
	var id: int = int(s.get("id", -1))
	match str(s.get("kind", "")):
		"contact":
			return {"target": id} if id in ctx.interp.contact_ids() else {}
		"mark":
			var m: Dictionary = ctx.crew.mark_in_slot(id)
			if m.is_empty():
				return {}
			var contact: int = int(m["contact"])
			if contact >= 0 and contact in ctx.interp.contact_ids():
				return {"target": contact}
	return {}


## Fires mount i's guided ordnance at the selected mark or contact (FT-WPN-008): aims the
## mount at it, and sends `fire_guided` when it is in arc and loaded. False, with a toast
## where the player can fix it, when it doesn't fire.
func fire_guided(i: int) -> bool:
	if mount_count() == 0 or not is_usable(i):
		return false
	var w: WeaponDef = weapon_of(i)
	if not w.is_guided():
		ctx.crew.toast.emit("toast.not_guided", {})
		return false
	var goal: Dictionary = guided_goal()
	if goal.is_empty():
		ctx.crew.toast.emit("toast.guided_no_mark", {})
		return false
	var now: int = ctx.now_ms()
	var row: Dictionary = mount_row(i)
	if now < int(aim.next_fire.get(i, 0)) or int(row.get("ammo", 1)) == 0:
		return false
	var at: Vector3 = ctx.interp.contact_position(int(goal["target"]))
	aim.aims[i] = at
	aim.dirty[i] = true
	if not in_arc(i, aim_dir(i)):
		ctx.crew.toast.emit("toast.guided_out_of_arc", {})
		return false
	aim.flush(now, true)
	ctx.intents.command({"kind": "fire_guided", "mount_index": i, "target": int(goal["target"])})
	aim.next_fire[i] = now + roundi(w.cooldown * 1000.0)
	return true


## "Bring mount N to bear" (Helm's chip) names the selected mount.
func chip_arg(chip: ChipDef) -> int:
	return mount if chip.arg == ChipDef.Arg.MOUNT else -1


func claim_item() -> String:
	return "%s:%d" % [StationViews.CLAIM_MOUNT, mount] if mount_count() > 0 else ""


# --- Mounts. ---


func mount_count() -> int:
	return ship_def.mounts.size() if ship_def != null else 0


## The MOUNTS block row of mount i ({} before data).
func mount_row(i: int) -> Dictionary:
	var rows: Array = ctx.view.blocks.get(StationViews.Section.MOUNTS, {}).get("mounts", [])
	return rows[i] if i < rows.size() else {}


func is_mine(i: int) -> bool:
	return int(holder(i).get("session", -1)) == ctx.crew.session


## Free or mine: this client may aim and fire it.
func is_usable(i: int) -> bool:
	return holder(i).is_empty() or is_mine(i)


## Camera on mount i, if this client may use it.
func select_mount(i: int) -> void:
	if i >= 0 and i < mount_count() and is_usable(i):
		mount = i


## Camera swap (FT-WPN-003): the next or previous mount this client holds (any usable one
## while it holds none).
func swap(direction: int) -> void:
	var mine: Array[int] = []
	var usable: Array[int] = []
	for i: int in mount_count():
		if is_mine(i):
			mine.append(i)
		if is_usable(i):
			usable.append(i)
	var ring: Array[int] = mine if not mine.is_empty() else usable
	if ring.is_empty():
		return
	var at: int = ring.find(mount)
	if at < 0:
		mount = ring[0] if direction > 0 else ring[-1]
	else:
		mount = ring[posmod(at + direction, ring.size())]


## Fires every mount this client holds (FT-JNT-008's cockpit and the fire-all hold): each
## except `keep_aim` first aims at `contact`'s lead point (-1: keep the aims), and fires
## if in arc and ready. Returns the mounts fired.
func fire_claimed_at(contact: int, keep_aim: int = -1) -> int:
	var now: int = ctx.now_ms()
	var fired: int = 0
	for i: int in mount_count():
		if not is_mine(i):
			continue
		if i != keep_aim and contact >= 0:
			var lead: Variant = lead_dir(i, contact)
			if lead == null:
				continue
			set_aim_dir(i, lead)
		if _try_fire(i, now):
			fired += 1
	return fired


# --- Aim (WeaponsAim) and read-outs (WeaponsReadout). ---


## Where mount i aims (world unit vector from the mount): its aim point, else its barrel.
func aim_dir(i: int) -> Vector3:
	return aim.aim_dir(i)


## Aims mount i along `dir` (world unit vector): a point at the weapon's range.
func set_aim_dir(i: int, dir: Vector3) -> void:
	aim.set_aim_dir(i, dir)


## The aim direction from mount i (world unit) that leads `contact`, or null.
func lead_dir(i: int, contact: int) -> Variant:
	return aim.lead_dir(i, contact)


## True when a world direction from mount i lies in its arc (FT-SIM-011).
func in_arc(i: int, dir: Vector3) -> bool:
	return aim.in_arc(i, dir)


func selected_contact() -> int:
	var s: Dictionary = ctx.crew.selection
	return int(s["id"]) if s.get("kind", "") == "contact" else -1


## The name of the player who holds mount i, or "".
func holder_name(i: int) -> String:
	return str(holder(i).get("name", ""))


# --- Internals. ---


## The claim on mount i ({"session", "name"}), {} while free.
func holder(i: int) -> Dictionary:
	return ctx.crew.claims.get("%s:%d" % [StationViews.CLAIM_MOUNT, i], {})


func _first_mount() -> int:
	for i: int in mount_count():
		if is_mine(i):
			return i
	for i: int in mount_count():
		if is_usable(i):
			return i
	return 0


## Turns the camera mount's aim by the aim axes (with controller assist).
func _turn_aim(delta: float) -> void:
	var x: float = ctx.matcher.axis("aim_x")
	var y: float = ctx.matcher.axis("aim_y")
	if x == 0.0 and y == 0.0:
		return
	var dir: Vector3 = aim_dir(mount)
	var basis: Basis = _look(dir)
	var rate: float = AIM_RATE
	var lead: Variant = null
	# FT-SIM-015: assist on controller aiming only (D25).
	if ctx.matcher.device == IntentTable.PAD:
		lead = aim.lead_dir(mount, selected_contact())
		if lead != null and dir.angle_to(lead) > ASSIST_CONE:
			lead = null
	if lead != null:
		rate *= ASSIST_SLOW
	dir = dir.rotated(basis.y, -x * rate * delta).rotated(basis.x, -y * rate * delta)
	if lead != null:
		dir = WeaponsAim.turn_toward(dir, lead, ASSIST_PULL * Vector2(x, y).length() * delta)
	aim.aim_within_arc(mount, dir)


## One shot from mount i when usable, in arc, loaded and cool, at most once per cooldown.
func _try_fire(i: int, now: int) -> bool:
	var w: WeaponDef = weapon_of(i)
	var row: Dictionary = mount_row(i)
	if not is_usable(i) or now < int(aim.next_fire.get(i, 0)) or not in_arc(i, aim_dir(i)):
		return false
	if int(row.get("ammo", 1)) == 0 or float(row.get("heat", 0.0)) >= w.heat_limit:
		return false
	if bool(row.get("locked", false)):
		return false
	aim.flush(now, true)
	ctx.intents.command({"kind": "fire", "mount_index": i})
	aim.next_fire[i] = now + roundi(w.cooldown * 1000.0)
	return true


func _look(dir: Vector3) -> Basis:
	var rot: Quaternion = ctx.interp.own_rotation()
	var up: Vector3 = ComfortCamera.plane_up(ctx.settings, rot, ComfortCamera.target_rot(ctx))
	return ComfortCamera.look(dir, up, rot * Vector3.FORWARD)


func _update_camera() -> void:
	cam_basis = _look(aim_dir(mount))
	fov = ComfortCamera.fov_deg(ctx.settings, FOV_DEG)
	if not focused:
		return
	_space.place_camera(Transform3D(cam_basis, Vector3.ZERO), fov)
	_space.sync_ships(ctx, ctx.interp.own_rotation() * ship_def.mounts[mount].position)


## Position of a world direction seen from the camera mount, in the turret view's
## coordinates, or null behind it (WeaponsTurretOverlay).
func project(dir: Vector3) -> Variant:
	return _overlay.project(dir)


func _build_view() -> void:
	_view = SubViewportContainer.new()
	_view.stretch = true
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_view)
	var vp: SubViewport = SubViewport.new()
	vp.own_world_3d = true
	RenderQuality.track(vp)
	_view.add_child(vp)
	_space = SpaceView.new()
	_space.ship_scale = SHIP_SCALE
	vp.add_child(_space)
