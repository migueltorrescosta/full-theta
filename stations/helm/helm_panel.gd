class_name HelmPanel
extends StationPanel
## Helm (§5.1, T051, D46): the cockpit forward view (or the chase camera) with the HUD,
## target compass, off-screen arrows, shield ring, thrust envelope and propellant;
## docked, a compact read-out with the compass and the ring (FT-HLM-001).
##
## Sends (net/StationViews.STATION_COMMANDS["helm"]): `helm_input` only when the polled
## sticks, throttle, face or approach change (HelmInputCommand latches, at most every
## INPUT_MS while the sticks move), `helm_select_target` when the shared selection
## changes (a contact, a mark or a named site), `helm_align`, `helm_all_stop`,
## `helm_decoupled`, `set_shield_focus`, and `helm_jump`, `helm_dock` and `helm_undock`
## for the selected site or mark (FT-HLM-013, FT-HLM-016).
## Rules live in sim/: this panel only turns intents into commands.
##
## On a phone (#28) HelmTouch lays the touch controls over the cockpit, landscape-first,
## and the pointer never steers: the sticks do, and a tap selects under the finger. With it
## the panel is in the shared phone frame (in_frame): its pages are HelmTouch's, and the HUD
## keeps its read-outs under the screen's view-top row.

## The controller Helm radial (hold View + right stick, FT-HLM-017): flick toward an
## item and let go.
const RADIAL: Array[String] = [
	"chase_camera", "align", "decoupled", "shield_track", "ping", "dock", "jump"
]
## The six shield faces (FT-HLM-008), ship frame (-Z bow).
const FACES: Dictionary = {
	"shield_fore": Vector3.FORWARD,
	"shield_aft": Vector3.BACK,
	"shield_port": Vector3.LEFT,
	"shield_starboard": Vector3.RIGHT,
	"shield_dorsal": Vector3.UP,
	"shield_ventral": Vector3.DOWN,
}
## "Under the reticle" (§5.0): items within this many pixels of the view centre.
const PICK_PX: float = 48.0
## Stick values are sent in steps of this size, and while they move at most every
## INPUT_MS, so the 90 per second command budget stays free for the rest.
const INPUT_STEP: float = 0.02
const INPUT_MS: int = 33
## Right-stick deflection that picks a radial item.
const RADIAL_DEFLECT: float = 0.5

## The chase camera is on (FT-HLM-002); the HUD stays the same.
var chase: bool = false
## Index in RADIAL of the highlighted radial item, -1 for none.
var radial_pick: int = -1
var view3d: HelmView
var hud: HelmHud
var ring: ShieldRing
## The phone layout (HelmTouch) while the focused panel is on a phone, else null.
var touch_ui: HelmTouch = null

var _container: SubViewportContainer
var _viewport: SubViewport
## The pointer is captured for steering (KB/M) until the menu, a pause, the end of
## the run or a focus loss frees it; a click in the view captures it again.
var _captured: bool = true
var _sent_input: Dictionary = _neutral()
var _sent_input_ms: int = -INPUT_MS
var _sent_target: Dictionary = {}


func _setup() -> void:
	clip_contents = true
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_container.add_child(_viewport)
	view3d = HelmView.new()
	_viewport.add_child(view3d)
	hud = HelmHud.new()
	hud.panel = self
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(hud)
	ring = ShieldRing.new()
	ring.sector_picked.connect(_set_focus.bind(-1))
	add_child(ring)
	gui_input.connect(_on_gui_input)


func _mode_changed() -> void:
	_container.visible = focused
	hud.compact = not focused
	_mode_changed_ring()
	_captured = focused
	_apply_form()


func _mode_changed_ring() -> void:
	# Room for the label under the ring when focused.
	var side: float = 170.0 if focused else 100.0
	ring.size = Vector2(side + (80.0 if focused else 0.0), side + 2.0 * ShieldRing.FONT_SIZE)
	ring.label = focused


