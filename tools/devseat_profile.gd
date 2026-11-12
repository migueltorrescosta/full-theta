extends SceneTree
## Manual profile of the dev seat's screen build (#30): times each station panel's load
## and setup, then the whole all-stations StationScreen (setup, entering the tree, first
## frames). Wall-clock, so not a gate test; run it pinned, on a quiet host, and record
## the load average with the result:
##
## taskset -c 0,1 godot --headless --path . -s res://tools/devseat_profile.gd
##
## DEVSEAT_ENTRY=helm times a single-station screen instead.

const FIXTURE: String = "res://tests/stations/station_fixture.gd"


func _initialize() -> void:
	var fixture: GDScript = load(FIXTURE)
	var seat: String = OS.get_environment("DEVSEAT_ENTRY")
	if seat.is_empty():
		seat = "all"
	var ctx: StationContext = fixture.context(seat)
	var times: Dictionary = {}
	var screen: StationScreen = StationScreen.new()
	screen.panel_factory = func(st: String) -> StationPanel:
		var t0: int = Time.get_ticks_usec()
		var p: StationPanel = StationRegistry.make(st)
		times[st + " make"] = Time.get_ticks_usec() - t0
		return p
	var t0: int = Time.get_ticks_usec()
	screen.setup(ctx)
	var setup_us: int = Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	root.add_child(screen)
	var enter_us: int = Time.get_ticks_usec() - t0
	var frames: Array[int] = []
	for i: int in 3:
		t0 = Time.get_ticks_usec()
		await process_frame
		frames.append(Time.get_ticks_usec() - t0)
	for k: String in times:
		print("%-20s %8.1f ms" % [k, times[k] / 1000.0])
	print("screen.setup         %8.1f ms (includes the makes above)" % [setup_us / 1000.0])
	print("add_child            %8.1f ms" % [enter_us / 1000.0])
	for i: int in frames.size():
		print("frame %d              %8.1f ms" % [i + 1, frames[i] / 1000.0])
	print("total                %8.1f ms" % [(setup_us + enter_us + frames[0]) / 1000.0])
	await _controls_pane()
	quit()


## The settings menu's Controls tab for the dev seat's six stations, the heavy child of
## the shell path (the menu opens on the first visit): build, then the keyboard diagram.
func _controls_pane() -> void:
	var six: Array[String] = StationViews.CREW.duplicate()
	var pane: ControlsPane = ControlsPane.new()
	root.add_child(pane)
	var t0: int = Time.get_ticks_usec()
	pane.build(Bindings.new(), six, IntentTable.KBM, "all")
	var build_us: int = Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	if pane.has_method("show_view"):
		pane.call("show_view", ControlsPane.VIEW_KBM)
	await process_frame
	await process_frame
	print("ControlsPane.build   %8.1f ms" % [build_us / 1000.0])
	print("  + show kbm, 2 frames %6.1f ms" % [(Time.get_ticks_usec() - t0) / 1000.0])
