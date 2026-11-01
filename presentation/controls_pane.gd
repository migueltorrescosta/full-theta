class_name ControlsPane
extends VBoxContainer
## The menu's Controls tab (FT-STN-011, FT-STN-012, D185, P28-Help): the seat's role
## summary over a filter (my stations, the default, or all stations) and three views of
## the same live bindings, picked with buttons: the keyboard-and-mouse diagram, the
## controller diagram and the text list (ControlsList), which stays the way in for a
## screen reader. A phone shows the touch pictures of the shown stations' pages
## (TouchHelpPicture, P28-Help) over the list and never builds a diagram; others open on
## the diagram of the device in use. A diagram is built the first time it shows, and
## ControlsDiagram keeps finished layouts, so the menu opens fast (load fix 1). Under a
## diagram, the screen's intents that are not bound on that device and the bindings it
## can't draw.

const VIEW_KBM: String = "Keyboard"
const VIEW_PAD: String = "Gamepad"
const VIEW_LIST: String = "List"
## The filter button's node name.
const ALL_STATIONS: String = "AllStations"

## The text list view; also what SettingsScreen.controls exposes.
var list: ControlsList = ControlsList.new()
var kbm: ControlsDiagram = ControlsDiagram.new()
var pad: ControlsDiagram = ControlsDiagram.new()
var view: String = VIEW_LIST
## A phone's touch pictures, one per shown station that has one, over the list.
var touch: VBoxContainer = VBoxContainer.new()
## Every station shown, not only the screen's (the filter).
var all_stations: bool = false

var _role: String = ""
var _device: String = IntentTable.KBM
var _bindings: Bindings = null
## The screen's stations.
var _stations: Array = []
var _phone: bool = false
var _summary: Label = Label.new()
var _buttons: HFlowContainer = HFlowContainer.new()
var _filter: Button = Button.new()
var _notes: Dictionary = {}
## The stations the touch pictures show.
var _touch_shown: Array = []


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_theme_color_override("font_color", Palette.color("text"))
	add_child(_summary)
	add_child(_buttons)
	for v: String in [VIEW_KBM, VIEW_PAD, VIEW_LIST]:
		var b: Button = Button.new()
		b.name = v
		b.toggle_mode = true
		b.pressed.connect(show_view.bind(v))
		_buttons.add_child(b)
	_filter.name = ALL_STATIONS
	_filter.toggle_mode = true
	_filter.toggled.connect(set_all_stations)
	_buttons.add_child(_filter)
	for v: String in [VIEW_KBM, VIEW_PAD]:
		var box: VBoxContainer = VBoxContainer.new()
		box.name = v + "View"
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.visible = false
		add_child(box)
		box.add_child(kbm if v == VIEW_KBM else pad)
		var note: Label = Label.new()
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override("font_color", Palette.color("text_dim"))
		box.add_child(note)
		_notes[v] = note
	touch.name = "TouchView"
	touch.add_theme_constant_override("separation", 16)
	touch.visible = false
	add_child(touch)
	list.name = VIEW_LIST + "View"
	add_child(list)


## Fills the pane for `stations` on `device` under the role summary of `role`; follows
## later rebinds. Shows the list on a phone, else the diagram of `device`; only the view
## showing is built.
func build(bindings: Bindings, stations: Array, device: String, role: String = "") -> void:
	if _bindings != null and _bindings.changed.is_connected(_refresh_notes):
		_bindings.changed.disconnect(_refresh_notes)
	_bindings = bindings
	_role = role
	_device = device
	_stations = stations
	_phone = is_inside_tree() and LayoutMode.kind_of(self) == LayoutMode.Kind.PHONE
	_bindings.changed.connect(_refresh_notes)
	_summary.visible = role != ""
	(_buttons.get_node(VIEW_KBM) as Control).visible = not _phone
	(_buttons.get_node(VIEW_PAD) as Control).visible = not _phone
	_retext()
	# The list is cheap and what tests and screen readers read: always built.
	list.build(bindings, shown_stations(), device, "")
	show_view(default_view(_phone, device))


