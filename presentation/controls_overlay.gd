class_name ControlsOverlay
extends Control
## The controls overlay (FT-STN-011, D100): generated from the live bindings, so a rebind
## shows at once; one section for the common actions and the always-live set and one
## per station of the screen, for the device in use; translated labels. Intents with no
## binding on the device are left out; hold intents switched to a toggle say so.

var _rows: Array[Dictionary] = []
var _bindings: Bindings = null
var _stations: Array = []
var _device: String = IntentTable.KBM
var _list: VBoxContainer = VBoxContainer.new()


func _init() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(centre)
	var panel: PanelContainer = PanelContainer.new()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Palette.color("panel")
	box.border_color = Palette.color("line")
	box.set_border_width_all(1)
	box.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", box)
	centre.add_child(panel)
	panel.add_child(_list)


## Regenerates the rows for `stations` on `device`; follows later rebinds.
func build(bindings: Bindings, stations: Array, device: String) -> void:
	if _bindings != null and _bindings.changed.is_connected(_rebuild):
		_bindings.changed.disconnect(_rebuild)
	_bindings = bindings
	_stations = stations
	_device = device
	_bindings.changed.connect(_rebuild)
	_rebuild()


## The rows shown, for tests: [{"section", "id", "label", "keys"}].
func rows() -> Array[Dictionary]:
	return _rows


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.color("background") * Color(1, 1, 1, 0.8))


func _rebuild() -> void:
	_rows.clear()
	for c: Node in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_list.add_child(_label(tr("overlay.title"), "text", 20))
	var common: Array[String] = IntentTable.ids_of(IntentTable.COMMON)
	common.append_array(IntentTable.ids_of(IntentTable.LIVE))
	_section("overlay.common", common)
	for s: Variant in _stations:
		_section("station." + str(s), IntentTable.ids_of(str(s)))


func _section(key: String, ids: Array[String]) -> void:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	for id: String in ids:
		var list: PackedStringArray = _bindings.bindings(id, _device)
		if list.is_empty():
			continue
		var keys: String = BindingText.describe_all(list)
		if _bindings.is_toggle(id):
			keys += " " + tr("overlay.toggle")
		var row: Dictionary = {
			"section": key, "id": id, "label": tr(IntentTable.label_key(id)), "keys": keys
		}
		_rows.append(row)
		grid.add_child(_label(row["label"], "text", 0))
		grid.add_child(_label(keys, "accent", 0))
	if grid.get_child_count() == 0:
		grid.free()
		return
	_list.add_child(_label(tr(key), "text_dim", 0))
	_list.add_child(grid)


static func _label(text: String, role: String, font_size: int) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Palette.color(role))
	if font_size > 0:
		l.add_theme_font_size_override("font_size", font_size)
	return l
