## Helm's touch help picture (HelmHelp) for the L5 harness (#28 follow-up, P28-Help): as the
## menu's Controls tab would show it on a phone.
extends Control


func _ready() -> void:
	I18n.apply("en")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back: ColorRect = ColorRect.new()
	back.color = Palette.color("panel")
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var help: HelmHelp = HelmHelp.new()
	help.position = Vector2(25.0, 12.0)
	help.size = help.custom_minimum_size
	add_child(help)
