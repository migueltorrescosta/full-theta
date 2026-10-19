class_name ServerPidFile
extends RefCounted
## The record a server child keeps in user data while it runs (FT-NET-003):
## its pid, ports, executable and whether a session is active. The server
## writes it once it listens and rewrites it when a session starts or ends; it
## removes it on a clean exit. The host client reads it on start to find an
## orphaned server (OrphanCheck), and the launcher reads it to know the child
## is up.

const PATH: String = "user://server_pid.json"
const FORMAT: int = 1

var pid: int = 0
## WebSocket port; the HTTP port for browser stations is one below (D108).
var port: int = 0
var bind: String = ""
## Absolute path of the executable the server runs from; identifies the install.
var executable: String = ""
## Wall-clock start, unix seconds.
var started_unix: int = 0
## True while a session (a lobby with players or a run) is active, so a
## relaunched host offers to rejoin instead of terminating it (TECH-8).
var session_active: bool = false


## A record for the calling process, as the server child writes it.
static func for_this_process(ws_port: int, bind_address: String) -> ServerPidFile:
	var f: ServerPidFile = ServerPidFile.new()
	f.pid = OS.get_process_id()
	f.port = ws_port
	f.bind = bind_address
	f.executable = OS.get_executable_path()
	f.started_unix = int(Time.get_unix_time_from_system())
	return f


func to_dict() -> Dictionary:
	return {
		"format": FORMAT,
		"pid": pid,
		"port": port,
		"bind": bind,
		"executable": executable,
		"started_unix": started_unix,
		"session_active": session_active,
	}


## Returns null unless `d` is a well-formed record of this format.
static func from_dict(d: Dictionary) -> ServerPidFile:
	var numbers: Array[String] = ["format", "pid", "port", "started_unix"]
	for key: String in numbers:
		if not (d.get(key) is float or d.get(key) is int):
			return null
	if not (d.get("bind") is String and d.get("executable") is String):
		return null
	if not d.get("session_active") is bool or int(d["format"]) != FORMAT:
		return null
	var f: ServerPidFile = ServerPidFile.new()
	f.pid = int(d["pid"])
	f.port = int(d["port"])
	f.bind = d["bind"]
	f.executable = d["executable"]
	f.started_unix = int(d["started_unix"])
	f.session_active = d["session_active"]
	return f if f.pid > 0 else null


## Writes the record atomically (a temporary file renamed over the old one), so
## a reader never sees half a file.
func save(path: String = PATH) -> Error:
	var abs_path: String = ProjectSettings.globalize_path(path)
	var tmp: String = abs_path + ".tmp"
	var file: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict()))
	file.close()
	return DirAccess.rename_absolute(tmp, abs_path)


## The record at `path`, or null if it is missing or malformed.
static func load_from(path: String = PATH) -> ServerPidFile:
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return from_dict(parsed) if parsed is Dictionary else null


static func remove(path: String = PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
