class_name PlaceholderPanel
extends StationPanel
## A station without its own UI yet (Science and Comms in M1, FT-M1-005, and the default
## for any station StationRegistry doesn't list): its name and a read-out of its
## StationDef (snapshot sections, block fields, claimable items and ship-wide controls),
## so it is pickable and covered in the lobby and its data visibly arrives.

var _title: Label
var _body: Label


func _setup() -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", Palette.color("text"))
	box.add_child(_title)
	_body = Label.new()
	_body.add_theme_color_override("font_color", Palette.color("text_dim"))
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_body)
	_refresh()


func _mode_changed() -> void:
	if _body != null:
		_body.visible = not docked


func _refresh() -> void:
	_title.text = tr("station." + station)
	var def: Dictionary = ctx.crew.def_of(station)
	var lines: PackedStringArray = [tr("placeholder.coming")]
	var names: PackedStringArray = []
	for kind: int in def.get("sections", []):
		names.append(_section_name(kind))
	lines.append("%s: %s" % [tr("placeholder.sections"), ", ".join(names)])
	var fields: Dictionary = def.get("fields", {})
	for kind: int in fields:
		lines.append("  %s: %s" % [_section_name(kind), ", ".join(PackedStringArray(fields[kind]))])
	lines.append("%s: %s" % [tr("placeholder.claims"), _list(def.get("claims", []))])
	lines.append("%s: %s" % [tr("placeholder.controls"), _list(def.get("controls", []))])
	_body.text = "\n".join(lines)


static func _section_name(kind: int) -> String:
	var key: Variant = StationViews.Section.find_key(kind)
	return str(key).to_lower() if key != null else str(kind)


static func _list(items: Array) -> String:
	return "-" if items.is_empty() else ", ".join(PackedStringArray(items))
