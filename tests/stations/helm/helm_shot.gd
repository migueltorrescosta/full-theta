## The station shot (tests/visual/station_shot.gd) with Helm's phone layout set up (#28):
## `helm_tab` opens a tab of the landscape right rail (HelmTouch.TAB_SHIELD), `radar_open`
## opens the radar drawer and `stick_slides` turns the portrait stick to Slide.
extends "res://tests/visual/station_shot.gd"

var helm_tab: int = 0
var radar_open: bool = false
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
		if t.tabs != null:
			t.tabs.current = helm_tab
		if radar_open:
			t.drawer.open()
		if stick_slides:
			t.set_stick_slides(true)