## Builds, rebuilds or drops the phone layout for the viewport's form (a rotation).
func _apply_form() -> void:
	var form: LayoutMode.Form = _form()
	var want: bool = focused and LayoutMode.is_phone(form)
	var portrait: bool = form == LayoutMode.Form.PHONE_PORTRAIT
	var rebuilt: bool = false
	if touch_ui != null and (not want or touch_ui.portrait != portrait):
		# The ring lives in the touch layout's page zone: take it back first.
		ring.reparent(self, false)
		ring.size_flags_vertical = Control.SIZE_FILL
		ring.visible = true
		ring.mouse_filter = Control.MOUSE_FILTER_STOP
		hud.visible = true
		_mode_changed_ring()
		remove_child(touch_ui)
		touch_ui.queue_free()
		touch_ui = null
		pages = null
		rebuilt = true
		ctx.matcher.release_all()
	if want and touch_ui == null:
		touch_ui = HelmTouch.new(self, _dispatch, portrait)
		add_child(touch_ui)
		pages = touch_ui.pages
		rebuilt = true
		_captured = false
		var screen: StationScreen = _screen()
		if screen != null and portrait:
			screen.rotate_banner.label.text = TouchText.of(
				HelmTouch.ROTATE_KEY, HelmTouch.ROTATE_TEXT
			)
	# In the frame with the phone layout only. Upright, a joint view keeps its docked panels
	# (the lead's call), which leave the cockpit too short for the view-top row: there Helm
	# keeps the chip strip.
	var screen_now: StationScreen = _screen()
	var docked_upright: bool = portrait and screen_now != null and screen_now.panels.size() >= 2
	in_frame = touch_ui != null and not docked_upright
	var inset: float = touch_ui.view_bottom_inset() if touch_ui != null else 0.0
	_container.offset_bottom = -inset
	hud.offset_bottom = -inset
	if rebuilt:
		_show_pages()


## The screen shows the tabs of the pages just built (it binds them on its own relayout,
## which runs before a rotation rebuilds this layout).
func _show_pages() -> void:
	var screen: StationScreen = _screen()
	if screen == null or not screen.is_inside_tree() or screen.focused_panel() != self:
		return
	var form_now: LayoutMode.Form = LayoutMode.form_of(screen)
	var alone: bool = screen.panels.size() >= 2 and form_now == LayoutMode.Form.PHONE_LANDSCAPE
	screen.frame.show_tabs(form_now, alone)


## The screen's form (LayoutMode.Form), measured on the screen's own size so a screen laid
## out at a set size (tests, a dev seat) gets its layout; desktop outside a screen.
func _form() -> LayoutMode.Form:
	var screen: StationScreen = _screen()
	if not is_inside_tree() or screen == null:
		return LayoutMode.Form.DESKTOP
	var ui_scale: float = 1.0
	var window: Window = get_window()
	if window != null:
		ui_scale = window.content_scale_factor
	var dp: Vector2 = LayoutMode.dp_size(screen.size, ui_scale, LayoutMode.density())
	return LayoutMode.form_for(dp, LayoutMode.coarse_pointer())


## The screen holding this panel, or null.
func _screen() -> StationScreen:
	var node: Node = get_parent()
	while node != null and not node is StationScreen:
		node = node.get_parent()
	return node as StationScreen


## Touch intent events go through the screen like a device's (StationScreen.dispatch).
func _dispatch(ev: Dictionary) -> void:
	var screen: StationScreen = _screen()
	if screen != null:
		screen.dispatch(ev)
	else:
		handle_intent(ev)


func _notification(what: int) -> void:
	if (
		what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT]
		or what == NOTIFICATION_EXIT_TREE
	):
		_captured = false
		_apply_mouse_mode()
	elif what == NOTIFICATION_ENTER_TREE:
		var screen: StationScreen = _screen()
		if screen != null and not screen.menu_requested.is_connected(_free_pointer):
			screen.menu_requested.connect(_free_pointer)
		if screen != null and not screen.resized.is_connected(_apply_form):
			screen.resized.connect(_apply_form)
		_apply_form.call_deferred()


