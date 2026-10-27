extends SceneTree
## L0 script check (FT-TST-001): loads every script named in a list file (one res://
## path per line) in one Godot process and fails if any does not compile, like
## `godot --check-only --script <path>` per script but without a process per file.
##   godot --headless --path . -s res://tools/check_scripts.gd -- <list file>


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("check_scripts: usage: -- <list file>")
		quit(2)
		return
	var failed: PackedStringArray = []
	var paths: PackedStringArray = FileAccess.get_file_as_string(args[0]).split("\n", false)
	for path: String in paths:
		var script: Script = load(path) as Script
		if script == null or not script.can_instantiate():
			failed.append(path)
	for path: String in failed:
		printerr("check_scripts: failed: %s" % path)
	print("check_scripts: %d script(s), %d failed" % [paths.size(), failed.size()])
	quit(1 if failed.size() > 0 else 0)
