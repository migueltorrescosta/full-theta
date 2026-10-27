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
## On a phone (#28, owner pick B) WeaponsTouch puts the view between docked thumb rails
## (landscape) or above two rows of buttons (upright): a drag aims, FIRE holds `fire`, and
## the mount, claim, ammo and Guided buttons send the same intents as the keys. Tablet
## and desktop layouts don't change.

## Vertical field of view (degrees).
const FOV_DEG: float = 60.0
## Aim turn rate at full deflection (rad/s, PROVISIONAL).
const AIM_RATE: float = 0.8
## Aim points go out at most this often (ms), when they moved more than AIM_SEND_M (m).
const AIM_SEND_MS: int = 50
const AIM_SEND_M: float = 1.0
## Controller aim assist (FT-SIM-015, PROVISIONAL, asked of the owner): within
## ASSIST_CONE (rad) of the selected contact's lead point, while the stick moves, the
## turn rate drops to ASSIST_SLOW and the aim drifts to the lead at up to ASSIST_PULL
## (rad/s at full deflection). Never with KB/M, never with the stick at rest.
const ASSIST_CONE: float = 0.07
const ASSIST_SLOW: float = 0.6
const ASSIST_PULL: float = 0.1
## Contact ship models: ProceduralShip is about 5 units long; ships are about 50 m.
const SHIP_SCALE: float = 10.0
const FONT_SIZE: int = 15
const RETICLE_R: float = 18.0
const BRACKET: float = 10.0
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

## Mount index -> aim point (m); a mount without one rests on its barrel.
var _aims: Dictionary = {}
var _sent: Dictionary = {}
var _dirty: Dictionary = {}
var _next_aim_ms: int = 0
var _next_fire: Dictionary = {}
var _firing: bool = false
var _firing_all: bool = false
## Brackets in view this frame (step), for drawing and item_at: {"item" (ContactPicture's),
## "pos", "chip", "rect" (bracket and chip)}.
var _targets: Array[Dictionary] = []
var _view: SubViewportContainer
## The turret camera's view, from the camera mount.
var _space: SpaceView
var _overlay: Control
## The phone arrangement while the form is a phone's and the panel is focused, else null.
var _touch: WeaponsTouch = null
var _screen: StationScreen = null


func _setup() -> void:
	ship_def = ctx.ship_def()
	_build_view()
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	mount = _first_mount()


func _ready() -> void:
	var n: Node = get_parent()
	while n != null and not n is StationScreen:
		n = n.get_parent()
	_screen = n as StationScreen
	if _screen != null:
		_screen.form_changed.connect(func(_f: LayoutMode.Form) -> void: _apply_form())
	_apply_form()


func _mode_changed() -> void:
	_view.visible = focused
	if not focused:
		_firing = false
		_firing_all = false
	_apply_form()


## Alone and focused on a phone in landscape, the panel draws its radar in its rail and
## takes the whole screen (#28).
func full_screen() -> bool:
	return focused and mount_count() > 0 and phone_form() == LayoutMode.Form.PHONE_LANDSCAPE


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
	if want:
		var alone: bool = _screen == null or _screen.panels.size() == 1
		_touch = WeaponsTouch.new(self, form as LayoutMode.Form, alone)
		add_child(_touch)
		_touch.take_view(_view, _overlay)
		_touch.refresh()


## The phone arrangement, or null (tests and shots).
func touch() -> WeaponsTouch:
	return _touch


# --- Touch (#28): the rails send the same intents as the keys and the pad. ---


## A rail button's press intent (`mount_next`, `ammo_next`, `fire_guided`).
func touch_press(id: String) -> void:
	handle_intent({"id": id, "pressed": true, "device": TOUCH})


## A held rail button (`fire`): pressed on the finger's down, released on its up.
func touch_hold(down: bool, id: String) -> void:
	handle_intent({"id": id, "pressed": down, "device": TOUCH})


## Claim or Release: the screen's common `claim` intent.
func touch_claim() -> void:
	if _screen != null:
		_screen.dispatch({"id": "claim", "target": "screen", "pressed": true, "device": TOUCH})


