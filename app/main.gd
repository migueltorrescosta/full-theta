extends Node
## Entry point: `-- --server --bind ADDR` runs the headless dedicated server (ServerMain,
## NetServer); the client comes in #7.


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
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
	print(
		(
			"server: listening on %s:%d, protocol %d"
			% [cli.bind_address, server.port(), NetProtocol.PROTOCOL_VERSION]
		)
	)
