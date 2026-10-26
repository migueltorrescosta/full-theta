class_name ServerMain
extends RefCounted
## Headless dedicated server entry (FT-NET-002): parses the command line after `--` and
## builds the NetServer node that app/main.gd adds to the tree.
##
## godot --headless --path . -- --server --bind ADDR [flags]
##   --port N             WebSocket port [47801]; the HTTP port (web stations) is
##                        N - 1 (D108). 0 picks a free port (tests, smoke runs).
##   --bind ADDR          address to listen on, required: the chosen LAN address, not
##                        every interface (S3); 127.0.0.1 for a local host.
##   --dev-all-stations   offer the dev entry holding every station (FT-NET-029, D72).
##   --seed N             world seed [1].
##   --host-secret-env    read the host secret from the FT_HOST_SECRET environment
##                        variable (what HostLauncher passes; D127); the host client
##                        presents it in Hello. None by default.
##   --grace-s S          reconnect grace (s) [15] (FT-NET-033; T045 owns the rules).
##   --idle-exit-min M    exit after M minutes without connected players (connections
##                        with a session), wall clock (FT-NET-003); 0 never [0].
##   --pid-file PATH      write the pid file there while running (FT-NET-003).
##   --http-root DIR      serve this web export (an absolute path) over HTTP at
##                        port - 1 (FT-NET-030, D108); off without it.
##   --session-log PATH   write the session log (JSON Lines: snapshot-age summaries every
##                        10 s and a final summary, D199) there; "off" writes none
##                        [user://logs/session-<unix time>.jsonl].
##   --name NAME          server name in the LAN beacon ["Full Theta server"].
##   --discovery-port N   UDP port the beacon broadcasts to [47790] (FT-NET-012).
##   --no-beacon          don't broadcast on the LAN. A server bound to a loopback
##                        address never does: no other machine could join it.
##   --run-for S          quit after S seconds (smoke runs; 0 = run until killed).
##   --language LANG      the session's language, en, pt_PT or it [en]; the host picks it
##                        before launch and Welcome carries it (FT-AUD-013, D41).
##   --encounter NAME     what the world holds: run, the director's run (RunSetup on
##                        content/runs/m3_run.tres, E07) [run], shakedown, the training
##                        scenario (FT-MIS-039: RunSetup on content/runs/shakedown.tres, one
##                        ship, no director; strand G2), or m1, the Milestone 1 encounter
##                        (the L4 encounter scenario and the golden tests).
##   --m1-player-hull-scale F
##                        test flag: the crewed ship's hull is F times its definition's
##                        (0 < F <= 1), so the L4 encounter (tools/l4) loses a fight in
##                        under a minute; sim/ and content/ stay as they are [1].
##                        Debug builds only, or with FT_DEV set in the environment.
## Load gate only (#11, D160, D161; tools/l4/load.sh), never for play; refused in a
## release build unless FT_DEV is set:
##   --load-ships N       N crewable ships of one faction plus AI raiders (LoadEncounter)
##                        instead of the M1 encounter [0: off].
##   --load-world N       total ships with --load-ships, raiders included [12].
##   --probe-out PATH     record the tick and net-thread costs (LoadProbe) and write
##                        them to PATH; the server quits when the window ends.
##   --probe-picks N      the window waits for N sessions with a pick [64].
##   --probe-warmup S     seconds between all picks plus a Start and the window [3].
##   --probe-window S     length of the measured window [60].

