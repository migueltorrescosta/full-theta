extends Node
## Entry point: `-- --server --bind ADDR` runs the headless server (ServerMain,
## NetServer, ServerLifecycle), dedicated or as the Host button's child; without
## `--server` it starts the client's MainMenu (T049), driven by ClientAutopilot when
## its test flags are given.


## The server's script, loaded only by `--server`: naming ServerMain, NetServer or
## ServerLifecycle here would compile the whole server stack in every browser client, which
## never runs one (about 7 % of the start-up compile, #11 DC2).
const SERVER_MAIN: String = "res://app/server_main.gd"


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	# Release checks (FT-TST-019): the build line, and `--tts-smoke` (ReleaseSmoke).
	print(ReleaseBundle.build_line())
	if ReleaseSmoke.handles(args):
		get_tree().quit(ReleaseSmoke.run(args))
		return
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
	var server_main: GDScript = load(SERVER_MAIN)
	var cli: Variant = server_main.new()
	if not cli.parse_args(args):
		get_tree().quit(2)
		return
	server_main.call("configure_engine")
	var server: Node = cli.make_server()
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
