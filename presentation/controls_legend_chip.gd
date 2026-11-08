class_name ControlsLegendChip
extends Button
## The first-visit legend for the contact label grammar (D2): once per client, below the
## Controls chip, "H2 · 4 high · mid: hostile 2, 4 o'clock, high, mid range". A tap opens
## the callout card (ControlsPane.callout_card_url()). The lesson that teaches the words is
## #37 C8; this chip only decodes the label a new player sees first.

const HINT: String = "callout_legend"
const SHOW_S: float = 10.0
## The widest the chip grows (px); its text wraps beyond.
const WIDTH: float = 420.0

var left_s: float = SHOW_S


## Adds the legend to `parent` on this client's first visit to any station; null once seen.
static func show_legend(parent: Control, settings: ClientSettings) -> ControlsLegendChip:
	if settings.hint_seen(HINT):
		return null
	settings.mark_hint_seen(HINT)
	settings.save()
	var chip: ControlsLegendChip = ControlsLegendChip.new()
	parent.add_child(chip)
	return chip


func _init() -> void:
	name = "ControlsLegendChip"
	focus_mode = Control.FOCUS_NONE
	theme_type_variation = "RailButton"
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	custom_minimum_size = Vector2(WIDTH, UiTheme.TOUCH_MIN)
	text = tr("controls.legend_chip")
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	pressed.connect(
		func() -> void:
			OS.shell_open(ControlsPane.callout_card_url())
			queue_free()
	)


func _ready() -> void:
	# Below the Controls chip and its gap.
	offset_top = ControlsChip.TOP + SafeArea.margins(self).y + UiTheme.TOUCH_MIN + 8.0
	offset_bottom = offset_top + UiTheme.TOUCH_MIN


func _process(delta: float) -> void:
	left_s -= delta
	if left_s <= 0.0:
		set_process(false)
		queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		text = tr("controls.legend_chip")
