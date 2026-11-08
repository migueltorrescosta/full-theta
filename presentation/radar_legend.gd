class_name RadarLegend
extends Button
## The first-visit radar legend (R26-6, C11): once per client, a chip under the controls
## chip says what the three icons nobody names mean: Drift (the green reticle, where the ship
## is heading), the Zone box (the site) and a mark (a diamond). It goes after SHOW_S seconds
## or on a tap. Like ControlsChip it keys off ClientSettings.hint_seen, so "Show first-visit
## hints again" brings it back; the key is not a station's, so every station shares it.
##
##     RadarLegend.show_once(self, ctx.settings)   # each frame is fine: a lookup once seen

const KEY: String = "radar_legend"
const SHOW_S: float = 12.0
## Below the controls chip (ControlsChip.TOP and its height).
const TOP: float = ControlsChip.TOP + UiTheme.TOUCH_MIN + 8.0
const MAX_W: float = 420.0

var left_s: float = SHOW_S


## Adds the legend to `parent` the first time the parent shows on this client; null when
## it was seen already, or the parent is not on screen.
static func show_once(parent: Control, settings: ClientSettings) -> RadarLegend:
	if settings.hint_seen(KEY) or not parent.is_visible_in_tree():
		return null
	settings.mark_hint_seen(KEY)
	settings.save()
	var legend: RadarLegend = RadarLegend.new()
	parent.add_child(legend)
	return legend


func _init() -> void:
	name = "RadarLegend"
	ControlsChip.join_stack(self, 3)
	focus_mode = Control.FOCUS_NONE
	theme_type_variation = "RailButton"
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	custom_minimum_size = Vector2(MAX_W, UiTheme.TOUCH_MIN * 1.5)
	text = tr("radar.legend")
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	pressed.connect(queue_free)


func _ready() -> void:
	# Narrower than the parent on a phone, never wider than MAX_W.
	var parent: Control = get_parent() as Control
	if parent != null:
		custom_minimum_size.x = minf(MAX_W, parent.size.x - 16.0)
	_stack()


## At TOP, or under the first-visit chips above it wherever they went (ControlsChip.STACK).
func _stack() -> void:
	ControlsChip.place_in_stack(self, TOP + SafeArea.margins(self).y)


func _process(delta: float) -> void:
	_stack()
	left_s -= delta
	if left_s <= 0.0:
		set_process(false)
		queue_free()
