class_name ControlsList
extends VBoxContainer
## The Controls tab of the menu (FT-STN-011, FT-STN-012, D100, D185): generated from the
## live bindings, so a rebind shows at once; one section for the common actions and the
## always-live set and one per station of the screen, for the device in use; translated
## labels. Intents with no binding on the device are left out; hold intents switched to a
## toggle say so. Headed by the seat's role summary; it retranslates itself when the
## language changes.

var _rows: Array[Dictionary] = []
var _bindings: Bindings = null
var _stations: Array = []
var _device: String = IntentTable.KBM
var _role: String = ""
## The rows live in here: a notification may not change the children of its own node.
var _list: VBoxContainer = VBoxContainer.new()


func _init() -> void:
	_list.add_theme_constant_override("separation", 6)
	add_child(_list)


## Regenerates the rows for `stations` on `device` under the role summary of seat `role`
## (an ENTRIES or STATIONS id; none when empty); follows later rebinds.
func build(bindings: Bindings, stations: Array, device: String, role: String = "") -> void:
	if _bindings != null and _bindings.changed.is_connected(_rebuild):
		_bindings.changed.disconnect(_rebuild)
	_bindings = bindings
	_stations = stations
	_device = device
	_role = role
	_bindings.changed.connect(_rebuild)
	_rebuild()


## What it shows: [bindings, stations, device], or [] before the first build.
func shown_args() -> Array:
	return [] if _bindings == null else [_bindings, _stations, _device]


## The rows shown, for tests: [{"section", "id", "label", "keys"}].
func rows() -> Array[Dictionary]:
	return _rows


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _bindings != null:
		_rebuild()


func _rebuild() -> void:
	_rows.clear()
	for c: Node in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if _role != "":
		var summary: Label = _label(tr("role." + _role), "text", 0)
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.custom_minimum_size = Vector2(480, 0)
		_list.add_child(summary)
	var common: Array[String] = IntentTable.ids_of(IntentTable.COMMON)
	common.append_array(IntentTable.ids_of(IntentTable.LIVE))
	_section("overlay.common", common)
	for s: Variant in _stations:
		_section("station." + str(s), IntentTable.ids_of(str(s)))


func _section(key: String, ids: Array[String]) -> void:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	ListLines.attach(grid)
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
		grid.add_child(_wrapped(row["label"], "text"))
		grid.add_child(_wrapped(keys, "accent"))
	if grid.get_child_count() == 0:
		grid.free()
		return
	_list.add_child(_label(tr(key), "text_dim", 0))
	_list.add_child(grid)


## A label that wraps in its column instead of widening the list (a phone).
static func _wrapped(text: String, role: String) -> Label:
	var l: Label = _label(text, role, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func _label(text: String, role: String, font_size: int) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Palette.color(role))
	if font_size > 0:
		l.add_theme_font_size_override("font_size", font_size)
	return l
