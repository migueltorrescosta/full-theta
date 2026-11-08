class_name WeaponsTurretOverlay
extends Control
## What Weapons draws over its turret camera (R13-7, FT-WPN-001): the mount's arc edge, the
## brackets and chips of the contacts and marks in view, the lead reticle (FT-SIM-014), the
## barrel and the reticle, the out-of-arc warning and arrow (FT-WPN-005) and, off the phone,
## the read-out lines (WeaponsReadout). Covers the turret view; reads the panel.

const FONT_SIZE: int = 15
const RETICLE_R: float = 18.0
const BRACKET: float = 10.0

## Brackets in view this frame (layout_targets), for drawing and item_at: {"item"
## (ContactPicture's), "pos", "chip", "chip_at" (its top left), "rect" (bracket and chip)}.
var targets: Array[Dictionary] = []
var _p: WeaponsPanel


func _init(panel: WeaponsPanel) -> void:
	_p = panel
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Position of a world direction seen from the camera mount, in the turret view's (the
## overlay's) coordinates, or null behind it.
func project(dir: Vector3) -> Variant:
	var c: Vector3 = _p.cam_basis.transposed() * dir
	if c.z > -1e-4:
		return null
	return size / 2.0 + Vector2(c.x, -c.y) * focal() / -c.z


## The turret view's focal length (px): its half height over tan(fov / 2).
func focal() -> float:
	return maxf(size.y / 2.0, 1.0) / tan(deg_to_rad(_p.fov) / 2.0)


## Brackets of the contacts and marks in view, with their chips and hit rectangles.
func layout_targets() -> void:
	targets.clear()
	if not _p.focused:
		return
	var font: Font = _p.get_theme_default_font()
	var rot: Quaternion = _p.ctx.interp.own_rotation()
	var m: MountDef = _p.ship_def.mounts[_p.mount]
	# A phone's or a tablet's view with rails keeps its chips inside the view.
	var phone: bool = (
		_p.tablet() != null or (_p.is_inside_tree() and LayoutMode.is_phone(LayoutMode.form_of(_p)))
	)
	for it: Dictionary in _p.ctx.picture().items:
		if it["kind"] == "point":
			continue
		var p: Variant = project(rot * ((it["local"] as Vector3) - m.position).normalized())
		if p == null:
			continue
		# On a phone a bracket outside the view is not drawn, so its chip never shows cut.
		var view: Rect2 = Rect2(Vector2.ZERO, size).grow(-BRACKET)
		if phone and view.has_area() and not view.has_point(p as Vector2):
			continue
		# (a target whose centre is off the view has no bracket to hang a chip on)
		if size.x > 0.0 and not Rect2(Vector2.ZERO, size).has_point(p as Vector2):
			continue
		var chip: String = WeaponsReadout.target_chip(_p, it)
		var sz: Vector2 = font.get_string_size(chip, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		var at: Vector2 = (p as Vector2) + Vector2(BRACKET + 6.0, 4.0 - FONT_SIZE)
		# Too near the right edge for the chip: it goes to the left of the bracket.
		if phone and at.x + sz.x > size.x:
			at.x = (p as Vector2).x - BRACKET - 6.0 - sz.x
		at.x = maxf(at.x, 2.0)
		var r: Rect2 = Rect2((p as Vector2) - Vector2.ONE * BRACKET, Vector2.ONE * BRACKET * 2.0)
		targets.append(
			{"item": it, "pos": p, "chip": chip, "chip_at": at, "rect": r.merge(Rect2(at, sz))}
		)


func _draw() -> void:
	var font: Font = _p.get_theme_default_font()
	if _p.mount_count() == 0:
		_text(font, Vector2(16, 28), _p.tr("weapons.no_mounts"), Palette.color("text_dim"))
		return
	if _p.focused:
		_draw_turret(font)
	if _p.touch() != null:
		_draw_phone_lines(font)
		return
	var rows: Array[String] = WeaponsReadout.mount_rows(_p)
	var lines: Array[String] = []
	lines.append_array(rows)
	var target: String = WeaponsReadout.target_text(_p)
	if target != "":
		lines.append(target)
	if _p.focused:
		lines.append_array(WeaponsReadout.feed_lines(_p))
	var arc: String = WeaponsReadout.out_of_arc_text(_p)
	if _p.focused:
		lines.append(WeaponsReadout.ammo_text(_p))
		if WeaponsReadout.hint(_p) != "":
			lines.append(WeaponsReadout.hint(_p))
		if arc != "":
			_draw_arc_warning(font, arc)
	elif arc != "":
		lines.append(arc)
	var line_h: float = FONT_SIZE + 6.0
	# A line longer than the view wraps (the docked column is narrow), so none is cut at the
	# screen's edge (D319).
	var width: float = maxf(size.x - 24.0, 40.0)
	var counts: Array[int] = []
	var total: int = 0
	for text: String in lines:
		var wrapped: float = (
			font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, FONT_SIZE).y
		)
		var rows_n: int = maxi(roundi(wrapped / font.get_height(FONT_SIZE)), 1)
		counts.append(rows_n)
		total += rows_n
	var y0: float = 12.0 + FONT_SIZE if _p.docked else size.y - 12.0 - line_h * (total - 1)
	var y: float = y0
	for k: int in lines.size():
		var col: Color = Palette.color("text") if k == _p.mount else Palette.color("text_dim")
		if lines[k] == arc:
			col = Palette.color("warn")
		var bg: Color = Palette.color("background")
		var at: Vector2 = Vector2(12.0, y)
		draw_multiline_string_outline(
			font, at, lines[k], HORIZONTAL_ALIGNMENT_LEFT, width, FONT_SIZE, -1, 4, bg
		)
		draw_multiline_string(
			font, at, lines[k], HORIZONTAL_ALIGNMENT_LEFT, width, FONT_SIZE, -1, col
		)
		y += line_h * counts[k]


