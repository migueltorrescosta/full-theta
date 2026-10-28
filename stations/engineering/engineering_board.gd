class_name EngineeringBoard
extends Control
## Engineering's power board (FT-ENG-002, FT-ENG-003): a pip column per powered
## subsystem (click a pip to set the column to it; pips above the nominal line are
## overcharge and build heat), the reactor cap, the boost, and the shields: strength,
## power (the shield column's pips), focus tightness (click a step) and a small ring
## mirroring Helm's focus. `compact` is the docked view: the columns and the cap only.
## On a phone (#28, D274) a pip box (22 px) and a tightness step are too small to tap: a
## tap anywhere in a column selects it, and the rail's Power +/- and Tighter/Wider set the
## values; each column's tap area (a control with the `tap` meta) keeps 8 px from the next.

const PAD: float = 16.0
const GAP: float = 4.0

var panel: EngineeringPanel
var compact: bool = false:
	set(v):
		compact = v
		queue_redraw()

var _taps: Array[Control] = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


## Subsystem indices with a pip column (the reactor supplies pips, D117).
func columns() -> Array[int]:
	var out: Array[int] = []
	for i: int in panel.count():
		if panel.ship_def.subsystems[i].kind != SubsystemDef.Kind.REACTOR:
			out.append(i)
	return out


## The subsystem of the column under pos, or -1.
func column_at(pos: Vector2) -> int:
	if panel == null or panel.ship_def == null:
		return -1
	var cols: Array[int] = columns()
	var cw: float = _col_width(cols.size())
	var k: int = floori((pos.x - PAD) / cw)
	if k < 0 or k >= cols.size() or pos.y < _top() - GAP or pos.y > _labels_y() + 8.0:
		return -1
	return cols[k]


## The pip box at pos: [subsystem, pip index from 0], or [].
func pip_at(pos: Vector2) -> Array:
	var i: int = column_at(pos)
	if i < 0:
		return []
	for j: int in panel.ship_def.power.max_pips_per_subsystem:
		if _pip_rect(columns().find(i), j).grow(GAP / 2.0).has_point(pos):
			return [i, j]
	return []


## The tightness value of the step under pos, or -1.
func tightness_at(pos: Vector2) -> float:
	if compact:
		return -1.0
	var def: ShieldDef = panel.ship_def.shields
	for k: int in _steps():
		if _step_rect(k).grow(GAP / 2.0).has_point(pos):
			return def.tightness_min + k * EngineeringPanel.TIGHTNESS_STEP
	return -1.0


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT or panel == null:
		return
	if panel.ship_def == null or panel.docked:
		return
	var pip: Array = [] if phone() else pip_at(mb.position)
	if not pip.is_empty():
		panel.select(pip[0])
		var n: int = pip[1] + 1
		# A click on the top lit pip turns it off.
		panel.set_pips(pip[0], n - 1 if n == panel.pips_of(pip[0]) else n)
		accept_event()
		return
	var col: int = column_at(mb.position)
	if col >= 0:
		panel.select(col)
		accept_event()
		return
	var t: float = -1.0 if phone() else tightness_at(mb.position)
	if t >= 0.0:
		panel.set_tightness(t)
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.color("panel_focus" if not compact else "panel"))
	if panel == null or panel.ship_def == null:
		return
	var font: Font = get_theme_default_font()
	var fs: int = get_theme_default_font_size() - (4 if compact else 0)
	if not compact:
		_text(Vector2(PAD, 26), tr("eng.power"), "accent", fs)
	var cols: Array[int] = columns()
	var power: PowerDef = panel.ship_def.power
	for k: int in cols.size():
		var i: int = cols[k]
		var sd: SubsystemDef = panel.ship_def.subsystems[i]
		var pips: int = panel.pips_of(i)
		if i == panel.selected and not compact:
			var r: Rect2 = _pip_rect(k, power.max_pips_per_subsystem - 1)
			r = r.merge(_pip_rect(k, 0)).grow(GAP + 2.0)
			draw_rect(r, Palette.color("selected"), false, 1.5)
		for j: int in power.max_pips_per_subsystem:
			var over: bool = j >= sd.nominal_pips
			var rect: Rect2 = _pip_rect(k, j)
			var role: String = "warn" if over else "ok"
			if j < pips:
				draw_rect(rect, Palette.color(role))
			elif panel.is_boosted(i):
				draw_rect(rect, Palette.color("accent"))
			else:
				draw_rect(rect, Palette.color(role).darkened(0.65), false, 1.5)
		# The nominal line: pips above it overcharge (FT-SIM-026).
		var top: Rect2 = (
			_pip_rect(k, sd.nominal_pips - 1) if sd.nominal_pips > 0 else _pip_rect(k, 0)
		)
		var y: float = top.position.y - GAP / 2.0 if sd.nominal_pips > 0 else top.end.y + GAP / 2.0
		draw_line(
			Vector2(top.position.x - 3, y),
			Vector2(top.end.x + 3, y),
			Palette.color("text_dim"),
			1.0
		)
		var label: String = panel.short_name(i)
		var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var cx: float = _pip_rect(k, 0).get_center().x
		_text(Vector2(cx - w / 2.0, _labels_y()), label, "text", fs)
		if not compact:
			# The number key that selects it.
			_text(Vector2(cx - 4.0, _top() - 8.0), str(i + 1), "text_dim", fs - 4)
		# Health under the label, as a thin bar (FT-ENG-001's colours).
		var hb: Rect2 = Rect2(cx - 16.0, _labels_y() + 5.0, 32.0, 4.0)
		draw_rect(hb, Palette.color("line"))
		hb.size.x *= panel.health_frac(i)
		draw_rect(hb, EngineeringCutaway._health_color(panel.health_frac(i)))
	_draw_cap(fs)
	if not compact:
		_draw_legend(fs)
		_draw_shields(fs)
	_sync_taps()


