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
## (ContactPicture's), "pos", "callout", "callout_at" (its top left), "rect" (bracket and chip)}.
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
	var inset: Rect2 = _inset()
	# A phone's view-top row (selection bar, partner glance) covers the view's top: a bracket
	# under it is not drawn, so neither it nor its chip shows cut (D319(6), w-dcc).
	var top: float = _p.touch().read_top(self) - UiTheme.TOUCH_GAP if _p.touch() != null else 0.0
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
		if (p as Vector2).y - BRACKET < top:
			continue
		var chip: String = WeaponsReadout.target_chip(_p, it)
		var sz: Vector2 = font.get_string_size(chip, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		var at: Vector2 = (p as Vector2) + Vector2(BRACKET + 6.0, 4.0 - FONT_SIZE)
		# Too near the right edge for the chip: it goes to the left of the bracket.
		if phone and at.x + sz.x > size.x:
			at.x = (p as Vector2).x - BRACKET - 6.0 - sz.x
		at.x = maxf(at.x, 2.0)
		if inset.has_area():
			# A tablet's radar inset (C14) covers the brackets under it; a chip that would run
			# under it goes to the bracket's left.
			if inset.grow(BRACKET).has_point(p as Vector2):
				continue
			if Rect2(at, sz).intersects(inset):
				at.x = maxf((p as Vector2).x - BRACKET - 6.0 - sz.x, 2.0)
		var r: Rect2 = Rect2((p as Vector2) - Vector2.ONE * BRACKET, Vector2.ONE * BRACKET * 2.0)
		targets.append(
			{
				"item": it,
				"pos": p,
				"callout": chip,
				"callout_at": at,
				"rect": r.merge(Rect2(at, sz))
			}
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
	var widths: Array[float] = []
	var total: int = 0
	# (a held mount's row wraps short of its "You" chip, so the chip never runs off the edge)
	var chip_w: float = _mine_chip_w(font)
	for k: int in lines.size():
		var text: String = lines[k]
		var w_k: float = width
		if k < rows.size() and _p.is_mine(k):
			w_k = maxf(width - chip_w, 40.0)
		widths.append(w_k)
		var wrapped: float = (
			font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, w_k, FONT_SIZE).y
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
		var w_k: float = widths[k]
		if k < rows.size() and k == _p.mount:
			_draw_row_bar(font, at, lines[k], w_k, line_h)
		draw_multiline_string_outline(
			font, at, lines[k], HORIZONTAL_ALIGNMENT_LEFT, w_k, FONT_SIZE, -1, 4, bg
		)
		draw_multiline_string(
			font, at, lines[k], HORIZONTAL_ALIGNMENT_LEFT, w_k, FONT_SIZE, -1, col
		)
		if k < rows.size() and _p.is_mine(k):
			_draw_mine_chip(font, at, lines[k], w_k, line_h)
		y += line_h * counts[k]


## The camera mount's row (R22-16): a highlight bar behind its text, in place of a "> " cursor.
func _draw_row_bar(font: Font, at: Vector2, text: String, width: float, line_h: float) -> void:
	var para: TextParagraph = _para(font, text, width)
	var w: float = 0.0
	for i: int in para.get_line_count():
		w = maxf(w, para.get_line_width(i))
	var top: float = at.y - font.get_ascent(FONT_SIZE) - 3.0
	var h: float = line_h * (para.get_line_count() - 1) + FONT_SIZE + 8.0
	var bar: Rect2 = Rect2(at.x - 6.0, top, w + 12.0, h)
	draw_rect(bar, Color(Palette.color("accent"), 0.3))
	draw_rect(Rect2(bar.position, Vector2(3.0, bar.size.y)), Palette.color("accent"))


## "You" as a chip after the row of a mount this client holds (R22-16), on its last line.
func _draw_mine_chip(font: Font, at: Vector2, text: String, width: float, line_h: float) -> void:
	var para: TextParagraph = _para(font, text, width)
	var last: int = para.get_line_count() - 1
	var chip: String = WeaponsReadout.mine_chip(_p)
	var fs: int = FONT_SIZE - 2
	var sz: Vector2 = font.get_string_size(chip, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var base: Vector2 = at + Vector2(para.get_line_width(last) + 12.0, line_h * last)
	var box: Rect2 = Rect2(
		base.x - 6.0, base.y - font.get_ascent(fs) - 2.0, sz.x + 12.0, font.get_height(fs) + 4.0
	)
	var sb: StyleBoxFlat = UiTheme.box("ok", "", 0, 0)
	sb.set_corner_radius_all(int(box.size.y / 2.0))
	draw_style_box(sb, box)
	draw_string(font, base, chip, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.color("background"))


## The room (px) a "You" chip takes after its row: the gap, the chip and its padding.
func _mine_chip_w(font: Font) -> float:
	var chip: String = WeaponsReadout.mine_chip(_p)
	return font.get_string_size(chip, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE - 2).x + 24.0


## `text` broken into lines of `width` px, as draw_multiline_string breaks it.
static func _para(font: Font, text: String, width: float) -> TextParagraph:
	var para: TextParagraph = TextParagraph.new()
	para.add_string(text, font, FONT_SIZE)
	para.width = width
	para.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND
	return para


## On a phone the rail and the overlays show the mounts, the ammunition, the claim and the
## target (WeaponsTouch); the overlay adds the out-of-arc warning and the feeds under the
## target line (not on the Mounts page, whose list covers them).
func _draw_phone_lines(font: Font) -> void:
	# The Mounts page's list covers the view's read-outs: the warning hides with them (D319(6)).
	if not _p.touch().shows_feeds():
		return
	var arc: String = WeaponsReadout.out_of_arc_text(_p)
	if arc != "":
		_draw_arc_warning(font, arc)
	var lines: Array[String] = WeaponsReadout.feed_lines(_p)
	if lines.is_empty():
		return
	var line_h: float = FONT_SIZE + 6.0
	var at: Vector2 = _p.touch().feeds_origin(self, line_h * lines.size())
	for k: int in lines.size():
		_text(font, at + Vector2(0.0, FONT_SIZE + k * line_h), lines[k], Palette.color("text"))


func _draw_arc_warning(font: Font, arc: String) -> void:
	var r: Rect2 = arc_warning_rect(font, arc)
	# On a solid backing (w-dcc: the dim one let the nebula through; a star in the narrow
	# space after the colon read as "arc:·turn").
	var back: StyleBoxFlat = UiTheme.box("background", "", 0, 0)
	back.set_corner_radius_all(4)
	draw_style_box(back, r.grow(4.0))
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
	var inset: Rect2 = _inset()
	if inset.has_area() and r.intersects(inset.grow(UiTheme.TOUCH_GAP)):
		# Centred in the view left of a tablet's radar inset (C14).
		var room: float = inset.position.x - UiTheme.TOUCH_GAP
		r.position.x = maxf((room - sz.x) / 2.0, UiTheme.TOUCH_GAP)
	var keep_clear: Array[Rect2] = []
	if inset.has_area():
		keep_clear.append(inset)
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
		draw_colored_polygon(clear_of(arrow, _mount_list_rect()), Palette.color("warn"))


## A tablet's radar inset in this overlay's coordinates while it shows (C14), else empty.
func _inset() -> Rect2:
	return _p.tablet().radar_rect_in(self) if _p.tablet() != null else Rect2()


## `arrow` moved down under `cover` when the cover would hide it (the phone's mount list,
## w5); unchanged otherwise.
static func clear_of(arrow: PackedVector2Array, cover: Rect2) -> PackedVector2Array:
	var box: Rect2 = Rect2(arrow[0], Vector2.ZERO)
	for p: Vector2 in arrow:
		box = box.expand(p)
	box = box.grow(2.0)
	if not cover.has_area() or not box.intersects(cover):
		return arrow
	var out: PackedVector2Array = arrow.duplicate()
	for i: int in out.size():
		out[i] += Vector2(0.0, cover.end.y - box.position.y)
	return out


## The phone's mount list (Mounts page) in this overlay's coordinates, else an empty rect.
func _mount_list_rect() -> Rect2:
	var t: WeaponsTouch = _p.touch()
	if t == null or not t.mount_list.is_visible_in_tree():
		return Rect2()
	return get_global_transform().affine_inverse() * t.mount_list.get_global_rect()


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
		TargetBracket.draw(self, p, BRACKET, 5.0, col, 2.0 if sel else 1.5)
	_text(font, (t["callout_at"] as Vector2) + Vector2(0.0, FONT_SIZE), t["callout"], col)
	if it.get("priority", false):
		ItemGlyph.draw_priority(self, p, BRACKET)
	var pulse: float = float(it.get("pulse", 0.0))
	if pulse > 0.0:
		ItemGlyph.ping_ring(
			self,
			p,
			BRACKET + ItemGlyph.PING_GAP,
			ItemGlyph.PING_SPAN,
			pulse,
			Palette.color("ping"),
			2.0,
			32
		)


func _text(font: Font, base: Vector2, text: String, col: Color) -> void:
	Palette.draw_outlined(self, font, base, text, FONT_SIZE, col)
