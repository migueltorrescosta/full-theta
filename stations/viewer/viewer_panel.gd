class_name ViewerPanel
extends StationPanel
## The main screen (§5.8, FT-MSC-001, FT-MSC-003, FT-MSC-004): the forward view, a wide
## disc radar along the bottom and a callsign rail with clock and range band between
## them; pings and marks drawn large. Read-only: viewers only watch (the server
## refuses their pings, marks and commands).
##
## The forward camera sits at the bow and rolls with the deck plane, or, with comfort
## on, keeps the selected target ship's deck or the player's cosmetic reference plane
## level (FT-STN-017, D124). It switches to a chase camera while the ship is
## decoupled or rolls faster than CHASE_ROLL_DEG_S, and back once the roll has stayed
## under FORWARD_ROLL_DEG_S for FORWARD_AFTER_MS. The chase camera follows the bow but
## not the roll, so a fast roll shows the ship turning rather than the sky spinning.
## The other views (FT-MSC-002) come with the Captain in #10.

## Auto-chase thresholds (PROVISIONAL, approved by the owner in #7).
const CHASE_ROLL_DEG_S: float = 45.0
const FORWARD_ROLL_DEG_S: float = 30.0
const FORWARD_AFTER_MS: int = 1500
## Chase camera behind and above the ship (m, the procedural ship is about 5 m long).
const CHASE_BACK_M: float = 14.0
const CHASE_UP_M: float = 3.5
## The chase camera's roll eases back to the deck this fast once the roll is calm (1/s).
const CHASE_LEVEL_RATE: float = 0.6
## Vertical field of view (degrees), before comfort narrows it.
const FOV_DEG: float = 70.0
const RADAR_SHARE: float = 0.4
const RAIL_HEIGHT: float = 30.0
const FONT_SIZE: int = 15

## True while the chase camera is up.
var chase: bool = false
var camera: Camera3D
var radar: DiscRadar

var _calm_since: int = -1
## The chase camera's up; ZERO until the first chase frame seeds it from the ship (D124).
var _chase_up: Vector3 = Vector3.ZERO
var _viewport: SubViewport
## The forward view; only contacts with a NEAR orientation (within 2 km) are drawn.
var _space: SpaceView
var _own: Node3D
var _overlay: Control
var _rail: Control
var _items: Array[Dictionary] = []


func full_screen() -> bool:
	return true


func radar_orbitable() -> bool:
	return false


func _setup() -> void:
	clip_contents = true
	var rows: VBoxContainer = VBoxContainer.new()
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.add_theme_constant_override("separation", 0)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rows)
	var view: SubViewportContainer = SubViewportContainer.new()
	view.stretch = true
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.size_flags_stretch_ratio = (1.0 - RADAR_SHARE) / RADAR_SHARE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(view)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	view.add_child(_viewport)
	_space = SpaceView.new()
	_space.near_only = true
	_viewport.add_child(_space)
	camera = _space.camera
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	view.add_child(_overlay)
	_rail = Control.new()
	_rail.custom_minimum_size = Vector2(0, RAIL_HEIGHT)
	_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail.draw.connect(_draw_rail)
	rows.add_child(_rail)
	radar = DiscRadar.new()
	radar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	radar.tilt_deg = DiscRadar.TILT_MIN
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(radar)


func _process(_delta: float) -> void:
	update_view(get_process_delta_time())


## Camera mode, cameras, models, overlay, rail and radar for this frame (tests call it).
func update_view(delta: float) -> void:
	var now: int = ctx.now_ms()
	var status: Dictionary = ctx.view.blocks.get(StationViews.Section.STATUS, {})
	update_mode(bool(status.get("decoupled", false)), roll_rate_deg_s(), now)
	_items = ctx.picture().items
	var ship: Basis = Basis(ctx.interp.own_rotation())
	_place_camera(ship, delta)
	_space.sync_ships(ctx)
	radar.set_picture(ctx.picture(), ctx.crew.selection)
	_overlay.queue_redraw()
	_rail.queue_redraw()


## The own ship's roll rate (degrees per second) from the KIN section (body frame).
func roll_rate_deg_s() -> float:
	var ang: Vector3 = NetCodec.ang_of(ctx.view.kin.get("ang", Vector3i.ZERO))
	return absf(rad_to_deg(ang.z))


## Auto-chase (FT-MSC-001): chase while decoupled or rolling fast; forward again once
## the roll stayed calm for FORWARD_AFTER_MS.
func update_mode(decoupled: bool, roll_deg_s: float, now_ms: int) -> void:
	if decoupled or roll_deg_s > CHASE_ROLL_DEG_S:
		chase = true
		_calm_since = -1
	elif chase and roll_deg_s < FORWARD_ROLL_DEG_S:
		if _calm_since < 0:
			_calm_since = now_ms
		elif now_ms - _calm_since >= FORWARD_AFTER_MS:
			chase = false
			_calm_since = -1
	else:
		_calm_since = -1


