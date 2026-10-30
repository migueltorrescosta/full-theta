class_name ChoiceSheet
extends Control
## A choice sheet (#28 follow-up, design 1.4, P28-L1): one level of options for an action
## that needs a choice the selection can't give (which subsystem to hack, which alert
## level, which station). Picking an option calls back and closes the sheet; it never
## opens another sheet. Cancel (full width, at the bottom) or a tap on the scrim closes it
## without a choice. On a phone on its side the sheet covers the side of the screen whose
## button opened it, so the view stays visible beside it; upright it is a bottom sheet.
## Fill the area under the top bar with it (the top bar stays live); it hides until open.
##
##     var sheet := ChoiceSheet.new()
##     main_area.add_child(sheet)
##     sheet.open("Hack H2", ["Engines", "Weapons", "Shields"], func(i: int) -> void: _hack(i))

## An option was picked (also passed to open's callback).
signal chosen(index: int)
## The sheet closed without a pick.
signal cancelled

## The sheet's width on a phone on its side (design 1.4: 308 px).
const WIDTH: float = 308.0
## The scrim over the rest of the view.
const SCRIM_ALPHA: float = 0.25
const TITLE_FONT: int = 16
## A finger that lands on the sheet and moves this far down (px), more down than sideways,
## cancels it (design 1.4: swipe down cancels).
const SWIPE_DOWN: float = 64.0

## SIDE_LEFT or SIDE_RIGHT on a phone on its side; upright the sheet is at the bottom.
var side: Side = SIDE_RIGHT
## A bottom sheet (set by the owner on an upright phone).
var upright: bool = false:
	set(value):
		upright = value
		_place()
var title: Label = Label.new()
var cancel_button: RailButton
var scrim: ColorRect = ColorRect.new()
var box: PanelContainer = PanelContainer.new()

var _grid: GridContainer = GridContainer.new()
var _scroll: ScrollContainer = ScrollContainer.new()
var _callback: Callable = Callable()
var _buttons: Array[RailButton] = []
## The finger that landed on the sheet's box (-1 none) and where.
var _swipe_index: int = -1
var _swipe_from: Vector2 = Vector2.ZERO


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	scrim.color = Color(0.0, 0.0, 0.0, SCRIM_ALPHA)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(_on_scrim)
	scrim.add_to_group(TouchInput.GROUP)
	add_child(scrim)
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(Palette.color("panel"), UiTheme.OVERLAY_ALPHA)
	sb.border_color = Palette.color("line_strong")
	sb.set_border_width_all(UiTheme.BORDER)
	sb.set_corner_radius_all(UiTheme.RADIUS)
	sb.set_content_margin_all(UiTheme.TOUCH_GAP)
	box.add_theme_stylebox_override("panel", sb)
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.add_to_group(TouchInput.GROUP)
	add_child(box)
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	box.add_child(col)
	title.add_theme_font_size_override("font_size", TITLE_FONT)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(title)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_scroll)
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", UiTheme.TOUCH_GAP)
	_grid.add_theme_constant_override("v_separation", UiTheme.TOUCH_GAP)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)
	cancel_button = RailButton.make(TouchText.of("sheet.cancel", "Cancel"))
	cancel_button.name = "Cancel"
	cancel_button.pressed.connect(cancel)
	col.add_child(cancel_button)


func _ready() -> void:
	resized.connect(_place)
	_place()


## Opens the sheet with `heading` and one button per `options` label; `on_pick` (optional)
## gets the picked index. Opening again replaces the options.
func open(heading: String, options: Array, on_pick: Callable = Callable()) -> void:
	_callback = on_pick
	title.text = heading
	set_options(options)
	visible = true
	_place()


## Replaces the options (the Hack sheet retargeted by a tap on another blip).
func set_options(options: Array) -> void:
	for b: RailButton in _buttons:
		_grid.remove_child(b)
		b.queue_free()
	_buttons.clear()
	for i: int in options.size():
		var b: RailButton = RailButton.make(str(options[i]))
		b.name = "Option%d" % (i + 1)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_pick.bind(i))
		_grid.add_child(b)
		_buttons.append(b)


## The option buttons (tests, a station disabling one).
func option(index: int) -> RailButton:
	return _buttons[index] if index >= 0 and index < _buttons.size() else null


func option_count() -> int:
	return _buttons.size()


func is_open() -> bool:
	return visible


## Closes without a choice.
func cancel() -> void:
	if not visible:
		return
	_close()
	cancelled.emit()


func _pick(index: int) -> void:
	if not visible:
		return
	var cb: Callable = _callback
	_close()
	chosen.emit(index)
	if cb.is_valid():
		cb.call(index)


func _close() -> void:
	visible = false
	_callback = Callable()
	_swipe_index = -1


## Swipe down on the sheet cancels it; seen before the buttons, so a swipe that starts on an
## option works too (a tap still picks: a button fires on release, after a short move).
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var t: InputEventScreenTouch = event as InputEventScreenTouch
	if t != null:
		if t.pressed and box.get_global_rect().has_point(t.position):
			_swipe_index = t.index
			_swipe_from = t.position
		elif not t.pressed and t.index == _swipe_index:
			_swipe_index = -1
		return
	var d: InputEventScreenDrag = event as InputEventScreenDrag
	if d == null or d.index != _swipe_index:
		return
	var moved: Vector2 = d.position - _swipe_from
	if moved.y >= SWIPE_DOWN and moved.y > absf(moved.x):
		_swipe_index = -1
		get_viewport().set_input_as_handled()
		cancel()


## A tap on the scrim cancels (a finger, or a real mouse click: not both for one tap).
func _on_scrim(event: InputEvent) -> void:
	var up: bool = false
	if event is InputEventScreenTouch:
		up = not (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton and not TouchInput.is_emulated(event):
		up = not (event as InputEventMouseButton).pressed
	if up:
		scrim.accept_event()
		cancel()


## Upright: a bottom sheet over the controls, full width. On its side: WIDTH wide at
## `side`, from the top to the bottom of the area (above the gesture band: the owner gives
## the sheet an area that ends there).
func _place() -> void:
	if not is_inside_tree():
		return
	var w: float = size.x
	var h: float = size.y
	box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	if upright:
		var bh: float = minf(h, maxf(h * 0.45, 240.0))
		box.position = Vector2(0.0, h - bh)
		box.size = Vector2(w, bh)
	else:
		var bw: float = minf(WIDTH, w)
		box.position = Vector2(w - bw if side == SIDE_RIGHT else 0.0, 0.0)
		box.size = Vector2(bw, h)
