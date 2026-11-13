class_name HelpPage
extends RefCounted
## One phone page in a touch help picture (TouchHelpPicture): its tab `title` (translated)
## and the controls on it.

var title: String
var boxes: Array[HelpBox]


func _init(title_in: String, boxes_in: Array[HelpBox]) -> void:
	title = title_in
	boxes = boxes_in
