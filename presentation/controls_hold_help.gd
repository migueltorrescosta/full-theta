class_name HoldHelp
extends RefCounted
## Hold-to-explain for jargon buttons (D6, R26-4): a touch hold on a RailButton (a mouse
## hover on a desktop) says in a line what it does, using the `help.*` strings the Controls
## page already shows for the phone pages (TouchHelpPicture, each station's `touch_help()`).
## No button is renamed and no station lists its buttons here: a button's label is looked up
## in the stations' help boxes, whose names are those labels ("Cause", "Probe", "Claim").

## Seconds a finger holds before the line shows, and how long the line stays.
const HOLD_S: float = 0.5
const SHOW_S: float = 3.0

static var _table: Dictionary = {}
static var _locale: String = ""


## The one-line explanation of the button labelled `label` ("Guess cause", "Take crew\nA"), or ""
## when no station's help boxes name it. The longest box name the label equals or starts with
## (followed by a space) wins.
static func explain(label: String) -> String:
	# A rail button's second line names its part or reason ("Repair part\nENG"): the label
	# is its first line.
	label = label.get_slice("\n", 0)
	var t: Dictionary = table()
	if t.has(label):
		return t[label]
	var best: String = ""
	for name_of: String in t:
		if label.begins_with(name_of + " ") and name_of.length() > best.length():
			best = name_of
	return t[best] if best != "" else ""


## Box name -> what it does, from every station's touch help in the current language (the
## first station to name a control wins). Rebuilt when the language changes.
static func table() -> Dictionary:
	var locale: String = TranslationServer.get_locale()
	if locale == _locale and not _table.is_empty():
		return _table
	_locale = locale
	_table = {}
	for station: String in TouchHelpPicture.PANELS:
		for page: Dictionary in TouchHelpPicture.help_of(station):
			for box: Array in page["boxes"]:
				var named: String = str(box[1])
				if str(box[2]) != named and not _table.has(named):
					_table[named] = str(box[2])
	return _table


## Shows `text` as a bubble above `button` for SHOW_S seconds (drawn over its neighbours,
## kept inside the viewport).
static func bubble(button: Control, text: String) -> void:
	var old: Node = button.get_node_or_null("HoldHelp")
	if old != null:
		old.queue_free()
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "HoldHelp"
	panel.top_level = true
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 220.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	panel.add_theme_stylebox_override("panel", UiTheme.box("panel", "line_strong", 8, 8))
	button.add_child(panel)
	var room: Rect2 = button.get_viewport_rect()
	var want: Vector2 = panel.get_combined_minimum_size()
	var x: float = clampf(button.global_position.x, room.position.x, room.end.x - want.x)
	var y: float = button.global_position.y - want.y - 4.0
	if y < room.position.y:
		y = button.global_position.y + button.size.y + 4.0
	panel.global_position = Vector2(x, y)
	button.get_tree().create_timer(SHOW_S).timeout.connect(
		func() -> void:
			if is_instance_valid(panel):
				panel.queue_free()
	)
