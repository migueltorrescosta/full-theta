class_name ControlsChip
extends Button
## The first-visit hint (P28-Help, amends FT-STN-012 and D185): on a station's first visit
## to this client, a chip "Controls: ☰ › Controls" shows at the top of the view for
## SHOW_S seconds, then goes. Help never opens by itself any more; tapping the chip opens
## it (`pressed`). Once per client and station, re-enabled by the menu's "Show
## first-visit hints again" (ClientSettings.reset_hints).
##
##     var chip: ControlsChip = ControlsChip.show_once(self, ctx.settings, station)
##     if chip != null:
##         chip.pressed.connect(func() -> void: help_requested.emit())

const SHOW_S: float = 6.0
## Below the top bar.
const TOP: float = 64.0
## The first-visit chips (this chip, ControlsLegendChip, RadarLegend) and the "turn sideways"
## banner: each chip sits under the members of a lower rank that show, never over them (w5).
const STACK: StringName = &"first_visit_stack"
const RANK: StringName = &"stack_rank"

## Seconds left on screen.
var left_s: float = SHOW_S
## The binding that opens the page on this device ("?", "View"), or "" for the ☰ route.
var key_text: String = ""


## Adds the chip to `parent` on `station`'s first visit and records the visit; null when
## the visit was seen (or the browser test hooks skip it).
##
## `device` (IntentTable.KBM or PAD) names the overlay intent's binding in the chip; "" or a
## `touch` layout says the ☰ route.
static func show_once(
	parent: Control,
	settings: ClientSettings,
	station: String,
	device: String = "",
	touch: bool = false
) -> ControlsChip:
	if station == "" or settings.hint_seen(station):
		return null
	settings.mark_hint_seen(station)
	settings.save()
	var chip: ControlsChip = ControlsChip.new()
	if device != "" and not touch:
		chip.key_text = BindingText.describe_all(settings.bindings.bindings("overlay", device))
		chip.text = chip._label()
	parent.add_child(chip)
	return chip


func _init() -> void:
	name = "ControlsChip"
	join_stack(self, 1)
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(0.0, UiTheme.TOUCH_MIN)
	theme_type_variation = "RailAccentButton"
	text = _label()
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	pressed.connect(queue_free)


func _ready() -> void:
	place_in_stack(self, TOP + SafeArea.margins(self).y)


func _process(delta: float) -> void:
	place_in_stack(self, TOP + SafeArea.margins(self).y)
	left_s -= delta
	if left_s <= 0.0:
		set_process(false)
		queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		text = _label()


## The chip's words.
func _label() -> String:
	if key_text != "":
		return tr("controls.chip_key") % key_text
	return tr("controls.chip")


## Puts `c` in the first-visit stack at `rank` (the banner 0, then the chips top down).
static func join_stack(c: Control, rank: int) -> void:
	c.set_meta(RANK, rank)
	c.add_to_group(STACK)


## Sets `c`'s top offset to `top` (its parent's coordinates), or lower: under every shown
## member of the stack of a lower rank.
static func place_in_stack(c: Control, top: float) -> void:
	var parent: Control = c.get_parent() as Control
	if parent != null and c.is_inside_tree():
		var origin: float = parent.get_global_rect().position.y
		var rank: int = int(c.get_meta(RANK, 0))
		for n: Node in c.get_tree().get_nodes_in_group(STACK):
			var o: Control = n as Control
			if (
				o == c
				or int(o.get_meta(RANK, 0)) >= rank
				or not o.is_visible_in_tree()
				or o.is_queued_for_deletion()
			):
				continue
			top = maxf(top, o.get_global_rect().end.y + 8.0 - origin)
	if c.offset_top != top:
		var h: float = maxf(c.offset_bottom - c.offset_top, c.get_combined_minimum_size().y)
		c.offset_top = top
		c.offset_bottom = top + h