func _process(_delta: float) -> void:
	if ctx == null:
		return
	# A pause, the end of the run (the outcome card, D178) or anything blocking the
	# screen (the menu on any tab, the alert picker) frees the pointer; only a new left
	# click in the view takes it back (D183).
	if (
		ctx.crew.paused.has(ctx.crew.ship)
		or ctx.crew.host_paused
		or ctx.crew.run_over.has(ctx.crew.ship)
		or _overlay_open()
	):
		_captured = false
	_apply_mouse_mode()
	sync_target()
	_send_input()
	if ctx.matcher.is_held("helm_radial"):
		var v: Vector2 = ctx.matcher.stick("RS")
		if v.length() >= RADIAL_DEFLECT:
			radial_pick = radial_index(v)
	if touch_ui != null:
		_captured = false
		touch_ui.update(ring)
	else:
		ring.position = Vector2(size.x - ring.size.x - 12.0, (size.y - ring.size.y) / 2.0)
	ring.show_state(helm_block(), _shield_power())
	if focused:
		view3d.show_state(ctx, chase)
	hud.queue_redraw()


# --- Intents. ---


func handle_intent(ev: Dictionary) -> bool:
	var id: String = ev["id"]
	var pressed: bool = bool(ev.get("pressed", true))
	match id:
		"face", "approach", "helm_pointer":
			# Polled (is_held) and latched into helm_input.
			return true
		"helm_radial":
			if not pressed and radial_pick >= 0:
				run(RADIAL[radial_pick])
			radial_pick = -1
			return true
	if not pressed:
		return false
	if FACES.has(id):
		_set_focus(FACES[id], -1)
		return true
	return run(id)


## Runs one Helm action (a key, a radial item); false for unknown ones.
func run(id: String) -> bool:
	match id:
		"all_stop":
			ctx.intents.command({"kind": "helm_all_stop"})
		"decoupled":
			var on: bool = bool(helm_block().get("decoupled", false))
			ctx.intents.command({"kind": "helm_decoupled", "decoupled": not on})
		"align":
			# D124: with nothing selected Align does nothing (FT-HLM-007).
			if ctx.crew.selection.is_empty():
				ctx.crew.toast.emit("toast.select_first", {})
			else:
				sync_target()
				ctx.intents.command({"kind": "helm_align"})
		"chase_camera":
			chase = not chase
		"shield_track":
			_toggle_track()
		"ping":
			_ping()
		"jump":
			_jump()
		"dock":
			_dock()
		_:
			return false
	return true


## J: jump to the selected site or mark once the bow is on it (FT-HLM-016). The sim
## refuses a jump that isn't faced; the toast only saves the round trip.
func _jump() -> void:
	var s: Dictionary = ctx.crew.selection
	var cmd: Dictionary = {
		"kind": "helm_jump", "target_kind": 0, "target_id": -1, "x": 0.0, "y": 0.0, "z": 0.0
	}
	match s.get("kind", ""):
		"site":
			cmd["target_id"] = int(s["id"])
		"mark":
			var m: Dictionary = ctx.crew.mark_in_slot(int(s["id"]))
			if m.is_empty():
				ctx.crew.toast.emit("toast.jump_select", {})
				return
			var p: Vector3 = ctx.mark_position(m)
			cmd.merge({"target_kind": 1, "x": p.x, "y": p.y, "z": p.z}, true)
		_:
			ctx.crew.toast.emit("toast.jump_select", {})
			return
	var def: ShipDef = ctx.ship_def()
	var local: Variant = ctx.selection_local()
	if def != null and local is Vector3:
		if (local as Vector3).angle_to(Vector3.FORWARD) > def.jump_face_tolerance_rad:
			ctx.crew.toast.emit("toast.jump_face", {})
			return
	ctx.intents.command(cmd)


## H: undock when docked, else dock at the selected site (FT-HLM-013).
func _dock() -> void:
	if int(helm_block().get("docked_site", -1)) >= 0:
		ctx.intents.command({"kind": "helm_undock"})
		return
	var s: Dictionary = ctx.crew.selection
	var site: Dictionary = ctx.picture().find(s)
	if s.get("kind", "") != "site" or not bool(site.get("dockable", false)):
		ctx.crew.toast.emit("toast.dock_select", {})
		return
	ctx.intents.command({"kind": "helm_dock", "site_id": int(s["id"])})


