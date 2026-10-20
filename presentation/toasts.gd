class_name Toasts
extends VBoxContainer
## Toasts top-right (§5.0): short lines that expire after SHOW_MS, newest at the top, at
## most MAX shown (the oldest goes first).

const SHOW_MS: int = 4000
const MAX: int = 4


func _init() -> void:
	alignment = ALIGNMENT_BEGIN
	mouse_filter = MOUSE_FILTER_IGNORE


## kind: "info", "warn" or "danger" (palette roles; info is the accent).
func push(text: String, kind: String, now_ms: int) -> void:
	var label: Label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_color_override(
		"font_color", Palette.color("accent" if kind == "info" else kind)
	)
	label.add_theme_color_override("font_outline_color", Palette.color("background"))
	label.add_theme_constant_override("outline_size", 4)
	label.set_meta(&"until", now_ms + SHOW_MS)
	add_child(label)
	move_child(label, 0)
	while get_child_count() > MAX:
		var old: Node = get_child(get_child_count() - 1)
		remove_child(old)
		old.queue_free()


func update(now_ms: int) -> void:
	for label: Node in get_children():
		if now_ms >= int(label.get_meta(&"until", 0)):
			remove_child(label)
			label.queue_free()


## The texts shown, newest first (tests).
func texts() -> Array[String]:
	var out: Array[String] = []
	for label: Node in get_children():
		out.append((label as Label).text)
	return out
