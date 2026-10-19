extends Node
## Entry point: `-- --server` runs the headless server; the client comes in #7.


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--server"):
		get_tree().quit(ServerMain.new().run(args))
	else:
		get_tree().quit(0)
