class_name HelpBox
extends RefCounted
## One control in a touch help picture (TouchHelpPicture): its outline `box` in the phone
## frame's 844x390 coordinates, its name (`label`) and what it does (`what`; equal to `label`
## when the station says no more, "All stop"). Both are translated text.

var box: Rect2
var label: String
var what: String


func _init(box_in: Rect2, label_in: String, what_in: String) -> void:
	box = box_in
	label = label_in
	what = what_in


## A box from "Name: what it does" (or a bare name).
static func named(box_in: Rect2, text: String) -> HelpBox:
	var parts: PackedStringArray = text.split(": ", true, 1)
	return HelpBox.new(box_in, parts[0], parts[1] if parts.size() > 1 else parts[0])