## Sends helm_select_target when the shared selection (or the selected free mark's
## place) differs from what was last sent.
func sync_target() -> void:
	var t: Dictionary = target_command()
	if t == _sent_target:
		return
	_sent_target = t
	if not t.is_empty():
		ctx.intents.command(t)


## The helm_select_target command for the current selection: a contact, a named site, a
## mark's contact when attached, else the mark's point; {} with nothing selected yet, and a
## "none" target once something was selected and the selection was cleared.
func target_command() -> Dictionary:
	var s: Dictionary = ctx.crew.selection
	var cmd: Dictionary = {
		"kind": "helm_select_target",
		"target_ship": -1,
		"site_id": -1,
		"point": false,
		"x": 0.0,
		"y": 0.0,
		"z": 0.0
	}
	match s.get("kind", ""):
		"contact":
			cmd["target_ship"] = int(s["id"])
		"site":
			cmd["site_id"] = int(s["id"])
		"mark":
			var m: Dictionary = ctx.crew.mark_in_slot(int(s["id"]))
			if m.is_empty():
				return cmd if not _sent_target.is_empty() else {}
			if int(m.get("contact", -1)) >= 0:
				cmd["target_ship"] = int(m["contact"])
			else:
				var p: Vector3 = m["pos"]
				cmd["point"] = true
				cmd["x"] = p.x
				cmd["y"] = p.y
				cmd["z"] = p.z
		_:
			return cmd if not _sent_target.is_empty() else {}
	return cmd


## The latched helm_input from the polled axes and holds (sign conventions in
## HelmInputCommand: pitch nose up +, yaw nose to port +, roll to port +).
func input_command() -> Dictionary:
	var m: InputMatcher = ctx.matcher
	var rot: Vector3 = Vector3(-m.axis("helm_pitch"), -m.axis("helm_yaw"), -m.axis("helm_roll"))
	return {
		"kind": "helm_input",
		"rotation": rot.snapped(Vector3.ONE * INPUT_STEP),
		"strafe": snappedf(m.axis("helm_sway"), INPUT_STEP),
		"lift": snappedf(m.axis("helm_heave"), INPUT_STEP),
		"throttle": snappedf(m.axis("helm_surge"), INPUT_STEP),
		"face": m.is_held("face"),
		"approach": m.is_held("approach"),
	}


func _send_input() -> void:
	var cmd: Dictionary = input_command()
	if cmd == _sent_input:
		return
	var now: int = ctx.now_ms()
	var buttons: bool = (
		cmd["face"] != _sent_input["face"] or cmd["approach"] != _sent_input["approach"]
	)
	if not buttons and cmd != _neutral() and now - _sent_input_ms < INPUT_MS:
		return
	_sent_input = cmd
	_sent_input_ms = now
	ctx.intents.command(cmd)


static func _neutral() -> Dictionary:
	return {
		"kind": "helm_input",
		"rotation": Vector3.ZERO,
		"strafe": 0.0,
		"lift": 0.0,
		"throttle": 0.0,
		"face": false,
		"approach": false,
	}


## The radial item a stick direction points at: RADIAL laid clockwise from the top.
static func radial_index(v: Vector2) -> int:
	var a: float = fposmod(atan2(v.x, -v.y), TAU)
	var step: float = TAU / RADIAL.size()
	return int(fposmod(a + step / 2.0, TAU) / step) % RADIAL.size()


func _set_focus(direction: Vector3, track_id: int) -> void:
	ctx.intents.command(
		{"kind": "set_shield_focus", "direction": direction.normalized(), "track_id": track_id}
	)


## Shield track (FT-HLM-010): on for the selected contact, off (keeping the current
## direction) when tracking.
func _toggle_track() -> void:
	var h: Dictionary = helm_block()
	if int(h.get("shield_track", -1)) >= 0:
		_set_focus(h.get("shield_focus", Vector3.FORWARD), -1)
		return
	var s: Dictionary = ctx.crew.selection
	if s.get("kind", "") != "contact":
		ctx.crew.toast.emit("toast.select_contact_first", {})
		return
	var local: Variant = ctx.selection_local()
	var dir: Vector3 = local if local is Vector3 else Vector3.FORWARD
	_set_focus(dir, int(s["id"]))