const DEFAULT_PORT: int = NetProtocol.DEFAULT_WS_PORT
const DEFAULT_GRACE_S: float = NetSessions.DEFAULT_GRACE_US / 1_000_000.0
## Headless frame pacing (S3 "Server loop"): Godot otherwise sleeps 6.9 ms a frame in
## headless mode, capping it near 145 frames/s; 2 ms keeps the 60 Hz tick within about
## 2 ms of due without spinning. Provisional: see docs/protocol.md, Rates and limits.
const SLEEP_USEC: int = 2000
const MAX_FPS: int = 250
## The --encounter values that build a RunSetup (the director's run, the Shakedown).
const RUN_ENCOUNTERS: Array[String] = ["run", "shakedown"]  # strand G2
## The load gate's flags (dev and test only), and the variable that allows them and
## --m1-player-hull-scale in a release build.
const LOAD_FLAGS: Array[String] = [
	"--load-ships",
	"--load-world",
	"--probe-out",
	"--probe-picks",
	"--probe-warmup",
	"--probe-window"
]
const DEV_ENV: String = "FT_DEV"
## The enemies a crew can hail, and the conversation each answers with (STORY, strand E).
const HAIL_CONVERSATIONS: Dictionary[StringName, StringName] = {
	&"m1_raider": &"conv.surrender_demand"
}
## The beacon's default server name (provisional: see docs/protocol.md, Rates and limits).
const DEFAULT_NAME: String = "Full Theta server"

var port: int = DEFAULT_PORT
var bind_address: String = ""
var dev_all_stations: bool = false
var seed_value: int = 1
var host_secret: String = ""
var grace_s: float = DEFAULT_GRACE_S
var idle_exit_min: float = 0.0
var pid_file: String = ""
var run_for: float = 0.0
var http_root: String = ""
var session_log_path: String = SessionLog.default_path()
var server_name: String = DEFAULT_NAME
var discovery_port: int = LanBeacon.DISCOVERY_PORT
var beacon: bool = true
var language: String = I18n.LANGUAGES[0]
var load_ships: int = 0
var load_world: int = 12
var probe_out: String = ""
var probe_picks: int = 64
var probe_warmup: float = 3.0
var probe_window: float = 60.0
var player_hull_scale: float = 1.0
var encounter_name: String = "run"  # strand A, E
## Whether test flags (--m1-player-hull-scale, LOAD_FLAGS) are accepted: a debug build (the editor
## binary that L3 and L4 run) or FT_DEV set.
var dev_flags: bool = OS.is_debug_build() or OS.get_environment(DEV_ENV) != ""


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
			if i >= args.size() or not _set_value(flag, args[i]):
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
	return _check_load_flags(args)


## The load gate's flags (D160, D161) are for dev and test builds only, and each needs
## its companion: refused in a release build unless FT_DEV is set, and with a clear
## error instead of being ignored.
func _check_load_flags(args: PackedStringArray) -> bool:
	var given: Array[String] = []
	for flag: String in LOAD_FLAGS:
		if args.has(flag):
			given.append(flag)
	if given.is_empty():
		return true
	if not dev_flags:
		push_error("%s: dev and test only (debug build or %s set)" % [given, DEV_ENV])
		return false
	if load_ships < 0 or (args.has("--load-world") and load_ships == 0):
		push_error("--load-world needs --load-ships N (N >= 1)")
		return false
	for flag: String in ["--probe-picks", "--probe-warmup", "--probe-window"]:
		if args.has(flag) and probe_out == "":
			push_error("%s needs --probe-out PATH" % flag)
			return false
	return true


func _set_value(flag: String, value: String) -> bool:
	if flag == "--m1-player-hull-scale":
		return _set_hull_scale(value)
	if flag == "--encounter":  # strand A
		if not ["m1", "run", "shakedown"].has(value):  # strand G2
			push_error("--encounter must be m1, run or shakedown")
			return false
		encounter_name = value
		return true
	return _set_flag(flag, value)


