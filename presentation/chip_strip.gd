class_name ChipStrip
extends VBoxContainer
## The request chips of the station screen (§7.4, FT-PAIR-013): the ones other stations
## sent to this screen's stations, with their time left and how to answer them, and the ones
## this screen sent, waiting. An unanswered chip simply disappears when its time is up.

var _shown: Array = []
var _lapse: ChipLapse = ChipLapse.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 2)


## An incoming chip as "Helm: Boost": the asking station and the chip.
static func asker(c: Dictionary) -> String:
	return (
		"%s: %s" % [TranslationServer.translate("station." + str(c["from"])), ChipsReader.label(c)]
	)


## Shows the chips (ChipsReader rows) at the view's tick; does nothing when nothing shown
## changed (seconds count down once a second). An incoming chip is followed by what accepting
## does, a chip that lapsed unanswered stays a few seconds as a note, and `notes` (data a
## partner shared, still live) come last (C5). `now_ms` is the lapsed notes' clock.
func show_chips(
	incoming: Array[Dictionary],
	outgoing: Array[Dictionary],
	snap: SnapshotState,
	notes: Array[String] = [],
	now_ms: int = -1
) -> void:
	var lines: Array[String] = []
	var dim: Array[bool] = []
	var open: Array = []
	for c: Dictionary in incoming:
		open.append({"id": c["id"], "text": asker(c), "left": ChipsReader.left_s(snap, c)})
		lines.append(
			(
				tr("chip.ask") % [tr("station." + str(c["from"])), ChipsReader.label(c)]
				+ " · %d s" % ceili(ChipsReader.left_s(snap, c))
			)
		)
		dim.append(false)
		var effect: String = ChipLapse.effect(str(c["chip"]))
		if effect != "":
			lines.append(effect)
			dim.append(true)
	if not incoming.is_empty():
		lines.append(tr("chip.hint"))
		dim.append(false)
	for c: Dictionary in outgoing:
		lines.append(
			(
				tr("chip.sent") % [tr("station." + str(c["to"])), ChipsReader.label(c)]
				+ " · %d s" % ceili(ChipsReader.left_s(snap, c))
			)
		)
		dim.append(true)
	var now: int = Time.get_ticks_msec() if now_ms < 0 else now_ms
	for n: String in _lapse.update(open, now) + notes:
		lines.append(n)
		dim.append(true)
	if lines == _shown:
		return
	_shown = lines
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	for i: int in lines.size():
		var l: Label = Label.new()
		l.text = lines[i]
		l.add_theme_color_override("font_color", Palette.color("text_dim" if dim[i] else "text"))
		add_child(l)
	visible = not lines.is_empty()