## World axes centred on the own ship (minimum image offsets, D124). The forward camera's
## roll and field of view follow comfort (ComfortCamera, FT-STN-017).
func _place_camera(ship: Basis, delta: float) -> void:
	var fwd: Vector3 = -ship.z
	var fov: float = ComfortCamera.fov_deg(ctx.settings, FOV_DEG)
	if chase:
		if _chase_up == Vector3.ZERO:
			_chase_up = ship.y
		var calm: bool = roll_rate_deg_s() < FORWARD_ROLL_DEG_S
		var level: float = clampf(delta * CHASE_LEVEL_RATE, 0.0, 1.0) if calm else 0.0
		var b: Basis = ComfortCamera.look(fwd, _chase_up.lerp(ship.y, level), ship.y)
		_chase_up = b.y
		_space.place_camera(Transform3D(b, b.z * CHASE_BACK_M + b.y * CHASE_UP_M), fov)
	else:
		_chase_up = ship.y
		var rot: Quaternion = ship.get_rotation_quaternion()
		var up: Vector3 = ComfortCamera.plane_up(ctx.settings, rot, ComfortCamera.target_rot(ctx))
		_space.place_camera(Transform3D(ComfortCamera.look(fwd, up, ship.y), fwd * 3.0), fov)
	if chase and _own == null:
		# Built on the first chase (the first ship model bakes the AO).
		_own = _space.copy_ship()
	if _own != null:
		_own.visible = chase
		_own.transform = Transform3D(ship, Vector3.ZERO)


## Brackets and chips on contacts, big diamonds on marks, big rings on pings (FT-MSC-003).
func _draw_overlay() -> void:
	var font: Font = get_theme_default_font()
	for it: Dictionary in _items:
		var world: Vector3 = it["world"]
		if camera.is_position_behind(world):
			continue
		var p: Vector2 = camera.unproject_position(world)
		if not Rect2(Vector2.ZERO, _overlay.size).grow(40.0).has_point(p):
			continue
		var pulse: float = float(it.get("pulse", 0.0))
		var col: Color = Palette.item_color(it)
		match str(it["kind"]):
			"contact":
				_bracket(p, 14.0, col, ctx.crew.is_selected(it["kind"], it["id"]))
				var chip: String = ChipText.chip(it["label"], it["local"])
				_text(font, p + Vector2(18.0, -6.0), chip, col)
			"mark":
				var pts: PackedVector2Array = Palette.shape_points("diamond", p, 14.0)
				_overlay.draw_polyline(pts, col, 3.0, true)
				_text(font, p + Vector2(18.0, -6.0), it["label"], col)
		if pulse > 0.0:
			var ping: Color = Palette.color("ping")
			ping.a = pulse
			_overlay.draw_arc(p, 20.0 + (1.0 - pulse) * 60.0, 0.0, TAU, 48, ping, 4.0, true)


func _bracket(p: Vector2, r: float, col: Color, selected: bool) -> void:
	var w: float = 3.0 if selected else 2.0
	var c: Color = Palette.color("selected") if selected else col
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var corner: Vector2 = p + Vector2(sx, sy) * r
			_overlay.draw_line(corner, corner - Vector2(sx * r * 0.5, 0.0), c, w)
			_overlay.draw_line(corner, corner - Vector2(0.0, sy * r * 0.5), c, w)


## The callsign rail's contacts, nearest first.
func rail_items() -> Array[Dictionary]:
	var contacts: Array[Dictionary] = _items.filter(
		func(it: Dictionary) -> bool: return it["kind"] == "contact"
	)
	contacts.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return (a["local"] as Vector3).length() < (b["local"] as Vector3).length()
	)
	return contacts


## The callsign rail: "H2 · 4 high · mid" per contact, pinged and selected ones lit.
func _draw_rail() -> void:
	var font: Font = get_theme_default_font()
	_rail.draw_rect(Rect2(Vector2.ZERO, _rail.size), Palette.color("panel"))
	var contacts: Array[Dictionary] = rail_items()
	var x: float = 12.0
	var y: float = (_rail.size.y - font.get_height(FONT_SIZE)) / 2.0
	for it: Dictionary in contacts:
		var text: String = ChipText.chip(it["label"], it["local"])
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		if x + w > _rail.size.x:
			break
		if float(it.get("pulse", 0.0)) > 0.0 or ctx.crew.is_selected(it["kind"], it["id"]):
			_rail.draw_rect(
				Rect2(x - 6.0, 3.0, w + 12.0, _rail.size.y - 6.0), Palette.color("panel_focus")
			)
		var base: Vector2 = Vector2(x, y + font.get_ascent(FONT_SIZE))
		_rail.draw_string(
			font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Palette.item_color(it)
		)
		x += w + 28.0
		if x < _rail.size.x:
			_rail.draw_line(
				Vector2(x - 14.0, 6.0), Vector2(x - 14.0, _rail.size.y - 6.0), Palette.color("line")
			)


func _text(font: Font, at: Vector2, text: String, col: Color) -> void:
	var base: Vector2 = at + Vector2(0.0, font.get_ascent(FONT_SIZE))
	Palette.draw_outlined(_overlay, font, base, text, FONT_SIZE, col)