func _set_flag(flag: String, value: String) -> bool:
	match flag:
		"--port", "--seed", "--discovery-port", "--load-ships", "--load-world", "--probe-picks":
			if not value.is_valid_int():
				push_error("%s needs a whole number" % flag)
				return false
			var n: int = value.to_int()
			match flag:
				"--port":
					port = n
				"--seed":
					seed_value = n
				"--discovery-port":
					discovery_port = n
				"--load-ships":
					load_ships = n
				"--load-world":
					load_world = n
				"--probe-picks":
					probe_picks = n
		"--grace-s", "--idle-exit-min", "--run-for", "--probe-warmup", "--probe-window":
			if not value.is_valid_float():
				push_error("%s needs a number" % flag)
				return false
			var x: float = value.to_float()
			match flag:
				"--grace-s":
					grace_s = x
				"--idle-exit-min":
					idle_exit_min = x
				"--run-for":
					run_for = x
				"--probe-warmup":
					probe_warmup = x
				"--probe-window":
					probe_window = x
		"--bind":
			bind_address = value
		"--pid-file":
			pid_file = value
		"--http-root":
			# Relative paths would resolve against res:// in an export.
			if not value.is_absolute_path():
				push_error("--http-root needs an absolute path")
				return false
			http_root = value
		"--probe-out":
			probe_out = value
		"--session-log":
			session_log_path = "" if value == "off" else value
		"--name":
			server_name = value
		"--language":
			if not I18n.LANGUAGES.has(value):
				push_error("--language must be one of %s" % ", ".join(I18n.LANGUAGES))
				return false
			language = value
		_:
			push_error("unknown argument %s" % flag)
			return false
	return true


## --m1-player-hull-scale: a test flag (dev_flags) taking a number in (0, 1].
func _set_hull_scale(value: String) -> bool:
	if not dev_flags:
		push_error("--m1-player-hull-scale is a test flag: debug builds, or set " + DEV_ENV)
		return false
	if not value.is_valid_float() or value.to_float() <= 0.0 or value.to_float() > 1.0:
		push_error("--m1-player-hull-scale needs a number in (0, 1]")
		return false
	player_hull_scale = value.to_float()
	return true


## Builds and starts the server node (not yet in the tree); null on failure.
func make_server() -> NetServer:
	var defs: DefLibrary = DefLibrary.new()
	var player: ShipDef = defs.ship(&"m1_corvette")
	var enemy: EnemyDef = defs.enemy(&"m1_raider")
	if player == null or enemy == null:
		push_error("missing M1 definitions (m1_corvette, m1_raider)")
		return null
	if player_hull_scale != 1.0:
		player = player.duplicate()
		player.hull_max *= player_hull_scale
	var encounter: M1Encounter = M1Encounter.new(seed_value, "server", player, enemy)
	var run: RunSetup = run_setup(defs) if encounter_name in RUN_ENCOUNTERS else null  # strand A
	if encounter_name in RUN_ENCOUNTERS:  # strand G2
		if run == null:
			return null
		encounter = run
	# STAND-IN (#11 lobby): the multi-ship lobby replaces --load-ships and LoadEncounter.
	if load_ships > 0:
		encounter = LoadEncounter.new(seed_value, "server", player, enemy, load_ships, load_world)
		run = null  # strand A
	encounter.science = defs.science()
	if load_ships <= 0 and run == null:
		encounter.hazards = defs.m1_hazards()
	var server: NetServer = NetServer.new()
	if run != null:  # strand A
		server.driver_factory = (
			_training_factory() if encounter_name == "shakedown" else _director_factory(run)
		)  # G2
	server.run_for = run_for
	if probe_out != "":
		server.probe = LoadProbe.new(probe_out)
		server.probe.expect_picks = probe_picks
		server.probe.warmup_s = probe_warmup
		server.probe.window_s = probe_window
	var err: Error = server.start(encounter, port, bind_address, dev_all_stations, host_secret)
	if err != OK:
		push_error("server failed to start on %s:%d: %s" % [bind_address, port, error_string(err)])
		server.free()
		return null
	server.session.sessions.grace_us = int(grace_s * 1_000_000.0)
	server.session.language = language
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
	if beacon and not is_loopback(bind_address):
		server.start_beacon(server_name, discovery_port)
	if session_log_path != "":
		server.start_session_log(session_log_path)
	return server


