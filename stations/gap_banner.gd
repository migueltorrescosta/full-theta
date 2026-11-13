class_name GapBanner
extends PanelContainer
## Skip the quiet gap (gp-07, D3): during the director's gap between two encounters, a small
## card says how long the quiet lasts and how many of the fleet's crew are Ready, with
## one toggle, "Ready for the next one". It shows only to a session that votes (a human crew
## player or the Captain on a ship of the fleet in play: CrewState.votes_on_gap), so a viewer
## never sees a control it can't use. Once every voter is Ready the server ends the gap; the
## card goes when the gap does. It sits at the top centre, under the top bar (on a phone under
## the view-top row, like the vote prompts), where no readout or control is.
## Crew-chosen sites (E2, w-bzx): to a picker (CrewState.picks_site: the Captain, or Comms
## with no Captain seated) with 2+ offers, the card also shows "Pick the next site" and one
## exclusive toggle per offer above Ready (the site's name, then its risk and pay tags); a tap
## sends SitePick. Everyone else sees no choice. The offers sit in a row on a desktop and a
## phone held sideways, else in a column (a tablet's side panel and a phone's width).

var ctx: StationContext

var _text: Label
var _ready: Button
var _pick_box: VBoxContainer
var _heading: Label
var _offers: GridContainer
var _group: ButtonGroup = ButtonGroup.new()
## The offers and the pick the toggles show (rebuilt and re-pressed when the event changes them,
## so an optimistic press holds until the server's answer).
var _shown_offers: Array = []
var _shown_pick: int = -1
## The layout form the card is placed for (-1 before the first placement).
var _form: int = -1


func setup(context: StationContext) -> void:
	ctx = context
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	add_child(col)
	_text = Label.new()
	col.add_child(_text)
	_pick_box = VBoxContainer.new()
	_pick_box.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	col.add_child(_pick_box)
	_heading = Label.new()
	_pick_box.add_child(_heading)
	_offers = GridContainer.new()
	_offers.name = "Offers"
	_offers.add_theme_constant_override("h_separation", UiTheme.TOUCH_GAP)
	_offers.add_theme_constant_override("v_separation", UiTheme.TOUCH_GAP)
	_pick_box.add_child(_offers)
	_ready = Button.new()
	_ready.name = "Ready"
	_ready.toggle_mode = true
	_ready.focus_mode = Control.FOCUS_NONE
	_ready.custom_minimum_size = Vector2(0.0, UiTheme.TOUCH_PRIMARY)
	_ready.toggled.connect(_on_toggled)
	col.add_child(_ready)
	visible = false


func _process(_delta: float) -> void:
	refresh()


## Shows the gap's time left and Ready count to a voter, and the site choice to a picker, or
## hides.
func refresh() -> void:
	var gap: Dictionary = ctx.crew.gap
	visible = not gap.is_empty() and ctx.crew.votes_on_gap()
	if not visible:
		return
	var form: LayoutMode.Form = LayoutMode.form_of(self)
	_place(form)
	if LayoutMode.is_phone(form):
		position.y = VotePrompt.phone_top(self)
	var left: int = maxi(0, ceili((int(gap["ends_at"]) - ctx.snap.tick) / CrewState.TICK_RATE))
	_text.text = (
		tr("gap.text")
		. format(
			{
				"time": "%d:%02d" % [floori(left / 60.0), left % 60],
				"ready": Array(gap.get("ready", [])).size(),
				"crew": Array(gap.get("voters", [])).size(),
			}
		)
	)
	_ready.set_pressed_no_signal(ctx.crew.gap_ready())
	_ready.text = tr("gap.ready")
	_show_offers(Array(gap.get("offers", [])), int(gap.get("pick", 0)), form)


## The site choice (w-bzx): only for a picker with 2+ offers (avoid bad paths).
func _show_offers(offers: Array, pick: int, form: LayoutMode.Form) -> void:
	_pick_box.visible = offers.size() >= 2 and ctx.crew.picks_site()
	if not _pick_box.visible:
		return
	_heading.text = tr("gap.pick")
	if offers != _shown_offers:
		_shown_offers = offers
		_shown_pick = -1
		for b: Node in _offers.get_children():
			_offers.remove_child(b)
			b.queue_free()
		for i: int in offers.size():
			var b: Button = UiTheme.action_button("Offer%d" % i, "")
			b.toggle_mode = true
			b.button_group = _group
			b.focus_mode = Control.FOCUS_NONE
			b.toggled.connect(func(on: bool) -> void: _on_offer(i, on))
			_offers.add_child(b)
	var row: bool = form == LayoutMode.Form.DESKTOP or form == LayoutMode.Form.PHONE_LANDSCAPE
	_offers.columns = offers.size() if row else 1
	for i: int in offers.size():
		var o: Dictionary = offers[i]
		var b: Button = _offers.get_child(i)
		b.text = (
			"%s\n%s · %s"
			% [
				tr(str(o.get("name_key", ""))),
				tr("gap.risk.%d" % int(o.get("risk", 0))),
				tr("gap.pay.%d" % int(o.get("reward", 0))),
			]
		)
		if pick != _shown_pick:
			b.set_pressed_no_signal(i == pick)
	_shown_pick = pick


func _place(form: LayoutMode.Form) -> void:
	if form == _form:
		return
	_form = form
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_END
	position.y = VotePrompt.phone_top(self) if LayoutMode.is_phone(form) else VotePrompt.EDGE_GAP


func _on_toggled(on: bool) -> void:
	ctx.intents.skip_gap(on)


func _on_offer(i: int, on: bool) -> void:
	if on:
		ctx.intents.pick_site(i)