## On a phone the rail and the overlays show the mounts, the ammunition, the claim and the
## target (WeaponsTouch); the overlay adds the out-of-arc warning and the feeds under the
## target line (not on the Mounts page, whose list covers them).
func _draw_phone_lines(font: Font) -> void:
	var arc: String = WeaponsReadout.out_of_arc_text(_p)
	if arc != "":
		_draw_arc_warning(font, arc)
	if not _p.touch().shows_feeds():
		return
	var lines: Array[String] = WeaponsReadout.feed_lines(_p)
	if lines.is_empty():
		return
	var line_h: float = FONT_SIZE + 6.0
	var at: Vector2 = _p.touch().feeds_origin(self, line_h * lines.size())
	for k: int in lines.size():
		_text(font, at + Vector2(0.0, FONT_SIZE + k * line_h), lines[k], Palette.color("text"))


func _draw_arc_warning(font: Font, arc: String) -> void:
	var r: Rect2 = arc_warning_rect(font, arc)
	# On a dim backing: a star in the narrow space after the colon read as "arc:·turn".
	draw_rect(r.grow(3.0), Color(Palette.color("background"), 0.8))
	_text(font, r.position + Vector2(0, FONT_SIZE), arc, Palette.color("warn"))


## Where the out-of-arc warning goes (FT-WPN-005): centred near the top of the view (on a
## phone under the view-top row), moved down past any bracket or chip it would cover (#28:
## it hid the U3 chip). The rectangle's
## top is the text's top; the baseline is FONT_SIZE lower.
func arc_warning_rect(font: Font, arc: String) -> Rect2:
	var sz: Vector2 = font.get_string_size(arc, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var r: Rect2 = Rect2((size.x - sz.x) / 2.0, 48.0 - FONT_SIZE, sz.x, FONT_SIZE + 6.0)
	var touch: WeaponsTouch = _p.touch()
	if touch != null:
		# On a phone: centred in the view beside the rail, under the view-top row.
		var view: Rect2 = (
			get_global_transform().affine_inverse() * (_p.get_global_transform() * _p.view_rect())
		)
		r.position = Vector2(view.get_center().x - sz.x / 2.0, touch.read_top(self))
	var keep_clear: Array[Rect2] = []
	for t: Dictionary in targets:
		keep_clear.append(t["rect"])
	if touch != null and touch.target_label.text != "":
		# The target line over the view's left (WeaponsTouch).
		var label: Label = touch.target_label
		keep_clear.append(get_global_transform().affine_inverse() * label.get_global_rect())
	for _pass: int in keep_clear.size():
		var clear: bool = true
		for hit: Rect2 in keep_clear:
			if hit.intersects(r):
				r.position.y = hit.end.y + 4.0
				clear = false
		if clear:
			break
	return r


func _draw_turret(font: Font) -> void:
	var rot: Quaternion = _p.ctx.interp.own_rotation()
	var m: MountDef = _p.ship_def.mounts[_p.mount]
	# The arc edge: the cone of half-angle arc_half_angle around the rest direction.
	var axis: Vector3 = m.forward.cross(Vector3.UP if absf(m.forward.y) < 0.9 else Vector3.RIGHT)
	var edge: Vector3 = m.forward.rotated(axis.normalized(), m.arc_half_angle)
	var prev: Variant = null
	for k: int in 65:
		var p: Variant = project(rot * edge.rotated(m.forward, TAU * k / 64.0))
		if p != null and prev != null:
			draw_line(prev, p, Palette.color("accent") * Color(1, 1, 1, 0.7), 1.5, true)
		prev = p
	for t: Dictionary in targets:
		_draw_item(font, t)
	var lead: Variant = _p.lead_dir(_p.mount, _p.selected_contact())
	if lead != null:
		var p: Variant = project(lead)
		if p != null:
			var col: Color = Palette.color("selected")
			draw_polyline(Palette.shape_points("diamond", p, 7.0), col, 2.0, true)
	var bp: Variant = project(rot * _p.aim.barrel(_p.mount))
	if bp != null:
		draw_arc(bp, 5.0, 0.0, TAU, 16, Palette.color("ok"), 2.0, true)
	var c: Vector2 = size / 2.0
	var rc: Color = Palette.color("text")
	draw_arc(c, RETICLE_R, 0.0, TAU, 32, rc, 1.5, true)
	for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(c + d * (RETICLE_R + 4.0), c + d * (RETICLE_R + 12.0), rc, 1.5, true)
	# The target is out of the mount's arc: an arrow at the reticle toward where to turn (C6).
	var turn: Vector2 = WeaponsStatus.arc_arrow_dir(_p)
	if turn != Vector2.ZERO:
		var base: Vector2 = c + turn * (RETICLE_R + 26.0)
		var side: Vector2 = turn.orthogonal()
		var arrow: PackedVector2Array = PackedVector2Array(
			[base + turn * 12.0, base - turn * 4.0 + side * 9.0, base - turn * 4.0 - side * 9.0]
		)
		draw_colored_polygon(arrow, Palette.color("warn"))


func _draw_item(font: Font, t: Dictionary) -> void:
	var it: Dictionary = t["item"]
	var p: Vector2 = t["pos"]
	var sel: bool = _p.ctx.crew.is_selected(it["kind"], it["id"])
	var col: Color = Palette.color("selected") if sel else Palette.item_color(it)
	var flag: int = (
		WeaponsReadout.contract_flag(_p, int(it["id"])) if it["kind"] == "contact" else 0
	)
	if flag != 0 and not sel:
		col = Palette.color("warn") if flag == 1 else Palette.color("ok")
	if it["kind"] == "mark":
		draw_polyline(Palette.shape_points("diamond", p, BRACKET), col, 1.5, true)
	else:
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var q: Vector2 = p + corner * BRACKET
			draw_line(q, q - Vector2(corner.x * 5.0, 0), col, 2.0 if sel else 1.5)
			draw_line(q, q - Vector2(0, corner.y * 5.0), col, 2.0 if sel else 1.5)
	_text(font, (t["chip_at"] as Vector2) + Vector2(0.0, FONT_SIZE), t["chip"], col)
	var pulse: float = float(it.get("pulse", 0.0))
	if pulse > 0.0:
		var pc: Color = Palette.color("ping")
		pc.a = pulse
		draw_arc(p, BRACKET + 4.0 + (1.0 - pulse) * 22.0, 0.0, TAU, 32, pc, 2.0, true)


func _text(font: Font, base: Vector2, text: String, col: Color) -> void:
	Palette.draw_outlined(self, font, base, text, FONT_SIZE, col)