# --- strand A ---
## The run on content/runs/m3_run.tres with the enemy catalogue, or null (reported).
func run_setup(defs: DefLibrary) -> RunSetup:
	var run_def: RunDef = defs.run(&"shakedown" if encounter_name == "shakedown" else &"m3_run")
	if run_def == null:
		push_error("missing run definition for --encounter %s" % encounter_name)
		return null
	var setup: RunSetup = RunSetup.new(seed_value, "server", run_def, defs.enemies())
	setup.science = defs.science()
	setup.conversations = ConversationLibrary.load_dir()
	for path: String in DefLibrary.list_tres("res://content/modules"):
		setup.module_defs.append(load(path) as ModuleDef)
	for path: String in DefLibrary.list_tres("res://content/economy/rep"):
		var dist: RepDistDef = load(path) as RepDistDef
		setup.rep_dists[dist.id] = dist
	for path: String in DefLibrary.list_tres("res://content/economy/markets"):
		var market: MarketDef = load(path) as MarketDef
		setup.markets[market.id] = market
	# --- strand E --- (the site ids are the map's load order; hails by enemy key)
	var sites: Array[SiteDef] = run_def.map.sites if run_def.map != null else []
	for i: int in sites.size():
		if sites[i].market != &"":
			setup.site_markets[i] = sites[i].market
	setup.hail_conversations = HAIL_CONVERSATIONS
	# --- end strand E ---
	return setup


## Makes the director for a run when the first tick steps: the lobby's difficulty preset
## picks its budget, the catalogue is the scenarios the run lists (E07, D81).
func _director_factory(setup: RunSetup) -> Callable:
	return func(difficulty: StringName) -> Director:
		var d: Director = Director.new(
			setup.run_def.director,
			difficulty,
			ScenarioCatalogue.load_for(setup.run_def.scenarios),
			seed_value
		)
		d.encounters_per_run = setup.run_def.encounters
		return d


# --- end strand A ---
# --- strand G2 ---
## The Shakedown's driver when the first tick steps (FT-MIS-039): its one scenario and the
## step list. The difficulty preset changes nothing in training.
func _training_factory() -> Callable:
	return func(_difficulty: StringName) -> TrainingDriver:
		var scenarios: Array[Scenario] = ScenarioCatalogue.load_for(
			PackedStringArray(["shakedown"])
		)
		var steps: TrainingStepsDef = load("res://content/training/steps.tres") as TrainingStepsDef
		return TrainingDriver.new(scenarios[0], steps)


# --- end strand G2 ---
## The host's voice service next to `server` (E10, VoiceSetup), events at the sim tick,
## wired into the session: silent until the first Start calls start_session() with the
## session language and closed set; ship-computer lines go to the stations concerned
## (ServerVoice, ServerSession.computer_audience, FT-AUD-006).
func make_voice(server: NetServer) -> VoiceService:
	var voice: VoiceService = VoiceSetup.make_service(
		server.transport, func() -> int: return server.world.tick
	)
	voice.computer_audience = server.session.computer_audience
	voice.npc_audience = server.session.npc_audience  # --- strand G1 ---
	server.session.voice.voice = voice
	return voice


## The pid file and idle-exit node that runs next to `server` (FT-NET-003).
func make_lifecycle(server: NetServer) -> ServerLifecycle:
	return ServerLifecycle.new(server, pid_file, idle_exit_min)


## True for an address only this machine reaches (127.0.0.0/8, ::1, localhost).
static func is_loopback(address: String) -> bool:
	return address.begins_with("127.") or address in ["::1", "localhost"]


## Engine settings for a headless server process (not for in-process tests).
static func configure_engine() -> void:
	OS.low_processor_usage_mode = true
	OS.low_processor_usage_mode_sleep_usec = SLEEP_USEC
	Engine.max_fps = MAX_FPS
