class_name GapBanner
extends PanelContainer
## Skip the quiet gap (gp-07, D3): during the director's gap between two encounters, a small
## card says how long the quiet lasts and how many of the fleet's crew are Ready, with
## one toggle, "Ready for the next one". It shows only to a session that votes (a human crew
## player or the Captain on a ship of the fleet in play: CrewState.votes_on_gap), so a viewer
## never sees a control it can't use. Once every voter is Ready the server ends the gap; the
## card goes when the gap does. It sits at the screen's bottom-left corner (the Shakedown
## banner's: the two never show together); on a phone, where that corner holds the Helm
## throttle and other controls, at the bottom centre of the view, over readouts only.

var ctx: StationContext

var _text: Label
var _ready: Button
## Whether the card is placed for a phone (-1 before the first placement).
var _phone: int = -1


func setup(context: StationContext) -> void:
	ctx = context
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col: VBoxContainer = VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	add_child(col)
	_text = Label.new()
	col.add_child(_text)
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


## Shows the gap's time left and Ready count to a voter, or hides.
func refresh() -> void:
	var gap: Dictionary = ctx.crew.gap
	visible = not gap.is_empty() and ctx.crew.votes_on_gap()
	if not visible:
		return
	_place(1 if LayoutMode.is_phone(LayoutMode.form_of(self)) else 0)
	var left: int = maxi(0, ceili((int(gap["ends_at"]) - ctx.snap.tick) / CrewState.TICK_HZ))
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


func _place(phone: int) -> void:
	if phone == _phone:
		return
	_phone = phone
	var corner: Control.LayoutPreset = (
		Control.PRESET_CENTER_BOTTOM if phone == 1 else Control.PRESET_BOTTOM_LEFT
	)
	set_anchors_and_offsets_preset(corner, Control.PRESET_MODE_MINSIZE, 12 + 24 * phone)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	grow_horizontal = Control.GROW_DIRECTION_BOTH if phone == 1 else Control.GROW_DIRECTION_END


func _on_toggled(on: bool) -> void:
	ctx.intents.skip_gap(on)
