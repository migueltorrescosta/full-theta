class_name CrewPage
extends ScrollContainer
## The Crew page of a phone station (#28 follow-up, P28-Common, design 2.0): the station's
## request chips (FT-STN-010; a joint view's own pair acts directly, FT-JNT-005), Ping and
## Mark on the selection, and one Share button per data shortcut this screen may share
## (D210), as half-width rail buttons, scrolling past six. A chip waiting for an answer shows
## its seconds left; a share shows its seconds left. Add it as a station's last page:
##
##     var crew := CrewPage.new(self)
##     pages.add_page(TouchText.of("page.crew", "Crew"), [crew])
##     rail.add(crew)

const COLUMNS: int = 2

var panel: StationPanel
var grid: GridContainer = GridContainer.new()

## What the buttons show, to rebuild only on a change.
var _shown: Array = []
var _buttons: Array[RailButton] = []


func _init(owner_panel: StationPanel = null) -> void:
	panel = owner_panel
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", UiTheme.TOUCH_GAP)
	grid.add_theme_constant_override("v_separation", UiTheme.TOUCH_GAP)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(grid)


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		refresh()


## The buttons' entries: [kind, id, label] for each chip, Ping, Mark and share.
func entries() -> Array:
	var out: Array = []
	if panel == null or panel.ctx == null:
		return out
	for c: ChipDef in panel.request_chips():
		out.append(["chip", String(c.id), panel.chip_label(c)])
	out.append(["ping", "", tr("intent.ping")])
	if panel.ctx.crew.entry != StationViews.VIEWER:
		out.append(["mark", "", tr("intent.mark")])
	var stations: Array[String] = []
	stations.assign(panel.ctx.crew.stations())
	if panel.ctx.crew.is_crew():
		for id: StringName in ShareBar.features(stations, panel.ctx.crew.toggles):
			out.append(["share", String(id), tr("share.button") % tr("lobby.toggle." + String(id))])
	return out


## Rebuilds the buttons when the entries change, and updates their seconds left.
func refresh() -> void:
	var now: Array = entries()
	if now != _shown:
		_shown = now
		for b: RailButton in _buttons:
			grid.remove_child(b)
			b.queue_free()
		_buttons.clear()
		for e: Array in now:
			var b: RailButton = RailButton.make(str(e[2]))
			b.name = "%s_%s" % [e[0], e[1]] if e[1] != "" else str(e[0])
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.clip_text = false
			b.add_theme_font_size_override("font_size", 13)
			b.pressed.connect(_press.bind(e))
			grid.add_child(b)
			_buttons.append(b)
	for i: int in now.size():
		var left: float = _left(now[i])
		var text: String = str(now[i][2])
		if left > 0.0:
			text = "%s · %d s" % [text, ceili(left)]
		if _buttons[i].text != text:
			_buttons[i].text = text


## The button of entry kind `kind` (and id), or null (tests).
func button(kind: String, id: String = "") -> RailButton:
	for i: int in _shown.size():
		if _shown[i][0] == kind and (id == "" or _shown[i][1] == id):
			return _buttons[i]
	return null


## Seconds left of a waiting chip or a running share, else 0.
func _left(e: Array) -> float:
	var ctx: StationContext = panel.ctx
	match e[0]:
		"chip":
			for c: Dictionary in ChipView.outgoing(ctx.view, [panel.station]):
				if c["chip"] == e[1]:
					return ChipView.left_s(ctx.view, c)
		"share":
			return ctx.crew.share_left(StringName(e[1]), ctx.now_ms())
	return 0.0


func _press(e: Array) -> void:
	match e[0]:
		"chip":
			for c: ChipDef in panel.request_chips():
				if String(c.id) == e[1]:
					panel.send_chip(c)
		"ping", "mark":
			panel.common_requested.emit(str(e[0]))
		"share":
			panel.ctx.intents.share(str(e[1]))