## A finger dragged `relative` px across the view turns the camera mount's aim by the angle
## it covers on screen (drag right: aim right). No aim assist (controller only, D25).
func touch_aim(relative: Vector2) -> void:
	if mount_count() == 0:
		return
	var f: float = _focal()
	var yaw: float = relative.x / f
	var pitch: float = relative.y / f * (-1.0 if ctx.matcher.invert_pitch else 1.0)
	var dir: Vector3 = aim_dir(mount)
	var basis: Basis = _look(dir)
	_aim_within_arc(dir.rotated(basis.y, -yaw).rotated(basis.x, -pitch))


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
	_flush_aims(now, false)
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
	_layout_targets()
	_overlay.queue_redraw()
	if _touch != null:
		_touch.refresh()


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
	for t: Dictionary in _targets:
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
	return types[clampi(int(_mount_row(i).get("ammo_type", 0)), 0, types.size() - 1)]


## Switches the camera mount to the next (or previous) ammunition type it has; false, with
## a toast, when it has only one or this client may not use it.
func cycle_ammo(direction: int) -> bool:
	if mount_count() == 0 or not is_usable(mount):
		return false
	var n: int = ship_def.mounts[mount].ammo_types().size()
	if n < 2:
		ctx.crew.toast.emit("toast.one_ammo", {})
		return false
	var now: int = int(_mount_row(mount).get("ammo_type", 0))
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
	var row: Dictionary = _mount_row(i)
	if now < int(_next_fire.get(i, 0)) or int(row.get("ammo", 1)) == 0:
		return false
	var at: Vector3 = ctx.interp.contact_position(int(goal["target"]))
	_aims[i] = at
	_dirty[i] = true
	if not _in_arc(i, aim_dir(i)):
		ctx.crew.toast.emit("toast.guided_out_of_arc", {})
		return false
	_flush_aims(now, true)
	ctx.intents.command({"kind": "fire_guided", "mount_index": i, "target": int(goal["target"])})
	_next_fire[i] = now + roundi(w.cooldown * 1000.0)
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
func _mount_row(i: int) -> Dictionary:
	var rows: Array = ctx.view.blocks.get(StationViews.Section.MOUNTS, {}).get("mounts", [])
	return rows[i] if i < rows.size() else {}


func is_mine(i: int) -> bool:
	return int(_holder(i).get("session", -1)) == ctx.crew.session


## Free or mine: this client may aim and fire it.
func is_usable(i: int) -> bool:
	return _holder(i).is_empty() or is_mine(i)


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


# --- Aim. ---


## The position of mount i (m).
func _mount_position(i: int) -> Vector3:
	return ctx.interp.own_position() + ctx.interp.own_rotation() * ship_def.mounts[i].position


## Where mount i aims (world unit vector from the mount): its aim point, else its barrel.
func aim_dir(i: int) -> Vector3:
	var rot: Quaternion = ctx.interp.own_rotation()
	if _aims.has(i):
		var to: Vector3 = ctx.interp.offset_to(_aims[i]) - rot * ship_def.mounts[i].position
		if to.length_squared() > 1e-6:
			return to.normalized()
	return rot * _barrel(i)


## Mount i's barrel in the ship frame (the MOUNTS block; its rest direction before data).
func _barrel(i: int) -> Vector3:
	var b: Variant = _mount_row(i).get("barrel")
	return (b as Vector3).normalized() if b is Vector3 else ship_def.mounts[i].forward


## Aims mount i along `dir` (world unit vector): a point at the weapon's range.
func set_aim_dir(i: int, dir: Vector3) -> void:
	var p: Vector3 = _mount_position(i) + dir * weapon_of(i).max_range
	_aims[i] = p
	if not _sent.has(i) or (_sent[i] as Vector3).distance_to(p) > AIM_SEND_M:
		_dirty[i] = true


