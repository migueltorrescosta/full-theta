extends Node
## Entry point: `-- --server --bind ADDR` runs the headless server (ServerMain,
## NetServer, ServerLifecycle), dedicated or as the Host button's child; without
## `--server` it starts the client's MainMenu (T049), driven by ClientAutopilot when
## its test flags are given.


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.has("--server"):
		var menu: MainMenu = MainMenu.new()
		add_child(menu)
		if ClientAutopilot.wanted(args):
			var pilot: ClientAutopilot = ClientAutopilot.new()
			if not pilot.parse_args(args):
				get_tree().quit(2)
				return
			pilot.menu = menu
			add_child(pilot)
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
