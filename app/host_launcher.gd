class_name HostLauncher
extends RefCounted
## The Host button's server child (FT-NET-001, FT-M1-002, D7): spawns this
## same executable headless as a server bound to localhost, and kills it when
## the host client exits (FT-NET-003). The client then connects to
## ws://127.0.0.1:<port>.
##
## Each spawn makes a fresh random host secret (D127), passed to the child as
## `--host-secret HEX`; the host client presents it in its Hello and the server
## treats that client as the host. Keep it with the stored token
## (SessionTokenFile.host_secret), not in the pid file. A dedicated server has
## none.
##
## Bound to 127.0.0.1 for now: other machines can join once the host picks a
## LAN address (T047 and E13 pass it as `--bind`).

const BIND: String = "127.0.0.1"
## Minutes without connections before the child exits by itself. Provisional:
## FT-NET-003 leaves N open.
const DEFAULT_IDLE_EXIT_MIN: int = 10
const SECRET_BYTES: int = 32

## The child's pid, or -1 when none was spawned.
var pid: int = -1
var port: int = 0
var pid_file: String = ServerPidFile.PATH
## Hex host secret of the last spawn (D127), "" before the first.
var host_secret: String = ""


## The command-line arguments that start the server child. `project_path` is
## the project folder when running from the editor binary, or "" in an export.
static func server_args(
	ws_port: int, pid_file_path: String, idle_exit_min: int, secret: String, project_path: String
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
				"--host-secret",
				secret,
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
## writes the same file whatever its working directory.
func spawn(
	ws_port: int,
	pid_file_path: String = ServerPidFile.PATH,
	idle_exit_min: int = DEFAULT_IDLE_EXIT_MIN
) -> Error:
	if is_running():
		return ERR_ALREADY_IN_USE
	port = ws_port
	pid_file = pid_file_path
	host_secret = new_secret()
	var args: PackedStringArray = server_args(
		ws_port,
		ProjectSettings.globalize_path(pid_file_path),
		idle_exit_min,
		host_secret,
		project_path()
	)
	pid = OS.create_process(OS.get_executable_path(), args)
	return OK if pid > 0 else ERR_CANT_FORK


## True while the spawned child runs. Works only for our own child: Godot's
## `OS.is_process_running` reports false for any other process on Linux.
func is_running() -> bool:
	return pid > 0 and OS.is_process_running(pid)


## True once the child has written its pid file, that is once it listens.
func is_ready() -> bool:
	var info: ServerPidFile = ServerPidFile.load_from(pid_file)
	return is_running() and info != null and info.pid == pid


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