## The aim direction from mount i (world unit) that leads `contact`, or null when it is
## unknown or out of reach (Lead.intercept_time, FT-SIM-014).
func lead_dir(i: int, contact: int) -> Variant:
	if contact not in ctx.interp.contact_ids():
		return null
	var rot: Quaternion = ctx.interp.own_rotation()
	var rel: Vector3 = (
		ctx.interp.offset_to(ctx.interp.contact_position(contact))
		- rot * ship_def.mounts[i].position
	)
	var model: Dictionary = ctx.view.contacts.get("model", {})
	var vel: Vector3i = model[contact][1] if model.has(contact) else Vector3i.ZERO
	var own: Vector3i = ctx.view.kin.get("vel", Vector3i.ZERO)
	var rel_vel: Vector3 = Vector3(vel - own) / NetCodec.VEL_Q
	var speed: float = weapon_of(i).projectile_speed
	if speed <= 0.0:
		# A beam arrives at once: aim straight at the contact.
		return rel.normalized() if rel.length_squared() > 1e-6 else null
	var t: float = Lead.intercept_time(rel, rel_vel, speed)
	if t < 0.0:
		return null
	var aim: Vector3 = Lead.aim_point(rel, rel_vel, t)
	return aim.normalized() if aim.length_squared() > 1e-6 else null


## True when a world direction from mount i lies in its arc (FT-SIM-011).
func _in_arc(i: int, dir: Vector3) -> bool:
	var m: MountDef = ship_def.mounts[i]
	return m.forward.angle_to(ctx.interp.own_rotation().inverse() * dir) <= m.arc_half_angle


func selected_contact() -> int:
	var s: Dictionary = ctx.crew.selection
	return int(s["id"]) if s.get("kind", "") == "contact" else -1


## The out-of-arc line (FT-WPN-005): "H2 out of arc: turn 4 high", the bow direction that
## brings the selected contact onto the mount's rest direction; "" when in arc or none.
func out_of_arc_text() -> String:
	var id: int = selected_contact()
	if mount_count() == 0 or id not in ctx.interp.contact_ids():
		return ""
	var m: MountDef = ship_def.mounts[mount]
	var local: Vector3 = (
		ctx.interp.local(ctx.interp.offset_to(ctx.interp.contact_position(id))) - m.position
	)
	if local.length_squared() < 1e-6 or m.forward.angle_to(local) <= m.arc_half_angle:
		return ""
	var swing: Vector3 = Quaternion(m.forward, local.normalized()) * Vector3.FORWARD
	return tr("weapons.out_of_arc").format(
		{"target": ctx.view.callsign(id), "dir": _clock_words(swing)}
	)


## One line per mount (FT-WPN-004): number, id, state, heat, ammo, claimer; the camera
## mount marked.
func mount_rows() -> Array[String]:
	var out: Array[String] = []
	for i: int in mount_count():
		var m: MountDef = ship_def.mounts[i]
		var row: Dictionary = _mount_row(i)
		var w: WeaponDef = weapon_of(i)
		var ammo: int = int(row.get("ammo", w.ammo_capacity))
		var ammo_text: String = "∞" if ammo < 0 else "%d/%d" % [ammo, w.ammo_capacity]
		var holder: Dictionary = _holder(i)
		var who: String = tr("weapons.free")
		if is_mine(i):
			who = tr("weapons.you")
		elif not holder.is_empty():
			who = str(holder.get("name", ""))
		var heat: float = float(row.get("heat", 0.0)) / w.heat_limit
		(
			out
			. append(
				(
					"%s%d %s · %s · %s · %s · %s"
					% [
						"> " if i == mount else "  ",
						i + 1,
						m.id,
						tr("weapons." + _state(i)),
						tr("weapons.heat") % roundi(heat * 100.0),
						ammo_text,
						who,
					]
				)
			)
		)
	return out


## Mount i on two lines for the phone's mount button: "1 bow · ready", "heat 15% · 380/400".
func mount_text(i: int) -> String:
	if i < 0 or i >= mount_count():
		return ""
	var w: WeaponDef = weapon_of(i)
	var row: Dictionary = _mount_row(i)
	var ammo: int = int(row.get("ammo", w.ammo_capacity))
	var heat: float = float(row.get("heat", 0.0)) / w.heat_limit
	return (
		"%d %s · %s\n%s · %s"
		% [
			i + 1,
			ship_def.mounts[i].id,
			tr("weapons." + _state(i)),
			tr("weapons.heat") % roundi(heat * 100.0),
			"∞" if ammo < 0 else "%d/%d" % [ammo, w.ammo_capacity],
		]
	)


