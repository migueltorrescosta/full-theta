class_name ControlsPane
extends VBoxContainer
## The menu's Controls tab (FT-STN-011, FT-STN-012, D185): the seat's role summary over
## three views of the same live bindings, picked with buttons: the keyboard-and-mouse
## diagram, the controller diagram and the text list (ControlsList), which stays the
## way in for a touch device or a screen reader. A phone opens on the list; others on
## the diagram of the device in use. Under a diagram, the screen's intents that are not
## bound on that device and the bindings it can't draw.

const VIEW_KBM: String = "Keyboard"
const VIEW_PAD: String = "Gamepad"
const VIEW_LIST: String = "List"

## The text list view; also what SettingsScreen.controls exposes.
var list: ControlsList = ControlsList.new()
var kbm: ControlsDiagram = ControlsDiagram.new()
var pad: ControlsDiagram = ControlsDiagram.new()
var view: String = VIEW_LIST

var _role: String = ""
var _device: String = IntentTable.KBM
var _bindings: Bindings = null
var _summary: Label = Label.new()
var _buttons: HFlowContainer = HFlowContainer.new()
var _notes: Dictionary = {}


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
	for v: String in [VIEW_KBM, VIEW_PAD]:
		var box: VBoxContainer = VBoxContainer.new()
		box.name = v + "View"
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(box)
		box.add_child(kbm if v == VIEW_KBM else pad)
		var note: Label = Label.new()
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.add_theme_color_override("font_color", Palette.color("text_dim"))
		box.add_child(note)
		_notes[v] = note
	list.name = VIEW_LIST + "View"
	add_child(list)


## Fills the pane for `stations` on `device` under the role summary of `role`; follows
## later rebinds. Opens on the list on a phone, else on the diagram of `device`.
func build(bindings: Bindings, stations: Array, device: String, role: String = "") -> void:
	if _bindings != null and _bindings.changed.is_connected(_refresh_notes):
		_bindings.changed.disconnect(_refresh_notes)
	_bindings = bindings
	_role = role
	_device = device
	list.build(bindings, stations, device, "")
	kbm.build(bindings, stations, IntentTable.KBM)
	pad.build(bindings, stations, IntentTable.PAD)
	_bindings.changed.connect(_refresh_notes)
	_summary.visible = role != ""
	_retext()
	_refresh_notes()
	show_view(
		default_view(is_inside_tree() and LayoutMode.kind_of(self) == LayoutMode.Kind.PHONE, device)
	)


## The view a menu opens on: the list on a phone, else the device in use.
static func default_view(phone: bool, device: String) -> String:
	if phone:
		return VIEW_LIST
	return VIEW_PAD if device == IntentTable.PAD else VIEW_KBM


func show_view(v: String) -> void:
	view = v
	for b: Node in _buttons.get_children():
		(b as Button).button_pressed = b.name == v
	get_node(VIEW_KBM + "View").visible = v == VIEW_KBM
	get_node(VIEW_PAD + "View").visible = v == VIEW_PAD
	list.visible = v == VIEW_LIST


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and _bindings != null:
		_retext()
		_refresh_notes()


func _retext() -> void:
	_summary.text = tr("role." + _role) if _role != "" else ""
	(_buttons.get_node(VIEW_KBM) as Button).text = tr("controls.view_kbm")
	(_buttons.get_node(VIEW_PAD) as Button).text = tr("controls.view_pad")
	(_buttons.get_node(VIEW_LIST) as Button).text = tr("controls.view_list")


## The notes under the diagrams: unbound intents of the screen, bindings off the picture.
func _refresh_notes() -> void:
	for v: String in _notes:
		var d: ControlsDiagram = kbm if v == VIEW_KBM else pad
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
