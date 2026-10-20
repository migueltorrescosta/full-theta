class_name ShieldRing
extends Control
## The shield ring (FT-HLM-009, FT-HLM-011, D16, D48): a clock face in the ship frame,
## 12 at the bow, each hour split into three bands (outer high, middle level, inner
## low) and a centre split into overhead (top half) and under (bottom half), so
## "shields 4 high" is one click. Each cell is shaded by how much shield covers it: the
## focus direction Helm sets, spread by Engineering's tightness (the coverage lobe) and
## brightened by shield power. A label gives power, tightness and the tracked contact.

## Emitted with the ship-frame direction of a clicked cell.
signal sector_picked(direction: Vector3)

## Band radii as shares of the ring radius: centre, low | level, level | high.
const CENTRE: float = 0.22
const LOW_LEVEL: float = 0.48
const LEVEL_HIGH: float = 0.74
## Elevation (degrees) a band click picks: low, level, high (middle of the band's
## height-word range, Callout.LEVEL_DEG to POLE_DEG).
const BAND_ELEVATIONS: Array[float] = [-37.5, 0.0, 37.5]
const FONT_SIZE: int = 12

## Focus direction (ship frame), tightness and power (1 nominal); the track's callsign.
var focus: Vector3 = Vector3.FORWARD
var tightness: float = 0.0
var power: float = 1.0
var tracking: bool = false
## Draw the power and tightness label under the ring (off when docked).
var label: bool = true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


## Reads the HELM block (shield_focus, shield_tightness, shield_track) and shield power.
func show_state(helm: Dictionary, shield_power: float) -> void:
	focus = helm.get("shield_focus", Vector3.FORWARD)
	tightness = float(helm.get("shield_tightness", 0.0))
	tracking = int(helm.get("shield_track", -1)) >= 0
	power = shield_power
	queue_redraw()


func radius() -> float:
	return minf(size.x, size.y - FONT_SIZE * 2.0) / 2.0 - 2.0


func centre() -> Vector2:
	return Vector2(size.x / 2.0, radius() + 2.0)


## The ship-frame direction of the cell at `pos` (this control's coordinates), or ZERO
## outside the ring.
func direction_at(pos: Vector2) -> Vector3:
	var d: Vector2 = pos - centre()
	var r: float = radius()
	var dist: float = d.length() / r
	if dist > 1.0:
		return Vector3.ZERO
	if dist < CENTRE:
		return Vector3.UP if d.y < 0.0 else Vector3.DOWN
	var band: int = 0 if dist < LOW_LEVEL else (1 if dist < LEVEL_HIGH else 2)
	var hour: int = roundi(fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0) / 30.0) % 12
	return cell_direction(hour, band)


## Unit direction of an hour (0 = 12) and band (0 low, 1 level, 2 high), ship frame.
static func cell_direction(hour: int, band: int) -> Vector3:
	var b: float = deg_to_rad(hour * 30.0)
	var e: float = deg_to_rad(BAND_ELEVATIONS[band])
	return Vector3(sin(b) * cos(e), sin(e), -cos(b) * cos(e))


## Where the focus dot sits: at its bearing in the middle of its height band (D184:
## outer high, middle level, inner low, Callout's words), or in the overhead or under
## half of the centre.
func focus_point() -> Vector2:
	var c: Vector2 = centre()
	var r: float = radius()
	var bands: Dictionary = {
		"low": (CENTRE + LOW_LEVEL) / 2.0,
		"level": (LOW_LEVEL + LEVEL_HIGH) / 2.0,
		"high": (LEVEL_HIGH + 1.0) / 2.0,
	}
	match Callout.height_word(focus):
		"overhead":
			return c + Vector2(0.0, -CENTRE * r / 2.0)
		"under":
			return c + Vector2(0.0, CENTRE * r / 2.0)
		var word:
			var b: float = deg_to_rad(Callout.bearing_deg(focus))
			return c + Vector2(sin(b), -cos(b)) * float(bands[word]) * r


## Coverage of direction `dir` relative to its peak (ShieldSystem's lobe k e^(k cos) /
## sinh k divided by its value at the focus): 1 at the focus, everywhere 1 when spread.
func coverage(dir: Vector3) -> float:
	var k: float = tightness
	if k < 1e-3:
		return 1.0
	return exp(k * (dir.normalized().dot(focus.normalized()) - 1.0))


func _gui_input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var dir: Vector3 = direction_at(mb.position)
	if dir != Vector3.ZERO:
		sector_picked.emit(dir)
		accept_event()


func _draw() -> void:
	var c: Vector2 = centre()
	var r: float = radius()
	var line: Color = Palette.color("line")
	var lit: Color = Palette.color("accent")
	var strength: float = clampf(power, 0.0, 1.5) / 1.5
	draw_circle(c, r, Color(Palette.color("background"), 0.6))
	var radii: Array[float] = [CENTRE * r, LOW_LEVEL * r, LEVEL_HIGH * r, r]
	for hour: int in 12:
		var a0: float = deg_to_rad(hour * 30.0 - 15.0) - PI / 2.0
		for band: int in 3:
			var cov: float = coverage(cell_direction(hour, band))
			var col: Color = Color(lit, 0.08 + 0.7 * cov * strength)
			_cell(c, radii[band], radii[band + 1], a0, a0 + deg_to_rad(30.0), col)
	for half: int in 2:
		var cov: float = coverage(Vector3.UP if half == 0 else Vector3.DOWN)
		var start: float = PI if half == 0 else 0.0
		_cell(c, 0.0, radii[0], start, start + PI, Color(lit, 0.08 + 0.7 * cov * strength))
	for rr: float in radii:
		draw_arc(c, rr, 0.0, TAU, 48, line, 1.0)
	for hour: int in 12:
		var a: float = deg_to_rad(hour * 30.0 - 15.0) - PI / 2.0
		var dir: Vector2 = Vector2(cos(a), sin(a))
		draw_line(c + dir * radii[0], c + dir * r, line, 1.0)
	draw_line(c - Vector2(radii[0], 0.0), c + Vector2(radii[0], 0.0), line, 1.0)
	draw_circle(focus_point(), 4.0, Palette.color("text"))
	if not label:
		return
	var font: Font = get_theme_default_font()
	var text: String = tr("helm.shield_label") % [roundi(power * 100.0), tightness]
	if tracking:
		text += " · " + tr("helm.tracking")
	draw_string(
		font,
		Vector2(0.0, 2.0 * r + 4.0 + FONT_SIZE),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		size.x,
		FONT_SIZE,
		Palette.color("text_dim")
	)


## One annular cell from radius r0 to r1 between angles a0 and a1 (screen radians).
func _cell(c: Vector2, r0: float, r1: float, a0: float, a1: float, col: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	var n: int = 6
	for i: int in n + 1:
		var a: float = lerpf(a0, a1, float(i) / n)
		pts.append(c + Vector2(cos(a), sin(a)) * r1)
	for i: int in n + 1:
		var a: float = lerpf(a1, a0, float(i) / n)
		pts.append(c + Vector2(cos(a), sin(a)) * r0)
	if r0 <= 0.0:
		pts = pts.slice(0, n + 2)
	draw_colored_polygon(pts, col)
