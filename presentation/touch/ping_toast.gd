class_name PingToast
extends RailButton
## The ping toast on a phone (#28 follow-up, P28-Common, design 1.3): "Bo pinged H2". A
## tap selects the pinged item (the common select_pinged); it goes after SHOW_MS.
##
##     toast.tapped.connect(func() -> void: ctx.crew.select_pinged(ctx.now_ms()))
##     toast.show_ping("Bo pinged H2", now_ms)

signal tapped

const SHOW_MS: int = 4000
const FONT: int = 13

var _until: int = 0


func _init() -> void:
	super()
	visible = false
	add_theme_font_size_override("font_size", FONT)
	add_theme_color_override("font_color", Palette.color("accent"))
	pressed.connect(_tap)


## Shows `label` until now_ms + SHOW_MS.
func show_ping(label: String, now_ms: int) -> void:
	text = label
	var font: Font = get_theme_font("font")
	var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x
	custom_minimum_size.x = maxf(UiTheme.TOUCH_PRIMARY, w + 2.0 * UiTheme.TOUCH_PAD)
	_until = now_ms + SHOW_MS
	visible = true


## Hides the toast once its time is up.
func update(now_ms: int) -> void:
	if visible and now_ms >= _until:
		visible = false


func _tap() -> void:
	visible = false
	tapped.emit()
