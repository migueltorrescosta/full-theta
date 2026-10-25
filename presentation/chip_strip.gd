class_name ChipStrip
extends VBoxContainer
## The request chips of the station screen (§7.4, FT-PAIR-013): the ones other stations
## sent to this screen's stations, with their time left and how to answer them, and the ones
## this screen sent, waiting. An unanswered chip simply disappears when its time is up.

var _shown: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 2)


## Shows the chips (ChipView rows) at the view's tick; does nothing when nothing shown
## changed (seconds count down once a second).
func show_chips(
	incoming: Array[Dictionary], outgoing: Array[Dictionary], view: NetViewState
) -> void:
	var lines: Array[String] = []
	for c: Dictionary in incoming:
		lines.append(
			(
				tr("chip.ask") % [tr("station." + str(c["from"])), ChipView.label(c)]
				+ " · %d s" % ceili(ChipView.left_s(view, c))
			)
		)
	if not incoming.is_empty():
		lines.append(tr("chip.hint"))
	for c: Dictionary in outgoing:
		lines.append(
			(
				tr("chip.sent") % [tr("station." + str(c["to"])), ChipView.label(c)]
				+ " · %d s" % ceili(ChipView.left_s(view, c))
			)
		)
	if lines == _shown:
		return
	_shown = lines
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	for i: int in lines.size():
		var l: Label = Label.new()
		l.text = lines[i]
		var dim: bool = i >= incoming.size() + (1 if not incoming.is_empty() else 0)
		l.add_theme_color_override("font_color", Palette.color("text_dim" if dim else "text"))
		add_child(l)
	visible = not lines.is_empty()
