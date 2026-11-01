extends RefCounted
## Phone reachability walker for strand WR's stations (#28 follow-up, D287): from a station's
## resting state (first page, no sheet open) it taps a page tab when the action is on another
## page, then the action's control, then a sheet option when the row names one, and counts
## the taps. Preload it (no class_name, so other strands' helpers can't clash):
##
##     const Reach = preload("res://tests/stations/wr/phone_reach.gd")
##     var r: Dictionary = Reach.walk(screen, {"page": 1, "control": "Touch_claim"})
##     assert_str(r["error"]).is_empty()
##
## A row: "page" (index in the panel's PageHost, 0 = rest), "control" (the node name of a
## visible BaseButton in the focused panel, or a Callable(screen) -> BaseButton), optional
## "option" (a sheet option index tapped next), "taps" (most taps allowed, default 2).


## Puts the screen back to rest: no sheet, first page.
static func rest(s: StationScreen) -> void:
	if s.sheet.is_open():
		s.sheet.cancel()
	var p: StationPanel = s.focused_panel()
	if p.pages != null:
		p.pages.current = 0


## The tab strip a phone shows: the top bar on its side, the bottom tab bar upright.
static func strip(s: StationScreen) -> PageTabs:
	return s.top_bar.tabs if s.top_bar.tabs.tab_count() > 0 else s.frame.bottom_tabs


## Walks one row from rest: {"taps": int, "error": String} (error "" when reached in time).
static func walk(s: StationScreen, row: Dictionary) -> Dictionary:
	rest(s)
	var taps: int = 0
	var page: int = int(row.get("page", 0))
	var p: StationPanel = s.focused_panel()
	if page > 0:
		if p.pages == null or page >= p.pages.count():
			return {"taps": taps, "error": "no page %d" % page}
		var tab: RailButton = strip(s).tab(page)
		if tab == null or not tab.is_visible_in_tree():
			return {"taps": taps, "error": "tab %d not shown" % page}
		tab.pressed.emit()
		taps += 1
		# A Crew page fills its buttons when it shows (it refreshes each frame).
		for crew: Node in p.find_children("*", "CrewPage", true, false):
			(crew as CrewPage).refresh()
	var c: BaseButton = control(s, row["control"])
	if c == null:
		return {"taps": taps, "error": "%s not found" % str(row["control"])}
	if not c.is_visible_in_tree():
		return {"taps": taps, "error": "%s hidden on page %d" % [c.name, page]}
	if c.disabled:
		return {"taps": taps, "error": "%s disabled" % c.name}
	if c.get_global_rect().end.y > SafeArea.tap_bottom(s) + 0.5:
		return {"taps": taps, "error": "%s in the band" % c.name}
	c.pressed.emit()
	taps += 1
	if row.has("option"):
		if not s.sheet.is_open():
			return {"taps": taps, "error": "%s opened no sheet" % c.name}
		var o: RailButton = s.sheet.option(int(row["option"]))
		if o == null:
			return {"taps": taps, "error": "no option %d" % int(row["option"])}
		o.pressed.emit()
		taps += 1
	var most: int = int(row.get("taps", 2))
	if taps > most:
		return {"taps": taps, "error": "%d taps, at most %d" % [taps, most]}
	return {"taps": taps, "error": ""}


## The row's control: a Callable's result, or the first visible BaseButton named `which`
## in the focused panel (else in the whole screen).
static func control(s: StationScreen, which: Variant) -> BaseButton:
	if which is Callable:
		return (which as Callable).call(s)
	var name: String = str(which)
	var found: BaseButton = null
	for root: Node in [s.focused_panel(), s]:
		for n: Node in root.find_children(name, "BaseButton", true, false):
			if (n as Control).is_visible_in_tree():
				return n
			if found == null:
				found = n
	return found
