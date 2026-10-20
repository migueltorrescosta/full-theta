class_name ServerLifecycle
extends Node
## The server process's housekeeping around NetServer (FT-NET-003, TECH-8): it writes
## the pid file once the server listens, rewrites its session_active flag when a
## session starts or ends, removes it on a clean exit, and quits after --idle-exit-min
## minutes without connected players, that is connections with a session (wall
## clock, IdleExitTimer; NetServer.bound_connections()). It also logs when the host
## client (D127) joins or leaves. app/main.gd adds it next to the NetServer; it runs
## after the server in the frame (process_priority 1).

var server: NetServer
## Pid file path ("" for none).
var pid_file: String = ""
var idle: IdleExitTimer
## Called when the idle limit passes; quits the process by default. Tests replace it.
var on_idle_exit: Callable

var _record: ServerPidFile
var _host: int = -1


func _init(net_server: NetServer, pid_path: String, idle_exit_min: float) -> void:
	server = net_server
	pid_file = pid_path
	idle = IdleExitTimer.new(idle_exit_min)
	process_priority = 1
	name = "ServerLifecycle"
	on_idle_exit = _quit


func _ready() -> void:
	if pid_file == "":
		return
	_record = ServerPidFile.for_this_process(server.port(), server.bind_address)
	if _record.save(pid_file) != OK:
		push_error("can't write the pid file %s" % pid_file)
		_record = null


func _process(_delta: float) -> void:
	var active: bool = server.session_active()
	if _record != null and active != _record.session_active:
		_record.session_active = active
		_record.save(pid_file)
	var host: int = server.host_session()
	if host != _host:
		_host = host
		print("server: host %s" % ("left" if host < 0 else "is session %d" % host))
	if idle.update(server.bound_connections(), Time.get_unix_time_from_system()):
		print("server: no connected players for %.2f min, exiting" % (idle.limit_s / 60.0))
		idle = IdleExitTimer.new(0.0)
		on_idle_exit.call()


func _exit_tree() -> void:
	remove_pid_file()


## Removes the pid file if it is still ours (a clean exit; FT-NET-003).
func remove_pid_file() -> void:
	if _record == null:
		return
	var on_disk: ServerPidFile = ServerPidFile.load_from(pid_file)
	if on_disk != null and on_disk.pid == _record.pid:
		ServerPidFile.remove(pid_file)
	_record = null


func _quit() -> void:
	remove_pid_file()
	get_tree().quit(0)
