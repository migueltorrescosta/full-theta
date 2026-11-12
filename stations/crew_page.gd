class_name CrewPage
extends ScrollContainer
## The Crew page of a phone station (#28 follow-up, P28-Common, design 2.0): one Share button
## per data shortcut this screen may share (D210), as half-width rail buttons, each showing
## its seconds left while it runs. Ping and Mark are on the selection sheet (and the Captain's
## rail), the request chips at the top of the view (C4, C5): the page holds the shares only.
## Add it as a station's last page:
##
##     var crew := CrewPage.new(self)
##     pages.add_page(TouchText.of("page.crew", "Crew"), [crew])
##     rail.add(crew)

const COLUMNS: int = 2
## The button text sizes (px), the largest in which the longest word fits the button.
const FONT_SIZES: Array[int] = [13, 12, 11, 10]

var panel: StationPanel
var grid: GridContainer = GridContainer.new()

## What the buttons show, to rebuild only on a change.
var _shown: Array = []
var _buttons: Array[RailButton] = []
## What entries() reads (seat, toggles, language): entries are rebuilt only when it changes
## (R20-12).
var _inputs: Array = []
## The size and texts the buttons were last fitted to: _fit_text and _snap_rows run only
## when they change (R20-12).
var _fitted: Array = []


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


## The buttons' entries: [kind, id, label], one "share" per data shortcut this pick may share.
func entries() -> Array:
	var out: Array = []
	if panel == null or panel.ctx == null or not panel.ctx.crew.is_crew():
		return out
	var stations: Array[String] = []
	stations.assign(panel.ctx.crew.stations())
	for id: StringName in ShareBar.features(stations, panel.ctx.crew.toggles):
		out.append(["share", String(id), tr("share.button") % tr("lobby.toggle." + String(id))])
	return out


## Rebuilds the buttons when the entries' inputs change, and updates their seconds left; the
## text fit and the row snap follow a change of size or text only.
func refresh() -> void:
	var inputs: Array = _read_inputs()
	if inputs != _inputs:
		_inputs = inputs
		_rebuild(entries())
	for i: int in _shown.size():
		var left: float = _left(_shown[i])
		var text: String = str(_shown[i][2])
		if left > 0.0:
			text = "%s · %d s" % [text, ceili(left)]
		if _buttons[i].text != text:
			_buttons[i].text = text
	var column: Control = get_parent() as Control
	var fitted: Array = [size, column.size if column != null else Vector2.ZERO]
	for b: RailButton in _buttons:
		fitted.append(b.text)
		fitted.append(b.size)
	if fitted != _fitted:
		_fitted = fitted
		_fit_text()
		_snap_rows()


func _read_inputs() -> Array:
	if panel == null or panel.ctx == null:
		return []
	var crew: CrewState = panel.ctx.crew
	return [crew.seat, crew.toggles.encode(), TranslationServer.get_locale()]


func _rebuild(now: Array) -> void:
	if now == _shown:
		return
	_shown = now
	for b: RailButton in _buttons:
		grid.remove_child(b)
		b.queue_free()
	_buttons.clear()
	for e: Array in now:
		var b: RailButton = RailButton.make(str(e[2]))
		b.name = "%s_%s" % [e[0], e[1]]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# (by words: a long word never splits, "countdo wns")
		b.autowrap_mode = TextServer.AUTOWRAP_WORD
		b.clip_text = false
		b.add_theme_font_size_override("font_size", FONT_SIZES[0])
		b.pressed.connect(_press.bind(e))
		grid.add_child(b)
		_buttons.append(b)


## Each button shows its text in the largest size where its longest word fits, so a long
## word is never cut ("countdo"); the words wrap onto lines.
func _fit_text() -> void:
	var font: Font = get_theme_default_font()
	for b: RailButton in _buttons:
		var style: StyleBox = b.get_theme_stylebox("normal")
		var room: float = b.size.x - style.get_minimum_size().x - 2.0
		if room <= 0.0:
			continue
		var fit: int = FONT_SIZES[-1]
		for fs: int in FONT_SIZES:
			var widest: float = 0.0
			for word: String in b.text.split(" ", false):
				widest = maxf(
					widest, font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				)
			if widest <= room:
				fit = fs
				break
		if b.get_theme_font_size("font_size") != fit:
			b.add_theme_font_size_override("font_size", fit)


## When the buttons scroll, the page ends under its last whole row, so no button is cut at
## rest (D319): it shrinks to those rows, in the column it sits in, instead of filling it.
func _snap_rows() -> void:
	var column: BoxContainer = get_parent() as BoxContainer
	if column == null or not column.vertical or grid.get_child_count() == 0:
		return
	var room: float = column.size.y
	var gap: float = float(column.get_theme_constant("separation"))
	for sibling: Node in column.get_children():
		var c: Control = sibling as Control
		if c != null and c != self and c.visible:
			room -= c.get_combined_minimum_size().y + gap
	var keep: float = 0.0
	if grid.get_combined_minimum_size().y > room:
		for b: Node in grid.get_children():
			var bottom: float = (b as Control).get_rect().end.y
			if bottom <= room:
				keep = maxf(keep, bottom)
	var want: int = SIZE_SHRINK_BEGIN if keep > 0.0 else SIZE_EXPAND_FILL
	if size_flags_vertical != want:
		size_flags_vertical = want
	if int(custom_minimum_size.y) != int(keep):
		custom_minimum_size.y = keep


## The button of entry kind `kind` (and id), or null (tests).
func button(kind: String, id: String = "") -> RailButton:
	for i: int in _shown.size():
		if _shown[i][0] == kind and (id == "" or _shown[i][1] == id):
			return _buttons[i]
	return null


## Seconds left of a running share, else 0.
func _left(e: Array) -> float:
	return panel.ctx.crew.share_left(StringName(e[1]), panel.ctx.now_ms())


func _press(e: Array) -> void:
	panel.ctx.intents.share(str(e[1]))
