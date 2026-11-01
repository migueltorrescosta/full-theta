class_name RotateBanner
extends PanelContainer
## "Turn sideways for the full view" (#28, WCAG 1.3.4): a slim banner on a phone held
## upright, over the reduced portrait layout. It never blocks: the × hides it, and with
## `settings` set the dismissal is remembered on this device (ClientSettings tooltip
## KEY), else for the page's lifetime. It shows only in LayoutMode.Form.PHONE_PORTRAIT
## and follows rotations by itself.
##
##     var banner := RotateBanner.new()
##     banner.settings = ctx.settings
##     column.add_child(banner)

signal dismissed

## The ClientSettings tooltip key of a dismissal.
const KEY: String = "rotate_banner"
const TEXT_KEY: String = "touch.rotate"
const TEXT: String = "Turn sideways for the full view"

## Dismissed in this page (when there are no settings to remember it in).
static var dismissed_here: bool = false

var settings: ClientSettings = null
var label: Label = Label.new()
var close_button: RailButton = RailButton.make("×")


func _init() -> void:
	theme_type_variation = "Banner"
	visible = false
	var row: HBoxContainer = HBoxContainer.new()
	add_child(row)
	label.text = TouchText.of(TEXT_KEY, TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	close_button.pressed.connect(dismiss)
	row.add_child(close_button)


func _ready() -> void:
	get_viewport().size_changed.connect(refresh)
	refresh()


## True once the player closed it.
func is_dismissed() -> bool:
	return dismissed_here or (settings != null and settings.tooltip_seen(KEY))


## Shows the banner when the phone is upright and the player hasn't closed it.
func refresh() -> void:
	if not is_inside_tree():
		return
	visible = LayoutMode.form_of(self) == LayoutMode.Form.PHONE_PORTRAIT and not is_dismissed()


func dismiss() -> void:
	dismissed_here = true
	if settings != null:
		settings.mark_tooltip_seen(KEY)
		settings.save()
	visible = false
	dismissed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		label.text = TouchText.of(TEXT_KEY, TEXT)
