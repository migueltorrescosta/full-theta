## L5 screenshot capture (FT-TST-003), run by tools/l5.py under Xvfb with llvmpipe:
##   godot --path . --rendering-driver opengl3 --resolution WxH -s res://tools/l5_capture.gd \
##     -- --shots <shots.json> --out <dir>
## Renders each shot's scene in the root window at the shot's "size" (else the manifest's),
## waits a few frames, saves <name>.png
## and writes env.json (renderer, GL version, engine) and timings.json to <dir>.
extends SceneTree

const WARMUP_FRAMES := 5


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var shots_path: String = _arg(args, "--shots")
	var out_dir: String = _arg(args, "--out")
	if shots_path.is_empty() or out_dir.is_empty():
		_fail("usage: -- --shots <shots.json> --out <dir>")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(shots_path))
	if not parsed is Dictionary:
		_fail("cannot read %s" % shots_path)
		return
	var manifest: Dictionary = parsed
	var shots: Array = manifest.get("shots", [])
	var timings: Dictionary = {}
	for item: Variant in shots:
		var shot: Dictionary = item
		var name: String = shot["name"]
		var start: int = Time.get_ticks_msec()
		var size: Array = shot.get("size", manifest.get("size", []))
		var image: Image = await _capture(shot, size)
		if image == null:
			_fail("cannot load scene for shot %s" % name)
			return
		if image.save_png(out_dir.path_join(name + ".png")) != OK:
			_fail("cannot write %s.png" % name)
			return
		timings[name] = (Time.get_ticks_msec() - start) / 1000.0
	var env: Dictionary = {
		"renderer": RenderingServer.get_video_adapter_name(),
		"gl_version": RenderingServer.get_video_adapter_api_version(),
		"godot": Engine.get_version_info()["string"],
	}
	_write_json(out_dir.path_join("env.json"), env)
	_write_json(out_dir.path_join("timings.json"), timings)
	quit(0)


## Instances the shot's scene, applies its "set" properties, renders and returns the frame.
func _capture(shot: Dictionary, size: Array) -> Image:
	var scene: PackedScene = load(shot["scene"])
	if scene == null:
		return null
	if size.size() == 2:
		var want: Vector2i = Vector2i(int(size[0]), int(size[1]))
		DisplayServer.window_set_size(want)
		root.size = want
	var node: Node = scene.instantiate()
	var props: Dictionary = shot.get("set", {})
	for key: Variant in props:
		node.set(key, props[key])
	root.add_child(node)
	for i: int in WARMUP_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	root.remove_child(node)
	node.free()
	await process_frame
	return image


func _arg(args: PackedStringArray, flag: String) -> String:
	var i: int = args.find(flag)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else ""


func _write_json(path: String, data: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  ", false) + "\n")


func _fail(message: String) -> void:
	printerr("l5_capture: " + message)
	quit(1)
