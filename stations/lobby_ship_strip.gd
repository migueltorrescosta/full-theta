class_name LobbyShipStrip
extends ScrollContainer
## The lobby's ship buttons and New ship on a phone (#28 follow-up, strand T): one row that
## scrolls sideways instead of a flow that wraps, so up to six ships never push Start under
## the gesture band. The buttons share one width (the widest label's, or stretched so the
## whole buttons that fit fill the row), so none shows cut at the edge before the player
## scrolls; the chosen ship scrolls into view. A finger drags the row over the buttons
## (they pass the drag on). Off a phone the buttons go back to the lobby's flow.

## The row of buttons inside.
var row: HBoxContainer = HBoxContainer.new()


func _init() -> void:
	name = "ShipScroll"
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	visible = false
	row.name = "ShipStrip"
	add_child(row)


## Moves the ship buttons and `new_ship` between the lobby's `flow` and the strip.
func use(phone: bool, flow: Container, new_ship: Button) -> void:
	var from: Container = flow if phone else row
	var to: Container = row if phone else flow
	var moving: Array[Button] = []
	for c: Node in from.get_children():
		if str(c.name).begins_with("Ship_") or c == new_ship:
			moving.append(c as Button)
	for i: int in moving.size():
		from.remove_child(moving[i])
		to.add_child(moving[i])
		to.move_child(moving[i], i)
		adopt(moving[i], phone)
	visible = phone


## A button in the strip passes drags on (the row scrolls) and is a whole target tall.
static func adopt(b: Button, phone: bool) -> void:
	b.mouse_filter = Control.MOUSE_FILTER_PASS if phone else Control.MOUSE_FILTER_STOP
	b.custom_minimum_size = Vector2(0.0, UiTheme.TOUCH_PRIMARY if phone else 0.0)


## Sizes the buttons and the strip for `width` px of room.
func fit(width: float) -> void:
	if not visible or width <= 0.0:
		return
	var buttons: Array[Button] = []
	var w: float = UiTheme.TOUCH_PRIMARY
	for c: Node in row.get_children():
		var b: Button = c as Button
		if b != null and b.visible:
			buttons.append(b)
			var text: Vector2 = b.get_theme_font("font").get_string_size(
				b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")
			)
			w = maxf(w, ceilf(text.x + b.get_theme_stylebox("normal").get_minimum_size().x))
	var gap: float = UiTheme.TOUCH_GAP
	var n: int = clampi(floori((width + gap) / (w + gap)), 1, maxi(buttons.size(), 1))
	if n < buttons.size():
		# Some scroll: the whole buttons that fit share the full width.
		w = floorf((width - (n - 1) * gap) / n)
	for b: Button in buttons:
		b.custom_minimum_size = Vector2(w, UiTheme.TOUCH_PRIMARY)
		if b.button_pressed:
			ensure_control_visible.call_deferred(b)
	custom_minimum_size.x = n * w + (n - 1) * gap
