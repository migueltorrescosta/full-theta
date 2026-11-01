class_name ControlsChip
extends Button
## The first-visit hint (P28-Help, amends FT-STN-012 and D185): on a station's first visit
## to this client, a chip "Controls: ☰ › Controls" shows at the top of the view for
## SHOW_S seconds, then goes. Help never opens by itself any more; tapping the chip opens
## it (`pressed`). Once per client and station, re-enabled by the menu's "Show first-run
## tips again" (ClientSettings.reset_tooltips).
##
##     var chip: ControlsChip = ControlsChip.show_once(self, ctx.settings, station)
##     if chip != null:
##         chip.pressed.connect(func() -> void: help_requested.emit())

const SHOW_S: float = 6.0
## Below the top bar.
const TOP: float = 64.0

## Seconds left on screen.
var left_s: float = SHOW_S


## Adds the chip to `parent` on `station`'s first visit and records the visit; null when
## the visit was seen (or the browser test hooks skip it).
static func show_once(parent: Control, settings: ClientSettings, station: String) -> ControlsChip:
	if station == "" or settings.tooltip_seen(station):
		return null
	settings.mark_tooltip_seen(station)
	settings.save()
	var chip: ControlsChip = ControlsChip.new()
	parent.add_child(chip)
	return chip


func _init() -> void:
	name = "ControlsChip"
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(0.0, UiTheme.TOUCH_MIN)
	theme_type_variation = "RailAccentButton"
	text = tr("controls.chip")
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	pressed.connect(queue_free)


func _ready() -> void:
	offset_top = TOP + SafeArea.margins(self).y
	offset_bottom = offset_top + UiTheme.TOUCH_MIN


func _process(delta: float) -> void:
	left_s -= delta
	if left_s <= 0.0:
		set_process(false)
		queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		text = tr("controls.chip")