## Ping from the radial: the item under the reticle, else the selection.
func _ping() -> void:
	var item: Dictionary = item_at(size / 2.0)
	if item.is_empty():
		item = ctx.crew.selection
	if not item.is_empty():
		ctx.intents.ping(item["kind"], int(item["id"]), Vector3.ZERO)


# --- StationPanel. ---


## Contacts and marks under the reticle (the view centre) while the mouse steers or on
## a controller, else under the pointer; nearest first within PICK_PX.
func item_at(screen_pos: Vector2) -> Dictionary:
	if not focused:
		return {}
	var at: Vector2 = size / 2.0 if steering() else screen_pos
	var best: Dictionary = {}
	var best_d: float = PICK_PX
	for e: Dictionary in hud.markers():
		if not e["on_screen"]:
			continue
		var d: float = (e["pos"] as Vector2).distance_to(at)
		if d < best_d:
			best_d = d
			best = {"kind": e["kind"], "id": e["id"]}
	return best


## The cockpit and the turret look forward: a mark attaches to the tapped contact or none
## is placed (FT-SPA-030).
func marks_attach_only() -> bool:
	return focused


## A phone drops the radar column: the radar is a page (#28).
func full_screen() -> bool:
	return is_inside_tree() and LayoutMode.is_phone(LayoutMode.form_of(self))


## The part of the view the HUD may draw its read-outs in, in `control`'s coordinates:
## clear of the phone's rails and controls, else all of `control`.
func hud_area(control: Control) -> Rect2:
	var r: Rect2 = Rect2(Vector2.ZERO, control.size)
	if touch_ui != null and touch_ui.is_inside_tree():
		# Under the screen's view-top row too (selection chip, request chips).
		r = touch_ui.clear_view_in(control).intersection(r)
	# Above the screen's joint switch (a joint view on a phone on its side).
	r.size.y = maxf(r.size.y - bottom_reserve, 0.0)
	return r


## On a phone the view is the part the touch controls leave clear (the view-top row goes
## at its top).
func view_rect() -> Rect2:
	if touch_ui != null and touch_ui.is_inside_tree():
		return touch_ui.content_rect_in(self)
	return super()


func claim_item() -> String:
	return StationViews.CLAIM_FLIGHT


func mouse_steers() -> bool:
	return steering()


## The mouse steers: the focused cockpit, the pointer captured and Ctrl not held.
func steering() -> bool:
	return focused and _captured and not ctx.matcher.is_held("helm_pointer")


## The HELM block, or {} before the first snapshot.
func helm_block() -> Dictionary:
	return ctx.view.blocks.get(StationViews.Section.HELM, {})


## Propellant left as a share of the ship's capacity (ShipDef in content/), or -1 when
## the def is unknown.
func propellant_share() -> float:
	var def: ShipDef = ctx.ship_def()
	var left: float = float(
		ctx.view.blocks.get(StationViews.Section.STATUS, {}).get("propellant", 0.0)
	)
	if def == null or def.propellant_capacity <= 0.0:
		return -1.0
	return clampf(left / def.propellant_capacity, 0.0, 1.0)


func _shield_power() -> float:
	return float(helm_block().get("shield_power", 1.0))


func _free_pointer() -> void:
	_captured = false


## The screen is blocked by the menu (Controls, Settings, Rebind keys), the outcome card
## or the alert picker.
func _overlay_open() -> bool:
	var screen: StationScreen = _screen()
	return screen != null and screen.blocked()


## A click in the view that selected nothing captures the pointer again.
func _on_gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if (
		mb != null
		and mb.pressed
		and mb.button_index == MOUSE_BUTTON_LEFT
		and focused
		and touch_ui == null
		and not _overlay_open()
	):
		_captured = true


## CAPTURED only while the mouse steers (KB/M); VISIBLE for everything else.
func mouse_mode_wanted() -> Input.MouseMode:
	if ctx != null and steering() and ctx.matcher.device == IntentTable.KBM:
		return Input.MOUSE_MODE_CAPTURED
	return Input.MOUSE_MODE_VISIBLE


func _apply_mouse_mode() -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var want: Input.MouseMode = mouse_mode_wanted()
	if Input.mouse_mode != want:
		Input.mouse_mode = want
