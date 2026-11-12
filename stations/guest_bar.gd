class_name GuestBar
extends PanelContainer
## A guest's way onto a friendly ship's free light stations (#40 D10, gp-04, FT-NET-049): the
## server marks the session's own seat row `guest` once its eliminated crew was handed over to
## the ship it watches (co-op and teams). While the guest watches (Viewer) and at least one
## light station is free, "Help out:" lists them, each a button that picks it through the
## normal Pick; seated at one, "Back to watching" picks the Viewer again. Nothing shows for
## anyone else, or with no station free (D412: no control that only refuses).
##
## Sits at the top right under the top bar, clear of the handover notice in the middle; on a
## phone Help out spans the bottom (wrapping), and Back to watching sits under the view-top
## row at the right.

## The kinds of crew change it follows.
const KINDS: Array[StringName] = [&"lobby", &"fleet", &"picked", &"handover", &"relaunch"]
## Under the desktop top bar and its goal row (px).
const DESK_TOP: float = 68.0
const EDGE: float = 8.0
## The stations a guest may take, as the server's NetLobby.LIGHT_STATIONS.
const LIGHT_STATIONS: Array[String] = ["engineering", "science", "relay", "comms"]

var ctx: StationContext

var _row: HFlowContainer
var _label: Label


func setup(context: StationContext) -> void:
	ctx = context
	name = "GuestBar"
	_row = HFlowContainer.new()
	_row.name = "Row"
	_row.add_theme_constant_override("h_separation", UiTheme.TOUCH_GAP)
	_row.add_theme_constant_override("v_separation", UiTheme.TOUCH_GAP)
	add_child(_row)
	_label = Label.new()
	_label.name = "HelpOut"
	_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_row.add_child(_label)
	ctx.crew.changed.connect(_on_crew_changed)
	refresh()


func _enter_tree() -> void:
	PhoneSheet.follow_viewport(self, _place, true)
	_place.call_deferred()


## The session's own seat row on its ship when the server marks it a guest, else {}.
static func guest_row(context: StationContext) -> Dictionary:
	for row: Variant in context.crew.ship_state(context.crew.ship).get("seats", []):
		var r: Dictionary = row
		if int(r.get("session", -1)) == context.crew.session and bool(r.get("guest", false)):
			return r
	return {}


## The light stations of the watched ship a guest may take (NetLobby._guest_rule): none
## another player's seat covers, none a stand-in holds for a dropped player (a fill bot gives
## way), in LIGHT_STATIONS order.
static func free_stations(context: StationContext) -> Array[String]:
	var state: Dictionary = context.crew.ship_state(context.crew.ship)
	var taken: Dictionary = {}
	for row: Variant in state.get("seats", []):
		if int((row as Dictionary).get("session", -1)) != context.crew.session:
			for st: String in StationCatalogue.stations_of(str(row.get("seat", ""))):
				taken[st] = true
	for bot: Variant in state.get("bots", []):
		if str((bot as Dictionary).get("for", "")) != "":
			taken[str(bot["seat"])] = true
	var out: Array[String] = []
	for st: String in LIGHT_STATIONS:
		if not taken.has(st):
			out.append(st)
	return out


## Shows the guest's choices, or hides.
func refresh() -> void:
	for c: Node in _row.get_children():
		if c != _label:
			_row.remove_child(c)
			c.queue_free()
	var guest: bool = not guest_row(ctx).is_empty()
	var watching: bool = ctx.crew.seat == StationCatalogue.VIEWER
	var open: Array[String] = []
	if guest and watching:
		open = free_stations(ctx)
	visible = guest and (not watching or not open.is_empty())
	if not visible:
		return
	_label.visible = watching
	_label.text = tr("guest.help_out")
	if watching:
		for st: String in open:
			_row.add_child(_button("Take_" + st, tr(StationCatalogue.name_key(st)), st))
	else:
		_row.add_child(_button("BackToWatching", tr("guest.back"), StationCatalogue.VIEWER))
	_place.call_deferred()


func _button(node_name: String, text: String, seat: String) -> Button:
	var b: Button = Button.new()
	b.name = node_name
	b.text = text
	b.custom_minimum_size.y = UiTheme.TOUCH_MIN
	b.pressed.connect(func() -> void: ctx.intents.pick(ctx.crew.ship, seat))
	return b


## At the top right under the top bar; on a phone Help out across the bottom, above the safe
## area, and Back to watching under the view-top row.
func _place() -> void:
	if not is_inside_tree() or _row == null:
		return
	var area: Vector2 = get_parent_area_size()
	var phone: bool = PhoneSheet.is_phone(self)
	var wide: bool = phone and ctx.crew.seat == StationCatalogue.VIEWER
	# One row where it fits: the flow is as wide as its buttons, up to the screen.
	var need: float = 0.0
	for c: Node in _row.get_children():
		if (c as Control).visible:
			need += (c as Control).get_combined_minimum_size().x + UiTheme.TOUCH_GAP
	need += get_theme_stylebox("panel").get_minimum_size().x
	custom_minimum_size.x = area.x - 2.0 * EDGE if wide else minf(need, area.x - 2.0 * EDGE)
	reset_size()
	if wide:
		var bottom: float = SafeArea.margins(self).w
		position = Vector2(EDGE, area.y - bottom - size.y - EDGE)
		return
	var top: float = VotePrompt.phone_top(self) if phone else DESK_TOP
	position = Vector2(area.x - size.x - EDGE, top)


func _on_crew_changed(what: StringName) -> void:
	if what in KINDS:
		refresh()
