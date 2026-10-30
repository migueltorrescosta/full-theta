class_name PhoneReach
extends RefCounted
## Walks a phone station's pages and sheets the way a finger does (#28 follow-up, D287:
## every action within 2 taps of the resting state, combat actions on the first page at 1
## tap). A row of a station's reachability table names the page, the button (found on the
## page once it shows) and, for an action that needs a choice, the sheet option; `tap_row`
## goes back to rest, taps the page's tab (unless it is the first page), the button and the
## option, and returns how many taps that took (-1 when a step was not there to tap). A page
## gets a frame to fill itself (the Crew page builds its buttons when it shows).
##
##     var taps: int = await PhoneReach.tap_row(screen, [page, func() -> BaseButton: ..., -1])

const REST: int = 0


## A finger's tap on a button: press and release over its centre.
static func tap(b: BaseButton) -> void:
	var t: InputEventScreenTouch = InputEventScreenTouch.new()
	t.index = 0
	t.position = b.size / 2.0
	t.pressed = true
	b._gui_input(t)
	t.pressed = false
	b._gui_input(t)


## Back to the resting state: the sheet closed, the first page showing.
static func rest(s: StationScreen) -> void:
	if s.sheet.is_open():
		s.sheet.cancel()
	var pages: PageHost = s.focused_panel().pages
	if pages != null:
		pages.current = REST


## The tab of page `index` in the strip that shows (top bar on its side, bottom bar upright).
static func tab(s: StationScreen, index: int) -> RailButton:
	for strip: PageTabs in [s.top_bar.tabs, s.frame.bottom_tabs]:
		if strip.is_visible_in_tree() and strip.tab(index) != null:
			return strip.tab(index)
	return null


## Taps one row ([page, button finder, sheet option index or -1]) from rest; the taps it
## took, or -1 when a tab, the button or the option was missing, hidden or disabled.
static func tap_row(s: StationScreen, row: Array) -> int:
	rest(s)
	var taps: int = 0
	var page: int = row[0]
	if page != REST:
		var t: RailButton = tab(s, page)
		if not _usable(t):
			return -1
		tap(t)
		taps += 1
		await s.get_tree().process_frame
	var b: BaseButton = (row[1] as Callable).call()
	if not _usable(b):
		return -1
	tap(b)
	taps += 1
	var option: int = row[2] if row.size() > 2 else -1
	if option >= 0:
		if not s.sheet.is_open():
			return -1
		var o: RailButton = s.sheet.option(option)
		if not _usable(o):
			return -1
		tap(o)
		taps += 1
	return taps


static func _usable(b: BaseButton) -> bool:
	return b != null and b.is_visible_in_tree() and not b.disabled