## The name of the player who holds mount i, or "".
func holder_name(i: int) -> String:
	return str(_holder(i).get("name", ""))


## The camera mount's selected ammunition by name ("standard" for a mount with one).
func ammo_name() -> String:
	if mount_count() == 0 or ship_def.mounts[mount].alt_weapons.is_empty():
		return tr("weapons.ammo_standard")
	return weapon_of(mount).display_name


## The target line ("Target H2 · 4 high · mid"), or "".
func target_text() -> String:
	return _target_line()


## What other stations' work says of the selected target (FT-WPN-007, P7, P8): its
## weak points by name, how the selected ammunition fares against its resistances, the open
## hack window and the track quality. Each line exists only while the server sends its feed,
## that is while its toggle is on or Science and Relay share this view.
func feed_lines() -> Array[String]:
	var out: Array[String] = []
	var id: int = selected_contact()
	var feeds: Dictionary = ctx.view.blocks.get(StationViews.Section.FEEDS, {})
	if id < 0 or feeds.is_empty():
		return out
	var flag: int = contract_flag(id)
	if flag != 0:
		out.append(tr("weapons.flag_line_%d" % flag))
	for row: Dictionary in feeds["weak"]:
		if row["contact"] != id:
			continue
		var def: ShipDef = ScienceLookup.ship_class(row["class_id"])
		var names: PackedStringArray = PackedStringArray()
		for i: int in 32:
			if (int(row["weak_mask"]) >> i) & 1 == 1 and def != null and i < def.subsystems.size():
				names.append(String(def.subsystems[i].id))
		if not names.is_empty():
			out.append(tr("weapons.weak") % ", ".join(names))
		if mount_count() > 0:
			var kind: StringName = weapon_of(mount).damage_type
			for r: Dictionary in row["resist"]:
				if r["type"] == ScienceView.code(kind):
					out.append(tr("weapons.rating") % [String(kind), float(r["factor"])])
	for w: Dictionary in feeds["windows"]:
		if w["target"] == id:
			out.append(tr("weapons.window") % ceili(float(w["left"])))
	for t: Dictionary in feeds["tracks"]:
		if t["contact"] == id:
			var q: float = clampf(float(t["quality"]), 0.0, 1.0)
			var bar: String = "#".repeat(roundi(q * 8.0)) + "-".repeat(8 - roundi(q * 8.0))
			out.append(tr("weapons.track") % [roundi(q * 100.0), bar])
	return out


## The contract flag a contact carries (P9, FT-MIS-042): 1 disable ("do not destroy"), 2
## protect, 0 none. The FEEDS block holds the rows only while the contract flags are shared
## with this view (the P9 toggle, or Comms on this screen).
func contract_flag(contact: int) -> int:
	var feeds: Dictionary = ctx.view.blocks.get(StationViews.Section.FEEDS, {})
	for row: Dictionary in feeds.get("flags", []):
		if int(row["contact"]) == contact:
			return int(row["flag"])
	return 0


## The ammunition line (FT-WPN-006): the selected type, "standard" for a mount with one.
func _ammo_text() -> String:
	if mount_count() == 0 or ship_def.mounts[mount].alt_weapons.is_empty():
		return tr("weapons.ammo") % tr("weapons.ammo_standard")
	return tr("weapons.ammo") % weapon_of(mount).display_name


# --- Internals. ---


func _holder(i: int) -> Dictionary:
	return ctx.crew.claims.get("%s:%d" % [StationViews.CLAIM_MOUNT, i], {})


func _first_mount() -> int:
	for i: int in mount_count():
		if is_mine(i):
			return i
	for i: int in mount_count():
		if is_usable(i):
			return i
	return 0


