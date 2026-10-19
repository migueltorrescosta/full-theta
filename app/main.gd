extends Node
## Entry point: `-- --server --bind ADDR` runs the headless server (ServerMain,
## NetServer, ServerLifecycle), dedicated or as the Host button's child; the client
## comes in #7 (HostSession is its Host and orphan-rejoin path).


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	# Release checks (FT-TST-019): the build line, and `--tts-smoke` (ReleaseSmoke).
	print(ReleaseBundle.build_line())
	if ReleaseSmoke.handles(args):
		get_tree().quit(ReleaseSmoke.run(args))
		return
	if not args.has("--server"):
		get_tree().quit(0)
		return
	var cli: ServerMain = ServerMain.new()
	if not cli.parse_args(args):
		get_tree().quit(2)
		return
	ServerMain.configure_engine()
	var server: NetServer = cli.make_server()
	if server == null:
		get_tree().quit(1)
		return
	add_child(server)
	add_child(cli.make_voice(server))
	add_child(cli.make_lifecycle(server))
	print(
		(
			"server: listening on %s:%d, protocol %d"
			% [cli.bind_address, server.port(), NetProtocol.PROTOCOL_VERSION]
		)
	)
