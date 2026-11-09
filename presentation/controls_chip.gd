class_name ControlsChip
extends Button
## The first-visit chips (P28-Help, D2, C11; amend FT-STN-012 and D185): a chip at the top of
## the view, once per client and hint key, for a few seconds, then it goes; a tap acts and
## closes it. The menu's "Show first-visit hints again" (ClientSettings.reset_hints) brings
## them back. Three use it, stacked top down under the "turn sideways" banner:
## - the Controls chip (show_once): "Controls: ☰ › Controls" on a station's first visit, 6 s;
##   help never opens by itself any more, a tap opens it;
## - the callout legend (show_legend, D369): a sample callout decoded, on the first visit to
##   any station, 10 s; a tap opens the callout card;
## - the radar legend (show_radar_legend, C11): what Drift, the Zone box and a mark are, the
##   first time a radar station shows, 12 s.
##
##     var chip: ControlsChip = ControlsChip.show_once(self, ctx.settings, station)
##     if chip != null:
##         chip.pressed.connect(func() -> void: help_requested.emit())

const SHOW_S: float = 6.0
const LEGEND_KEY: String = "callout_legend"
const LEGEND_S: float = 10.0
const RADAR_KEY: String = "radar_legend"
const RADAR_S: float = 12.0
## The legends' widest (px), and narrower than the view on a phone; their text wraps.
const WIDE: float = 420.0
## Below the top bar.
const TOP: float = 64.0
## The first-visit chips and the "turn sideways" banner: each chip sits under the members of a
## lower rank that show, never over them (w5).
const STACK: StringName = &"first_visit_stack"
const RANK: StringName = &"stack_rank"

## Seconds left on screen.
var left_s: float = SHOW_S
## The binding that opens the page on this device ("?", "View"), or "" for the ☰ route.
var key_text: String = ""
## The strings key of a legend's words; "" for the Controls chip's own.
var text_key: String = ""


## Adds the Controls chip to `parent` on `station`'s first visit and records the visit; null
## when the visit was seen (or the browser test hooks skip it).
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
	if station == "":
		return null
	var key: String = ""
	if device != "" and not touch:
		key = BindingText.describe_all(settings.bindings.bindings("overlay", device))
	return _first(parent, settings, station, 1, SHOW_S, "", key)


## Adds the callout legend (D2, D369) to `parent` on this client's first visit to any station;
## null once seen.
static func show_legend(parent: Control, settings: ClientSettings) -> ControlsChip:
	return _first(parent, settings, LEGEND_KEY, 2, LEGEND_S, "controls.legend_chip")


## Adds the radar legend (R26-6, C11) the first time `parent` shows on this client; null when
## it was seen already, or the parent is not on screen. Each frame is fine: a lookup once seen.
static func show_radar_legend(parent: Control, settings: ClientSettings) -> ControlsChip:
	if not parent.is_visible_in_tree():
		return null
	var chip: ControlsChip = _first(parent, settings, RADAR_KEY, 3, RADAR_S, "radar.legend")
	if chip != null:
		chip.custom_minimum_size.y = UiTheme.TOUCH_MIN * 1.5
	return chip


## The chip of hint `key` at stack `rank`, `seconds` on screen, added to `parent` and the hint
## recorded as seen; null when it was seen. A legend has its `text_key`.
static func _first(
	parent: Control,
	settings: ClientSettings,
	key: String,
	rank: int,
	seconds: float,
	words: String,
	binding: String = ""
) -> ControlsChip:
	if settings.hint_seen(key):
		return null
	settings.mark_hint_seen(key)
	settings.save()
	var chip: ControlsChip = ControlsChip.new()
	join_stack(chip, rank)
	chip.left_s = seconds
	chip.key_text = binding
	chip.text_key = words
	if words != "":
		chip.name = "RadarLegend" if key == RADAR_KEY else "ControlsLegendChip"
		chip.theme_type_variation = "RailButton"
		chip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		chip.custom_minimum_size.x = WIDE
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
	# A legend is narrower than its parent on a phone, never wider than WIDE.
	var parent: Control = get_parent() as Control
	if text_key != "" and parent != null:
		custom_minimum_size.x = minf(WIDE, parent.size.x - 16.0)
	_place()


func _process(delta: float) -> void:
	_place()
	left_s -= delta
	if left_s <= 0.0:
		set_process(false)
		queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		text = _label()


## Under the top bar: the Controls chip at TOP, the legends a chip's height lower; under the
## shown chips of a lower rank wherever they went (STACK).
func _place() -> void:
	var top: float = TOP + SafeArea.margins(self).y
	if int(get_meta(RANK, 1)) > 1:
		top += UiTheme.TOUCH_MIN + 8.0
	place_in_stack(self, top)


## The chip's words.
func _label() -> String:
	if text_key != "":
		return tr(text_key)
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
