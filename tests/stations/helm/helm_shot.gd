## The station shot (tests/visual/station_shot.gd) with Helm's phone layout set up (#28):
## `page` shows a page of the phone layout (HelmTouch.PAGE_*) and `stick_slides` turns the
## portrait stick to Slide.
extends "res://tests/visual/station_shot.gd"

var page: int = 0
var stick_slides: bool = false


func _ready() -> void:
	super()
	_set_helm.call_deferred()


func _set_helm() -> void:
	await get_tree().process_frame
	for n: Node in find_children("*", "HelmPanel", true, false):
		var t: HelmTouch = (n as HelmPanel).touch_ui
		if t == null:
			continue
		t.pages.current = page
		if stick_slides:
			t.set_stick_slides(true)
