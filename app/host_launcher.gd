class_name HostLauncher
extends RefCounted
## The Host button's server child (FT-NET-001, FT-M1-002, D7): spawns this
## same executable headless as a server bound to localhost, and kills it when
## the host client exits (FT-NET-003). The client then connects to
## ws://127.0.0.1:<port>.
##
## Each spawn makes a fresh random host secret (D127), passed to the child in
## the FT_HOST_SECRET environment variable with `--host-secret-env`, never on
## the command line: /proc/<pid>/cmdline is world-readable, while
## /proc/<pid>/environ is readable only by the same user. The host client
## presents it in its Hello and the server treats that client as the host. Keep
## it with the stored token (SessionTokenFile.host_secret), not in the pid file.
## A dedicated server has none.
##
## Bound to 127.0.0.1 for now: other machines can join once the host picks a
## LAN address (T047 and E13 pass it as `--bind`).

const BIND: String = "127.0.0.1"
## Minutes without connections before the child exits by itself. Provisional:
## FT-NET-003 leaves N open.
const DEFAULT_IDLE_EXIT_MIN: int = 10
const SECRET_BYTES: int = 32
## Environment variable that carries the host secret to the child (D127).
const SECRET_ENV: String = "FT_HOST_SECRET"

## The child's pid, or -1 when none was spawned.
var pid: int = -1
var port: int = 0
var pid_file: String = ServerPidFile.PATH
## Hex host secret of the last spawn (D127), "" before the first.
var host_secret: String = ""
## Extra engine arguments (before `--`) and server flags for the child; tests
## pass `--log-file` and `--no-beacon`.
var engine_args: PackedStringArray = []
var extra_server_args: PackedStringArray = []
## True when `pid` is an orphan this client adopted (adopt()) rather than its
## own child: Godot can only watch its own children.
var adopted: bool = false


## The command-line arguments that start the server child. `project_path` is
## the project folder when running from the editor binary, or "" in an export.
static func server_args(
	ws_port: int, pid_file_path: String, idle_exit_min: float, project_path: String
) -> PackedStringArray:
	var args: PackedStringArray = ["--headless"]
	if project_path != "":
		args.append_array(["--path", project_path])
	(
		args
		. append_array(
			[
				"--",
				"--server",
				"--bind",
				BIND,
				"--port",
				str(ws_port),
				"--pid-file",
				pid_file_path,
				"--idle-exit-min",
				str(idle_exit_min),
				"--host-secret-env",
			]
		)
	)
	return args


## A fresh random host secret, hex (D127).
static func new_secret() -> String:
	return Crypto.new().generate_random_bytes(SECRET_BYTES).hex_encode()


## The project folder to pass as `--path`, or "" in an exported build, where the
## pck sits next to the executable.
static func project_path() -> String:
	if OS.has_feature("template"):
		return ""
	return ProjectSettings.globalize_path("res://")


## Spawns the server child. The pid file path is passed absolute so the child
## writes the same file whatever its working directory. Port 0 lets the child
## pick a free port; is_ready() then reads it from the pid file.
func spawn(
	ws_port: int,
	pid_file_path: String = ServerPidFile.PATH,
	idle_exit_min: float = DEFAULT_IDLE_EXIT_MIN
) -> Error:
	if is_running():
		return ERR_ALREADY_IN_USE
	port = ws_port
	pid_file = pid_file_path
	adopted = false
	host_secret = new_secret()
	var args: PackedStringArray = engine_args.duplicate()
	args.append_array(
		server_args(
			ws_port, ProjectSettings.globalize_path(pid_file_path), idle_exit_min, project_path()
		)
	)
	# A release package's host serves its bundled web export (FT-ARC-022, D108).
	var web: String = ReleaseBundle.web_root()
	if web != "":
		args.append_array(["--http-root", web])
	args.append_array(extra_server_args)
	# The child inherits the environment at fork; clear it again at once.
	OS.set_environment(SECRET_ENV, host_secret)
	pid = OS.create_process(OS.get_executable_path(), args)
	OS.unset_environment(SECRET_ENV)
	return OK if pid > 0 else ERR_CANT_FORK


## Takes charge of an orphaned server (OrphanCheck, FT-NET-003) the player
## rejoins, so stop() terminates it later like a child of this client.
func adopt(info: ServerPidFile, secret: String, pid_file_path: String = ServerPidFile.PATH) -> void:
	pid = info.pid
	port = info.port
	pid_file = pid_file_path
	host_secret = secret
	adopted = true


## True while the server runs. Our own child is watched with
## `OS.is_process_running` (which also reaps it); an adopted orphan isn't our
## child, so Godot reports false for it on Linux, and OrphanCheck asks /proc.
func is_running() -> bool:
	if pid <= 0:
		return false
	return OrphanCheck.process_alive(pid) if adopted else OS.is_process_running(pid)


## True once the child has written its pid file, that is once it listens; the
## port is then the one in the file (it differs from the requested one after a
## spawn on port 0).
func is_ready() -> bool:
	var info: ServerPidFile = ServerPidFile.load_from(pid_file)
	if not is_running() or info == null or info.pid != pid:
		return false
	port = info.port
	return true


## Kills the child and removes its pid file: a killed process can't remove it.
## Call it when the host client exits or leaves the session it hosts.
func stop() -> void:
	if pid <= 0:
		return
	if is_running():
		OS.kill(pid)
	var info: ServerPidFile = ServerPidFile.load_from(pid_file)
	if info != null and info.pid == pid:
		ServerPidFile.remove(pid_file)
	pid = -1
	adopted = false
