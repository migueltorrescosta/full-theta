class_name FirstRunTooltip
extends PanelContainer
## A station's first-run tooltip (FT-STN-012, D100): explains its controls only, from the
## live bindings (never "talk to X"); shown once per client and station, dismissable;
## Settings re-enables them (ClientSettings.reset_tooltips). Dismissing marks the station
## seen in the settings; the caller saves them.

signal dismissed(station: String)

var got_it: Button = Button.new()
var close: Button = Button.new()

var _station: String = ""
var _settings: ClientSettings = null
var _title: Label = Label.new()
var _lines: VBoxContainer = VBoxContainer.new()


func _init() -> void:
	visible = false
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Palette.color("panel_focus")
	box.border_color = Palette.color("accent")
	box.set_border_width_all(1)
	box.set_content_margin_all(12)
	add_theme_stylebox_override("panel", box)
	var col: VBoxContainer = VBoxContainer.new()
	add_child(col)
	var head: HBoxContainer = HBoxContainer.new()
	_title.size_flags_horizontal = SIZE_EXPAND_FILL
	_title.add_theme_color_override("font_color", Palette.color("text"))
	close.text = "×"
	close.flat = true
	head.add_child(_title)
	head.add_child(close)
	col.add_child(head)
	col.add_child(_lines)
	got_it.size_flags_horizontal = SIZE_SHRINK_END
	col.add_child(got_it)
	got_it.pressed.connect(_dismiss)
	close.pressed.connect(_dismiss)


## Shows the tip of `station` listing `intents` unless settings has it seen; false when
## not shown. Intents unbound on `device` are left out.
func show_for(
	station: String,
	intents: Array[String],
	bindings: Bindings,
	device: String,
	settings: ClientSettings
) -> bool:
	if settings.tooltip_seen(station):
		visible = false
		return false
	_station = station
	_settings = settings
	_title.text = tr("tooltip.title")
	got_it.text = tr("tooltip.got_it")
	for c: Node in _lines.get_children():
		_lines.remove_child(c)
		c.queue_free()
	for id: String in intents:
		var list: PackedStringArray = bindings.bindings(id, device)
		if list.is_empty():
			continue
		var l: Label = Label.new()
		l.text = "%s: %s" % [tr(IntentTable.label_key(id)), BindingText.describe_all(list)]
		l.add_theme_color_override("font_color", Palette.color("text"))
		_lines.add_child(l)
	visible = true
	return true


## The lines shown (tests).
func lines() -> Array[String]:
	var out: Array[String] = []
	for l: Node in _lines.get_children():
		out.append((l as Label).text)
	return out


func _dismiss() -> void:
	visible = false
	if _settings != null:
		_settings.mark_tooltip_seen(_station)
	dismissed.emit(_station)