func _state(i: int) -> String:
	var row: Dictionary = _mount_row(i)
	var w: WeaponDef = weapon_of(i)
	if row.is_empty():
		return "no_data"
	if int(row["ammo"]) == 0:
		return "empty"
	if bool(row.get("locked", false)):
		return "locked"
	if float(row["heat"]) >= w.heat_limit:
		return "hot"
	if float(row["cooldown"]) > 0.0:
		return "reloading"
	return "ready"


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
		lead = lead_dir(mount, selected_contact())
		if lead != null and dir.angle_to(lead) > ASSIST_CONE:
			lead = null
	if lead != null:
		rate *= ASSIST_SLOW
	dir = dir.rotated(basis.y, -x * rate * delta).rotated(basis.x, -y * rate * delta)
	if lead != null:
		dir = _turn_toward(dir, lead, ASSIST_PULL * Vector2(x, y).length() * delta)
	_aim_within_arc(dir)


## Aims the camera mount along `dir` (world), stopped at the arc edge: input stops there;
## a held aim the ship turns out of arc stays (FT-WPN-009).
func _aim_within_arc(dir: Vector3) -> void:
	var m: MountDef = ship_def.mounts[mount]
	var rot: Quaternion = ctx.interp.own_rotation()
	var local: Vector3 = rot.inverse() * dir
	if m.forward.angle_to(local) > m.arc_half_angle:
		dir = rot * _turn_toward(m.forward, local, m.arc_half_angle)
	set_aim_dir(mount, dir.normalized())


func _flush_aims(now: int, force: bool) -> void:
	if _dirty.is_empty() or (now < _next_aim_ms and not force):
		return
	for i: int in _dirty:
		var p: Vector3 = _aims[i]
		ctx.intents.command(
			{"kind": "aim_mount", "mount_index": i, "aim_x": p.x, "aim_y": p.y, "aim_z": p.z}
		)
		_sent[i] = p
	_dirty.clear()
	_next_aim_ms = now + AIM_SEND_MS


## One shot from mount i when usable, in arc, loaded and cool, at most once per cooldown.
func _try_fire(i: int, now: int) -> bool:
	var w: WeaponDef = weapon_of(i)
	var row: Dictionary = _mount_row(i)
	if not is_usable(i) or now < int(_next_fire.get(i, 0)) or not _in_arc(i, aim_dir(i)):
		return false
	if int(row.get("ammo", 1)) == 0 or float(row.get("heat", 0.0)) >= w.heat_limit:
		return false
	if bool(row.get("locked", false)):
		return false
	_flush_aims(now, true)
	ctx.intents.command({"kind": "fire", "mount_index": i})
	_next_fire[i] = now + roundi(w.cooldown * 1000.0)
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


## Position of a world direction seen from the camera mount, in the turret view's (the
## overlay's) coordinates, or null behind it.
func project(dir: Vector3) -> Variant:
	var c: Vector3 = cam_basis.transposed() * dir
	if c.z > -1e-4:
		return null
	return _overlay.size / 2.0 + Vector2(c.x, -c.y) * _focal() / -c.z


## The turret view's focal length (px): its half height over tan(fov / 2).
func _focal() -> float:
	return maxf(_overlay.size.y / 2.0, 1.0) / tan(deg_to_rad(fov) / 2.0)


func _build_view() -> void:
	_view = SubViewportContainer.new()
	_view.stretch = true
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_view)
	var vp: SubViewport = SubViewport.new()
	vp.own_world_3d = true
	_view.add_child(vp)
	_space = SpaceView.new()
	_space.ship_scale = SHIP_SCALE
	vp.add_child(_space)


## The chip text of an item: "H2 4 high 2.3km", and a contact a contract flags names its
## flag ("[disable]", "[protect]", P9).
func target_chip(it: Dictionary) -> String:
	var chip: String = ChipText.chip(it["label"], it["local"])
	var flag: int = contract_flag(int(it["id"])) if it["kind"] == "contact" else 0
	if flag != 0:
		chip += " [%s]" % tr("weapons.flag_%d" % flag)
	return chip