## True on a phone, where only whole columns take taps.
func phone() -> bool:
	return is_inside_tree() and LayoutMode.is_phone(LayoutMode.form_of(self))


## Column k's tap area on a phone: the column less half a gap on each side.
func column_tap_rect(k: int) -> Rect2:
	var cw: float = _col_width(columns().size())
	var top: float = _top() - GAP
	var half: float = UiTheme.TOUCH_GAP / 2.0
	return Rect2(PAD + k * cw + half, top, cw - 2.0 * half, _labels_y() + 8.0 - top)


func _sync_taps() -> void:
	var on: bool = phone() and not compact and panel != null and panel.ship_def != null
	var n: int = columns().size() if on else 0
	while _taps.size() < n:
		var c: Control = Control.new()
		c.name = "ColumnTap%d" % _taps.size()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.set_meta("tap", true)
		add_child(c)
		_taps.append(c)
	for k: int in _taps.size():
		_taps[k].visible = k < n
		if k < n:
			var r: Rect2 = column_tap_rect(k)
			_taps[k].position = r.position
			_taps[k].size = r.size


func _draw_cap(fs: int) -> void:
	var power: PowerDef = panel.ship_def.power
	var y: float = _labels_y() + (22.0 if compact else 40.0)
	var used: int = panel.pips_used()
	var text: String = tr("eng.reactor") % [used, power.reactor_pips]
	if panel.boosting():
		var left: float = float(panel.block().get("boost_ticks", 0)) / CrewState.TICK_HZ
		text += "  " + tr("eng.boost_left") % ceili(left)
	_text(Vector2(PAD, y), text, "accent" if panel.boosting() else "text", fs)
	var w: float = (size.x - 2.0 * PAD) / power.reactor_pips
	for k: int in power.reactor_pips:
		var r: Rect2 = Rect2(PAD + k * w, y + 6.0, w - 2.0, 8.0 if compact else 12.0)
		draw_rect(r, Palette.color("ok" if k < used else "line"))


func _draw_legend(fs: int) -> void:
	var y: float = _labels_y() + 88.0
	draw_rect(Rect2(PAD, y - 10.0, 10.0, 10.0), Palette.color("warn"))
	_text(Vector2(PAD + 16.0, y), tr("eng.overcharge"), "text_dim", fs - 2)
	draw_rect(Rect2(PAD, y + 10.0, 10.0, 10.0), Palette.color("accent"))
	_text(Vector2(PAD + 16.0, y + 20.0), tr("eng.boost"), "text_dim", fs - 2)


