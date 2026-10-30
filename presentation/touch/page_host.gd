class_name PageHost
extends RefCounted
## A station's pages on a phone (#28 follow-up, owner pick P28-Tabs): up to MAX pages, each
## a set of controls (`parts`) that show only while the page is current. A page swaps only
## its own parts, so whatever the station never adds here (sticks, FIRE, the throttle, the
## view) is the persistent zone and never pages away. The first page is the resting state.
##
## The station screen draws the tabs: in the top bar on a phone on its side, in a bottom
## tab bar upright (PageTabs). A station only fills the host and sets it on its panel:
##
##     pages = PageHost.new()
##     pages.add_page("Fly", [face_row, track_row])
##     pages.add_page("Nav", [nav_rows])
##     pages.add_page("Crew", [CrewPage.new(self)])

## The current page changed (a tab tap, or a station setting `current`).
signal page_changed(index: int)
## Titles, badges or the session title changed: the tabs redraw.
signal tabs_changed

## At most five pages a station (design 1.1).
const MAX: int = 5

## The page showing (-1 before the first add_page); setting it switches.
var current: int:
	get:
		return _current
	set(value):
		select(value)
## While not empty the tab strip shows this instead of tabs (a Science scan or hack session,
## "Scan H2 · 12 s"): pages don't change during a session.
var session_title: String = "":
	set(value):
		if value != session_title:
			session_title = value
			tabs_changed.emit()

var _current: int = -1
var _titles: Array[String] = []
var _parts: Array[Array] = []
var _badges: Array[bool] = []


## Adds a page titled `title` holding `parts` (controls anywhere in the panel); the first
## page added shows, the others hide. Returns its index, or -1 past MAX.
func add_page(title: String, parts: Array) -> int:
	if _titles.size() >= MAX:
		push_error("PageHost: more than %d pages" % MAX)
		return -1
	var i: int = _titles.size()
	_titles.append(title)
	var own: Array[Control] = []
	for p: Variant in parts:
		if p is Control:
			own.append(p)
	_parts.append(own)
	_badges.append(false)
	if _current < 0:
		_current = 0
	_show()
	tabs_changed.emit()
	return i


## Adds `control` to page `index` (a part built after the page).
func add_part(index: int, control: Control) -> void:
	if index < 0 or index >= _parts.size():
		return
	_parts[index].append(control)
	control.visible = index == _current


func count() -> int:
	return _titles.size()


func title(index: int) -> String:
	return _titles[index] if index >= 0 and index < _titles.size() else ""


func titles() -> Array[String]:
	return _titles.duplicate()


## The controls of page `index`.
func parts(index: int) -> Array[Control]:
	var out: Array[Control] = []
	if index >= 0 and index < _parts.size():
		out.assign(_parts[index])
	return out


## A dot on the tab (a waiting hail on Comms' Hails page).
func set_badge(index: int, on: bool) -> void:
	if index < 0 or index >= _badges.size() or _badges[index] == on:
		return
	_badges[index] = on
	tabs_changed.emit()


func badge(index: int) -> bool:
	return index >= 0 and index < _badges.size() and _badges[index]


## Shows page `index`; nothing for an unknown index, the current one, or during a session.
func select(index: int) -> void:
	if index < 0 or index >= _titles.size() or index == _current or session_title != "":
		return
	_current = index
	_show()
	page_changed.emit(index)


## Shows the parts of the current page and hides the others' (a part on two pages shows).
func _show() -> void:
	for i: int in _parts.size():
		if i != _current:
			for c: Control in _parts[i]:
				if is_instance_valid(c):
					c.visible = false
	if _current >= 0:
		for c: Control in _parts[_current]:
			if is_instance_valid(c):
				c.visible = true