## Brackets of the contacts and marks in view, with their chips and hit rectangles.
func _layout_targets() -> void:
	_targets.clear()
	if not focused:
		return
	var font: Font = get_theme_default_font()
	var rot: Quaternion = ctx.interp.own_rotation()
	var m: MountDef = ship_def.mounts[mount]
	for it: Dictionary in ctx.picture().items:
		if it["kind"] == "point":
			continue
		var p: Variant = project(rot * ((it["local"] as Vector3) - m.position).normalized())
		if p == null:
			continue
		var chip: String = target_chip(it)
		var sz: Vector2 = font.get_string_size(chip, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		var at: Vector2 = (p as Vector2) + Vector2(BRACKET + 6.0, 4.0 - FONT_SIZE)
		var r: Rect2 = Rect2((p as Vector2) - Vector2.ONE * BRACKET, Vector2.ONE * BRACKET * 2.0)
		_targets.append({"item": it, "pos": p, "chip": chip, "rect": r.merge(Rect2(at, sz))})


func _draw_overlay() -> void:
	var font: Font = get_theme_default_font()
	if mount_count() == 0:
		_text(font, Vector2(16, 28), tr("weapons.no_mounts"), Palette.color("text_dim"))
		return
	if focused:
		_draw_turret(font)
	# On a phone the rails show the camera mount, its ammo and its claim (WeaponsTouch).
	var rows: Array[String] = mount_rows()
	var lines: Array[String] = []
	var bright: int = mount
	for i: int in rows.size():
		if _touch == null or i != mount:
			lines.append(rows[i])
	if _touch != null:
		bright = -1
	var target: String = _target_line()
	if target != "" and (_touch == null or _touch.target_label == null):
		lines.append(target)
	if focused:
		lines.append_array(feed_lines())
	var arc: String = out_of_arc_text()
	if focused:
		if _touch == null:
			lines.append(_ammo_text())
			if _hint() != "":
				lines.append(_hint())
		if arc != "":
			_text(
				font,
				arc_warning_rect(font, arc).position + Vector2(0, FONT_SIZE),
				arc,
				Palette.color("warn")
			)
	elif arc != "":
		lines.append(arc)
	var line_h: float = FONT_SIZE + 6.0
	var y0: float = (
		12.0 + FONT_SIZE if docked else _overlay.size.y - 12.0 - line_h * (lines.size() - 1)
	)
	for k: int in lines.size():
		var col: Color = Palette.color("text") if k == bright else Palette.color("text_dim")
		if lines[k] == arc:
			col = Palette.color("warn")
		_text(font, Vector2(12.0, y0 + k * line_h), lines[k], col)


## Where the out-of-arc warning goes (FT-WPN-005): centred near the top of the view, moved
## down past any bracket or chip it would cover (#28: it hid the U3 chip). The rectangle's
## top is the text's top; the baseline is FONT_SIZE lower.
func arc_warning_rect(font: Font, arc: String) -> Rect2:
	var sz: Vector2 = font.get_string_size(arc, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var r: Rect2 = Rect2((_overlay.size.x - sz.x) / 2.0, 48.0 - FONT_SIZE, sz.x, FONT_SIZE + 6.0)
	for _pass: int in _targets.size():
		var clear: bool = true
		for t: Dictionary in _targets:
			var hit: Rect2 = t["rect"]
			if hit.intersects(r):
				r.position.y = hit.end.y + 4.0
				clear = false
		if clear:
			break
	return r


func _draw_turret(font: Font) -> void:
	var rot: Quaternion = ctx.interp.own_rotation()
	var m: MountDef = ship_def.mounts[mount]
	# The arc edge: the cone of half-angle arc_half_angle around the rest direction.
	var axis: Vector3 = m.forward.cross(Vector3.UP if absf(m.forward.y) < 0.9 else Vector3.RIGHT)
	var edge: Vector3 = m.forward.rotated(axis.normalized(), m.arc_half_angle)
	var prev: Variant = null
	for k: int in 65:
		var p: Variant = project(rot * edge.rotated(m.forward, TAU * k / 64.0))
		if p != null and prev != null:
			_overlay.draw_line(prev, p, Palette.color("accent") * Color(1, 1, 1, 0.7), 1.5, true)
		prev = p
	for t: Dictionary in _targets:
		_draw_item(font, t)
	var lead: Variant = lead_dir(mount, selected_contact())
	if lead != null:
		var p: Variant = project(lead)
		if p != null:
			var col: Color = Palette.color("selected")
			_overlay.draw_polyline(Palette.shape_points("diamond", p, 7.0), col, 2.0, true)
	var bp: Variant = project(rot * _barrel(mount))
	if bp != null:
		_overlay.draw_arc(bp, 5.0, 0.0, TAU, 16, Palette.color("ok"), 2.0, true)
	var c: Vector2 = _overlay.size / 2.0
	var rc: Color = Palette.color("text")
	_overlay.draw_arc(c, RETICLE_R, 0.0, TAU, 32, rc, 1.5, true)
	for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		_overlay.draw_line(c + d * (RETICLE_R + 4.0), c + d * (RETICLE_R + 12.0), rc, 1.5, true)


func _draw_item(font: Font, t: Dictionary) -> void:
	var it: Dictionary = t["item"]
	var p: Vector2 = t["pos"]
	var sel: bool = ctx.crew.is_selected(it["kind"], it["id"])
	var col: Color = Palette.color("selected") if sel else Palette.item_color(it)
	var flag: int = contract_flag(int(it["id"])) if it["kind"] == "contact" else 0
	if flag != 0 and not sel:
		col = Palette.color("warn") if flag == 1 else Palette.color("ok")
	if it["kind"] == "mark":
		_overlay.draw_polyline(Palette.shape_points("diamond", p, BRACKET), col, 1.5, true)
	else:
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var q: Vector2 = p + corner * BRACKET
			_overlay.draw_line(q, q - Vector2(corner.x * 5.0, 0), col, 2.0 if sel else 1.5)
			_overlay.draw_line(q, q - Vector2(0, corner.y * 5.0), col, 2.0 if sel else 1.5)
	_text(font, p + Vector2(BRACKET + 6.0, 4.0), t["chip"], col)
	var pulse: float = float(it.get("pulse", 0.0))
	if pulse > 0.0:
		var pc: Color = Palette.color("ping")
		pc.a = pulse
		_overlay.draw_arc(p, BRACKET + 4.0 + (1.0 - pulse) * 22.0, 0.0, TAU, 32, pc, 2.0, true)


## "Target H2 · 4 high · mid", or "".
func _target_line() -> String:
	var id: int = selected_contact()
	if id not in ctx.interp.contact_ids():
		return ""
	var local: Vector3 = ctx.interp.local(ctx.interp.offset_to(ctx.interp.contact_position(id)))
	return tr("weapons.target") % ChipText.chip(ctx.view.callsign(id), local)


func _hint() -> String:
	var holder: Dictionary = _holder(mount)
	if is_mine(mount):
		return ""
	if holder.is_empty():
		var keys: PackedStringArray = ctx.settings.bindings.bindings("claim", ctx.matcher.device)
		return tr("weapons.hint_claim") % BindingText.describe_all(keys)
	return tr("weapons.held_by") % str(holder.get("name", ""))


func _text(font: Font, base: Vector2, text: String, col: Color) -> void:
	Palette.draw_outlined(_overlay, font, base, text, FONT_SIZE, col)


## "4 high" with its height word translated (ChipText's words).
static func _clock_words(local: Vector3) -> String:
	var words: PackedStringArray = Callout.clock_height(local).split(" ")
	words[-1] = String(TranslationServer.translate("callout." + words[-1]))
	return " ".join(words)


static func _turn_toward(from: Vector3, to: Vector3, max_angle: float) -> Vector3:
	var angle: float = from.angle_to(to)
	if angle <= max_angle:
		return to
	var axis: Vector3 = from.cross(to)
	if axis.length_squared() < 1e-12:
		axis = from.cross(Vector3.UP if absf(from.y) < 0.9 else Vector3.RIGHT)
	return from.rotated(axis.normalized(), max_angle).normalized()
