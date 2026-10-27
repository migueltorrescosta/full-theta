class_name TouchTabs
extends VBoxContainer
## Tabs for a rail (#28): a row of rail buttons over pages, one page showing. Secondary
## groups go here instead of a scrolling list (a scroll steals the drag from a stick).
##
##     var tabs := TouchTabs.new()
##     tabs.add_tab("Nav", nav_page)
##     tabs.add_tab("Shield", shield_page)
##     rail.add(tabs)

signal tab_changed(index: int)

## The tab buttons, in order.
var header: HBoxContainer = HBoxContainer.new()
## The page showing (-1 before the first add_tab); setting it switches.
var current: int:
	get:
		return _current
	set(value):
		_select(value)

var _current: int = -1
var _pages: Array[Control] = []
var _group: ButtonGroup = ButtonGroup.new()


func _init() -> void:
	add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	header.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	add_child(header)


## Adds a page titled `title`; the first one added shows. Returns its index.
func add_tab(title: String, page: Control) -> int:
	var i: int = _pages.size()
	var b: RailButton = RailButton.make(title)
	b.toggle_mode = true
	b.button_group = _group
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(func() -> void: _select(i))
	header.add_child(b)
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.visible = false
	add_child(page)
	_pages.append(page)
	if _current < 0:
		_select(0)
	return i


func tab_count() -> int:
	return _pages.size()


## The tab button of page `index`.
func tab_button(index: int) -> RailButton:
	return header.get_child(index) as RailButton


func _select(index: int) -> void:
	if index < 0 or index >= _pages.size() or index == _current:
		return
	_current = index
	for i: int in _pages.size():
		_pages[i].visible = i == index
		tab_button(i).set_pressed_no_signal(i == index)
	tab_changed.emit(index)
