class_name ControlsHint
extends Button
## The first-visit hints (P28-Help, D2, C11; amend FT-STN-012 and D185): a hint at the top of
## the view, once per client and hint key, for a few seconds, then it goes; a tap closes it.
## The menu's "Show first-visit hints again" (ClientSettings.reset_hints) brings them back.
## The radar legend (show_radar_legend, C11) uses it: what Drift, the Zone box and a mark are,
## the first time a radar station shows, 12 s. The station's first-seat card (FirstSeatCard,
## C7) replaced the Controls hint and the callout legend; it and the "turn sideways" banner
## share this stack, top down.
##
##     ControlsHint.show_radar_legend(self, ctx.settings)

const RADAR_KEY: String = "radar_legend"
const RADAR_TIME: float = 12.0
## The legend's widest (px), and narrower than the view on a phone; its text wraps.
const WIDE: float = 420.0
## Below the top bar.
const TOP: float = 64.0
## The first-visit hints and the "turn sideways" banner: each hint sits under the members of a
## lower rank that show, never over them (w5).
const STACK: StringName = &"first_visit_stack"
const RANK: StringName = &"stack_rank"

## Seconds left on screen.
var time_left: float = RADAR_TIME


## Adds the radar legend (R26-6, C11) the first time `parent` shows on this client; null when
## it was seen already, the parent is not on screen or a first-seat card is open. Each frame
## is fine: a lookup once seen.
static func show_radar_legend(parent: Control, settings: ClientSettings) -> ControlsHint:
	if not parent.is_visible_in_tree() or _card_open(parent) or settings.hint_seen(RADAR_KEY):
		return null
	settings.mark_hint_seen(RADAR_KEY)
	settings.save()
	var hint: ControlsHint = ControlsHint.new()
	parent.add_child(hint)
	return hint


## Whether a first-seat card (FirstSeatCard) is open: the radar legend waits until it is
## closed, so the two never open together.
static func _card_open(node: Node) -> bool:
	for n: Node in node.get_tree().get_nodes_in_group(STACK):
		if n is FirstSeatCard and not n.is_queued_for_deletion():
			return true
	return false


func _init() -> void:
	name = "RadarLegend"
	join_stack(self, 3)
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(WIDE, UiTheme.TOUCH_MIN * 1.5)
	theme_type_variation = "RailButton"
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text = tr("radar.legend")
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	pressed.connect(queue_free)


func _ready() -> void:
	# A legend is narrower than its parent on a phone, never wider than WIDE.
	var parent: Control = get_parent() as Control
	if parent != null:
		custom_minimum_size.x = minf(WIDE, parent.size.x - 16.0)
	_place()


func _process(delta: float) -> void:
	_place()
	time_left -= delta
	if time_left <= 0.0:
		set_process(false)
		queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		text = tr("radar.legend")


## Under the top bar, under the shown members of the stack of a lower rank (STACK).
func _place() -> void:
	place_in_stack(self, TOP + SafeArea.margins(self).y)


## Puts `c` in the first-visit stack at `rank` (the banner 0, then the hints top down).
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