## The view a menu opens on: the list on a phone, else the device in use.
static func default_view(phone: bool, device: String) -> String:
	if phone:
		return VIEW_LIST
	return VIEW_PAD if device == IntentTable.PAD else VIEW_KBM


## The stations shown: the screen's, or every station's with the filter on.
func shown_stations() -> Array:
	if not all_stations:
		return _stations
	var out: Array = []
	for g: String in IntentTable.GROUPS:
		if g not in [IntentTable.COMMON, IntentTable.LIVE]:
			out.append(g)
	return out


## Shows view `v`, building it for the stations shown when they changed. A phone shows
## only the list.
func show_view(v: String) -> void:
	if _phone:
		v = VIEW_LIST
	view = v
	for b: Node in _buttons.get_children():
		if b != _filter:
			(b as Button).button_pressed = b.name == v
	get_node(VIEW_KBM + "View").visible = v == VIEW_KBM
	get_node(VIEW_PAD + "View").visible = v == VIEW_PAD
	list.visible = v == VIEW_LIST
	touch.visible = _phone
	if _bindings == null:
		return
	var stations: Array = shown_stations()
	if _phone and _touch_shown != stations:
		_build_touch(stations)
	if list.shown_args() != [_bindings, stations, _device]:
		list.build(_bindings, stations, _device, "")
	if v == VIEW_LIST:
		return
	var d: ControlsDiagram = kbm if v == VIEW_KBM else pad
	var device: String = IntentTable.KBM if v == VIEW_KBM else IntentTable.PAD
	if d.shown_args() != [_bindings, stations, device]:
		d.build(_bindings, stations, device)
	_refresh_notes()


## The touch pictures of `stations`, each under the station's name.
func _build_touch(stations: Array) -> void:
	_touch_shown = stations.duplicate()
	for c: Node in touch.get_children():
		touch.remove_child(c)
		c.queue_free()
	for st: String in stations:
		var pic: TouchHelpPicture = TouchHelpPicture.make(st)
		if pic == null:
			continue
		var head: Label = Label.new()
		head.theme_type_variation = "HeadingLabel"
		head.text = tr("station." + st)
		touch.add_child(head)
		touch.add_child(pic)


## The filter: every station's controls, or only the screen's.
func set_all_stations(on: bool) -> void:
	all_stations = on
	_filter.set_pressed_no_signal(on)
	show_view(view)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _bindings != null:
		_retext()
		_refresh_notes()


func _retext() -> void:
	_summary.text = tr("role." + _role) if _role != "" else ""
	(_buttons.get_node(VIEW_KBM) as Button).text = tr("controls.view_kbm")
	(_buttons.get_node(VIEW_PAD) as Button).text = tr("controls.view_pad")
	(_buttons.get_node(VIEW_LIST) as Button).text = tr("controls.view_list")
	_filter.text = tr("controls.all_stations")


## The notes under the built diagrams: unbound intents of the screen, bindings off the
## picture.
func _refresh_notes() -> void:
	for v: String in _notes:
		var d: ControlsDiagram = kbm if v == VIEW_KBM else pad
		if d.shown_args().is_empty():
			continue
		var parts: PackedStringArray = []
		var unbound: PackedStringArray = []
		for id: String in d.model.unbound_here():
			unbound.append(tr(IntentTable.label_key(id)))
		if not unbound.is_empty():
			parts.append(tr("controls.unbound") % ", ".join(unbound))
		var off: PackedStringArray = []
		for e: Dictionary in d.model.unmapped():
			off.append("%s %s" % [e["label"], e["keys"]])
		if not off.is_empty():
			parts.append(tr("controls.off_diagram") % ", ".join(off))
		(_notes[v] as Label).text = "\n".join(parts)
		(_notes[v] as Label).visible = not parts.is_empty()
