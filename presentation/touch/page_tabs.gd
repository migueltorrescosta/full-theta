class_name PageTabs
extends HBoxContainer
## The tabs of a PageHost (#28 follow-up, P28-Tabs): in the phone's top bar on its side
## (at least TAB_W wide and as wide as the 13 px label) or as the bottom tab bar upright
## (equal widths). The current tab is the accent button. A `lead` button (a joint view's
## station chip, the dev seat's station button) goes first; while the host has a session
## title, a label replaces the tabs.
##
##     var tabs := PageTabs.new()
##     tabs.bind(panel.pages)
##     tabs.set_lead(station_chip)

## A tab's width on a phone on its side, and with a lead button beside the tabs.
const TAB_W: float = 64.0
const TAB_W_TIGHT: float = 56.0
const FONT: int = 13

## The bottom tab bar: the tabs share the width.
var upright: bool = false:
	set(value):
		upright = value
		_rebuild()
## The host shown; null shows no tabs.
var host: PageHost = null
## The lead button, or null.
var lead: Button = null

var _session: Label = Label.new()
var _buttons: Array[RailButton] = []


func _init() -> void:
	add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	_session.add_theme_font_size_override("font_size", FONT + 1)
	_session.add_theme_color_override("font_color", Palette.color("text"))
	_session.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_session.clip_text = true
	_session.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_session.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_session.visible = false
	add_child(_session)


## Shows `pages` (null for none); follows its changes.
func bind(pages: PageHost) -> void:
	if host == pages:
		return
	if host != null:
		host.tabs_changed.disconnect(_rebuild)
		host.page_changed.disconnect(_on_page)
	host = pages
	if host != null:
		host.tabs_changed.connect(_rebuild)
		host.page_changed.connect(_on_page)
	_rebuild()


## Puts `button` first (null removes the lead). The button is not freed.
func set_lead(button: Button) -> void:
	if lead == button:
		return
	if lead != null and lead.get_parent() == self:
		remove_child(lead)
	lead = button
	if lead != null:
		if lead.get_parent() != null:
			lead.get_parent().remove_child(lead)
		add_child(lead)
		move_child(lead, 0)
	_rebuild()


## The tab button of page `index` (tests), or null.
func tab(index: int) -> RailButton:
	return _buttons[index] if index >= 0 and index < _buttons.size() else null


func tab_count() -> int:
	return _buttons.size()


## True when the strip shows anything (tabs, a lead or a session title).
func has_content() -> bool:
	return lead != null or (host != null and host.count() > 0)


func _rebuild() -> void:
	for b: RailButton in _buttons:
		remove_child(b)
		b.queue_free()
	_buttons.clear()
	var session: bool = host != null and host.session_title != ""
	_session.visible = session
	_session.text = host.session_title if session else ""
	if host != null and not session:
		var w: float = TAB_W_TIGHT if lead != null else TAB_W
		for i: int in host.count():
			var b: RailButton = RailButton.make(host.title(i) + (" •" if host.badge(i) else ""))
			b.name = "Tab%d" % (i + 1)
			b.add_theme_font_size_override("font_size", FONT)
			# A tab is as wide as its label, never cut ("Requests", "Contracts").
			b.clip_text = false
			b.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
			b.custom_minimum_size = Vector2(0.0 if upright else w, UiTheme.TOUCH_PRIMARY)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL if upright else Control.SIZE_FILL
			b.pressed.connect(_on_tap.bind(i))
			add_child(b)
			_buttons.append(b)
	if lead != null:
		lead.size_flags_horizontal = Control.SIZE_EXPAND_FILL if upright else Control.SIZE_FILL
		move_child(lead, 0)
	_mark()


func _on_tap(index: int) -> void:
	if host != null:
		host.select(index)
	_mark()


func _on_page(_index: int) -> void:
	_mark()


## The current tab is the accent one.
func _mark() -> void:
	for i: int in _buttons.size():
		var on: bool = host != null and i == host.current
		_buttons[i].role = RailButton.Role.ACCENT if on else RailButton.Role.PLAIN
