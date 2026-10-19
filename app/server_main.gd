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
##   --grace-s S          reconnect grace (s) [10] (FT-NET-033; T045 owns the rules).
##   --idle-exit-min M    reserved for T045/T047: exit after M minutes without
##                        connections (FT-NET-003); parsed, not acted on yet.
##   --pid-file PATH      reserved for the host's orphan check (FT-NET-003); parsed only.
##   --run-for S          quit after S seconds (smoke runs; 0 = run until killed).

const DEFAULT_PORT: int = NetProtocol.DEFAULT_WS_PORT
## Headless frame pacing (S3 "Server loop"): Godot otherwise sleeps 6.9 ms a frame in
## headless mode, capping it near 145 frames/s; 2 ms keeps the 60 Hz tick within about
## 2 ms of due without spinning. PROVISIONAL.
const SLEEP_USEC: int = 2000
const MAX_FPS: int = 250

var port: int = DEFAULT_PORT
var bind_address: String = ""
var dev_all_stations: bool = false
var seed_value: int = 1
var host_secret: String = ""
var grace_s: float = 10.0
var idle_exit_min: float = 0.0
var pid_file: String = ""
var run_for: float = 0.0


## Parses the flags; reports the problem and returns false on a bad command line.
func parse_args(args: PackedStringArray) -> bool:
	var i: int = 0
	while i < args.size():
		var flag: String = args[i]
		if flag == "--server":
			pass
		elif flag == "--dev-all-stations":
			dev_all_stations = true
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
	return true


func _set_flag(flag: String, value: String) -> bool:
	match flag:
		"--port", "--seed":
			if not value.is_valid_int():
				push_error("%s needs a whole number" % flag)
				return false
			if flag == "--port":
				port = value.to_int()
			else:
				seed_value = value.to_int()
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
	return server


## Engine settings for a headless server process (not for in-process tests).
static func configure_engine() -> void:
	OS.low_processor_usage_mode = true
	OS.low_processor_usage_mode_sleep_usec = SLEEP_USEC
	Engine.max_fps = MAX_FPS