func _draw_shields(fs: int) -> void:
	var y: float = _shields_y()
	var frac: float = panel.shield_frac()
	_text(Vector2(PAD, y), tr("eng.shields") % roundi(frac * 100.0), "accent", fs)
	var bar: Rect2 = Rect2(PAD, y + 8.0, size.x - 2.0 * PAD - 96.0, 10.0)
	draw_rect(bar, Palette.color("line"))
	draw_rect(
		Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), Palette.color("friendly")
	)
	var si: int = _shield_subsystem()
	if si >= 0:
		_text(Vector2(PAD, y + 42.0), tr("eng.shield_power") % panel.pips_of(si), "text", fs - 2)
	_text(Vector2(PAD, y + 66.0), tr("eng.tightness"), "text", fs - 2)
	var t: float = panel.tightness()
	var def: ShieldDef = panel.ship_def.shields
	for k: int in _steps():
		var v: float = def.tightness_min + k * EngineeringPanel.TIGHTNESS_STEP
		var lit: bool = v <= t + 0.001
		draw_rect(
			_step_rect(k), Palette.color("accent" if lit else "line"), lit, -1.0 if lit else 1.5
		)
	var r0: Rect2 = _step_rect(0)
	var r1: Rect2 = _step_rect(_steps() - 1)
	_text(Vector2(r0.position.x, r0.end.y + 16.0), tr("eng.spread"), "text_dim", fs - 4)
	var tight: String = tr("eng.tight")
	var tw: float = get_theme_default_font().get_string_size(tight, 0, -1, fs - 4).x
	_text(Vector2(r1.end.x - tw, r1.end.y + 16.0), tight, "text_dim", fs - 4)
	_draw_ring(Vector2(size.x - PAD - 40.0, y + 34.0), 32.0, t, def.tightness_max)


## Helm's shield ring, seen from above with the bow up: the lobe narrows as the focus
## tightens (§5.3; Helm's own ring is FT-HLM-011).
func _draw_ring(c: Vector2, r: float, t: float, t_max: float) -> void:
	draw_arc(c, r, 0.0, TAU, 48, Palette.color("line"), 2.0)
	var f: Vector3 = panel.block().get("shield_focus", Vector3.FORWARD)
	var ang: float = atan2(f.x, -f.z) - PI / 2.0
	var half: float = PI * (1.0 - 0.85 * clampf(t / t_max, 0.0, 1.0)) if t_max > 0 else PI
	draw_arc(c, r, ang - half, ang + half, 32, Palette.color("friendly"), 6.0)
	var bow: PackedVector2Array = [
		c + Vector2(0, -r - 10), c + Vector2(-5, -r - 2), c + Vector2(5, -r - 2)
	]
	draw_colored_polygon(bow, Palette.color("text_dim"))


func _text(pos: Vector2, text: String, role: String, fs: int) -> void:
	draw_string(
		get_theme_default_font(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.color(role)
	)


func _shield_subsystem() -> int:
	for i: int in panel.count():
		if panel.ship_def.subsystems[i].kind == SubsystemDef.Kind.SHIELDS:
			return i
	return -1


# --- Layout (one place, used by drawing and hit tests). ---


func _top() -> float:
	return 10.0 if compact else 58.0


func _pip_h() -> float:
	return 9.0 if compact else 22.0


func _col_width(n: int) -> float:
	return (size.x - 2.0 * PAD) / maxi(n, 1)


## Box j (from the bottom) of column k.
func _pip_rect(k: int, j: int) -> Rect2:
	var n: int = panel.ship_def.power.max_pips_per_subsystem
	var cw: float = _col_width(columns().size())
	var w: float = minf(cw - 14.0, 44.0)
	var x: float = PAD + k * cw + (cw - w) / 2.0
	var y: float = _top() + (n - 1 - j) * (_pip_h() + GAP)
	return Rect2(x, y, w, _pip_h())


func _labels_y() -> float:
	var n: int = panel.ship_def.power.max_pips_per_subsystem
	return _top() + n * (_pip_h() + GAP) + (12.0 if compact else 18.0)


func _shields_y() -> float:
	return _labels_y() + 150.0


func _steps() -> int:
	var def: ShieldDef = panel.ship_def.shields
	return roundi((def.tightness_max - def.tightness_min) / EngineeringPanel.TIGHTNESS_STEP) + 1


func _step_rect(k: int) -> Rect2:
	var w: float = (size.x - 2.0 * PAD - 96.0) / _steps()
	return Rect2(PAD + k * w, _shields_y() + 74.0, w - GAP, 16.0)
