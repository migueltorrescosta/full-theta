class_name ServerMain
extends RefCounted
## Headless dedicated server entry (FT-NET-002): parses the command line after `--` and
## builds the NetServer node that app/main.gd adds to the tree.
##
## godot --headless --path . -- --server --bind ADDR [flags]
##   --port N             WebSocket port [47801]; the HTTP port (web stations) will be
##                        N - 1 (D108). 0 picks a free port (tests, smoke runs).
##   --bind ADDR          address to listen on, required: the chosen LAN address, not
##                        every interface (S3); 127.0.0.1 for a local host.
##   --dev-all-stations   offer the dev entry holding every station (FT-NET-029, D72).
##   --seed N             world seed [1].
##   --host-secret HEX    the host client presents it in Hello (D127); none by default.
##                        Tests only: other local users can read a command line.
##   --host-secret-env    read the host secret from the FT_HOST_SECRET environment
##                        variable instead (what HostLauncher passes; D127).
##   --grace-s S          reconnect grace (s) [10] (FT-NET-033; T045 owns the rules).
##   --idle-exit-min M    exit after M minutes without connections, wall clock
##                        (FT-NET-003); 0 never [0].
##   --pid-file PATH      write the pid file there while running (FT-NET-003).
##   --http-root DIR      serve this web export (an absolute path) over HTTP at
##                        port - 1 (FT-NET-030, D108); off without it.
##   --name NAME          server name in the LAN beacon ["Full Theta server"].
##   --discovery-port N   UDP port the beacon broadcasts to [47790] (FT-NET-012).
##   --no-beacon          don't broadcast on the LAN (tests).
##   --run-for S          quit after S seconds (smoke runs; 0 = run until killed).

const DEFAULT_PORT: int = NetProtocol.DEFAULT_WS_PORT
## Headless frame pacing (S3 "Server loop"): Godot otherwise sleeps 6.9 ms a frame in
## headless mode, capping it near 145 frames/s; 2 ms keeps the 60 Hz tick within about
## 2 ms of due without spinning. PROVISIONAL.
const SLEEP_USEC: int = 2000
const MAX_FPS: int = 250
## PROVISIONAL: the beacon's default server name.
const DEFAULT_NAME: String = "Full Theta server"

var port: int = DEFAULT_PORT
var bind_address: String = ""
var dev_all_stations: bool = false
var seed_value: int = 1
var host_secret: String = ""
var grace_s: float = 10.0
var idle_exit_min: float = 0.0
var pid_file: String = ""
var run_for: float = 0.0
var http_root: String = ""
var server_name: String = DEFAULT_NAME
var discovery_port: int = LanBeacon.DISCOVERY_PORT
var beacon: bool = true


## Parses the flags; reports the problem and returns false on a bad command line.
func parse_args(args: PackedStringArray) -> bool:
	var i: int = 0
	while i < args.size():
		var flag: String = args[i]
		if flag == "--server":
			pass
		elif flag == "--dev-all-stations":
			dev_all_stations = true
		elif flag == "--no-beacon":
			beacon = false
		elif flag == "--host-secret-env":
			host_secret = OS.get_environment(HostLauncher.SECRET_ENV)
			# Children of this process (none yet) shouldn't inherit it.
			OS.unset_environment(HostLauncher.SECRET_ENV)
			if host_secret == "":
				push_error("--host-secret-env: %s is not set" % HostLauncher.SECRET_ENV)
				return false
		else:
			i += 1
			if i >= args.size() or not _set_flag(flag, args[i]):
				return false
		i += 1
	if bind_address == "":
		push_error("--bind ADDR is required (the LAN address to serve on, or 127.0.0.1)")
		return false
	if port < 0 or port > 65535:
		push_error("--port must be 0..65535")
		return false
	if discovery_port <= 0 or discovery_port > 65535:
		push_error("--discovery-port must be 1..65535")
		return false
	return true


func _set_flag(flag: String, value: String) -> bool:
	match flag:
		"--port", "--seed", "--discovery-port":
			if not value.is_valid_int():
				push_error("%s needs a whole number" % flag)
				return false
			match flag:
				"--port":
					port = value.to_int()
				"--seed":
					seed_value = value.to_int()
				_:
					discovery_port = value.to_int()
		"--grace-s", "--idle-exit-min", "--run-for":
			if not value.is_valid_float():
				push_error("%s needs a number" % flag)
				return false
			set(flag.trim_prefix("--").replace("-", "_"), value.to_float())
		"--bind":
			bind_address = value
		"--host-secret":
			host_secret = value
		"--pid-file":
			pid_file = value
		"--http-root":
			# Relative paths would resolve against res:// in an export.
			if not value.is_absolute_path():
				push_error("--http-root needs an absolute path")
				return false
			http_root = value
		"--name":
			server_name = value
		_:
			push_error("unknown argument %s" % flag)
			return false
	return true


## Builds and starts the server node (not yet in the tree); null on failure.
func make_server() -> NetServer:
	var defs: DefLibrary = DefLibrary.new()
	var player: ShipDef = defs.ship(&"m1_corvette")
	var enemy: EnemyDef = defs.enemy(&"m1_raider")
	if player == null or enemy == null:
		push_error("missing M1 definitions (m1_corvette, m1_raider)")
		return null
	var encounter: M1Encounter = M1Encounter.new(seed_value, "server", player, enemy)
	var server: NetServer = NetServer.new()
	server.run_for = run_for
	var err: Error = server.start(encounter, port, bind_address, dev_all_stations, host_secret)
	if err != OK:
		push_error("server failed to start on %s:%d: %s" % [bind_address, port, error_string(err)])
		server.free()
		return null
	server.session.sessions.grace_us = int(grace_s * 1_000_000.0)
	if http_root != "":
		err = server.start_http(http_root)
		if err != OK:
			push_error(
				(
					"HTTP server failed to start on %s:%d: %s"
					% [bind_address, server.port() - 1, error_string(err)]
				)
			)
			server.transport.stop()
			server.free()
			return null
	if beacon:
		server.start_beacon(server_name, discovery_port)
	return server


## The pid file and idle-exit node that runs next to `server` (FT-NET-003).
func make_lifecycle(server: NetServer) -> ServerLifecycle:
	return ServerLifecycle.new(server, pid_file, idle_exit_min)


## Engine settings for a headless server process (not for in-process tests).
static func configure_engine() -> void:
	OS.low_processor_usage_mode = true
	OS.low_processor_usage_mode_sleep_usec = SLEEP_USEC
	Engine.max_fps = MAX_FPS
