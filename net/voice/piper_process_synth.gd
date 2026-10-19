class_name PiperProcessSynth
extends VoiceSynth
## The persistent-process half of the Piper adapters (FT-AUD-019, FT-ARC-019, spike
## S7b): one process per voice, started with OS.execute_with_pipe below the server's
## priority (`nice`), and one worker Thread that does every blocking pipe write and read.
## The main loop only queues requests and takes finished parts under a mutex.
##
## A process that dies is restarted; the request it was working on ends with an error
## part, so its line stays subtitles only. After MAX_LAUNCH_FAILURES launches in a row
## fail, the voice gives up and fails every request at once.
##
## Subclasses implement _command(), _handshake() and _synthesise().

## Niceness of the Piper process: the sim thread wins the CPU (S7b). PROVISIONAL.
const NICENESS: int = 5
const MAX_LAUNCH_FAILURES: int = 3

var niceness: int = NICENESS
## Voice sample rate, once ready.
var rate: int = 0
## Times the process was restarted after it died (worker thread writes, under mutex).
var restarts: int = 0

## Settings applied to the whole process (start()).
var _defaults: Dictionary = {}
var _stdio: FileAccess
## Kept open (never read): closing it would break the process's writes to stderr.
var _stderr: FileAccess
var _pid: int = -1
var _thread: Thread
var _mutex: Mutex = Mutex.new()
var _wake: Semaphore = Semaphore.new()
var _requests: Array[Dictionary] = []
var _parts: Array[Dictionary] = []
var _in_flight: int = 0
var _stopping: bool = false
var _ready: bool = false
var _dead: bool = false


func start(defaults: Dictionary = {}) -> Error:
	_defaults = defaults
	_thread = Thread.new()
	return _thread.start(_run)


func request(id: int, text: String, settings: Dictionary = {}) -> void:
	_mutex.lock()
	_requests.append({"id": id, "text": text, "settings": settings, "next_part": 0})
	_in_flight += 1
	_mutex.unlock()
	_wake.post()


func take_parts() -> Array[Dictionary]:
	_mutex.lock()
	var out: Array[Dictionary] = _parts
	_parts = []
	_mutex.unlock()
	return out


func pending() -> int:
	_mutex.lock()
	var n: int = _in_flight
	_mutex.unlock()
	return n


func is_ready() -> bool:
	_mutex.lock()
	var ready: bool = _ready
	_mutex.unlock()
	return ready


## True once the voice gave up after repeated launch failures.
func is_dead() -> bool:
	_mutex.lock()
	var dead: bool = _dead
	_mutex.unlock()
	return dead


func stop() -> void:
	_mutex.lock()
	_stopping = true
	_mutex.unlock()
	_wake.post()
	# Killing the process ends any blocking read on the worker thread with EOF.
	_kill()
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null
	_close_process()


# --- For subclasses (worker thread). ---


## [path, args] of the process to start.
func _command() -> Array:
	return ["", PackedStringArray()]


## Waits for the started process to be ready (reads its ready frame or synthesises a
## warm-up line), sets `rate`; false when it failed.
func _handshake() -> bool:
	return false


## Synthesises one request, pushing its parts with _push() (and req["next_part"] kept
## current); returns false when the process ended mid-request.
func _synthesise(_req: Dictionary) -> bool:
	return false


func _push(
	req: Dictionary, last: bool, pcm: PackedByteArray, part_rate: int, error: String = ""
) -> void:
	var part: Dictionary = VoiceSynth.make_part(
		req["id"], req["next_part"], last, pcm, part_rate, error
	)
	req["next_part"] = int(req["next_part"]) + 1
	_mutex.lock()
	_parts.append(part)
	_mutex.unlock()


## Reads up to n bytes from the process's stdout; fewer only at EOF.
func _read_exact(n: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	while out.size() < n:
		var chunk: PackedByteArray = _stdio.get_buffer(n - out.size())
		if chunk.is_empty():
			break
		out.append_array(chunk)
	return out


func _write_line(text: String) -> void:
	_stdio.store_buffer((text + "\n").to_utf8_buffer())


# --- Worker thread. ---


func _run() -> void:
	var failures: int = 0
	while not _is_stopping():
		if failures >= MAX_LAUNCH_FAILURES:
			_mutex.lock()
			_dead = true
			_mutex.unlock()
			push_warning(
				"voice %s: Piper failed to start %d times; subtitles only" % [voice, failures]
			)
			_fail_forever()
			return
		if not _launch():
			failures += 1
			_close_process()
			continue
		failures = 0
		_set_ready(true)
		if _serve():
			return
		_set_ready(false)
		_close_process()
		_mutex.lock()
		restarts += 1
		_mutex.unlock()
		push_warning("voice %s: Piper process ended; restarting" % voice)


## Starts the process and waits until it is ready.
func _launch() -> bool:
	var cmd: Array = _command()
	var path: String = cmd[0]
	var args: PackedStringArray = cmd[1]
	if niceness > 0 and OS.get_name() != "Windows":
		args = PackedStringArray(["-n", str(niceness), path]) + args
		path = "nice"
	var info: Dictionary = OS.execute_with_pipe(path, args)
	if info.is_empty():
		return false
	_mutex.lock()
	_stdio = info["stdio"]
	_stderr = info["stderr"]
	_pid = info["pid"]
	var stopping: bool = _stopping
	_mutex.unlock()
	return not stopping and _handshake()


## Serves requests until stop (returns true) or the process dies (false).
func _serve() -> bool:
	while true:
		_wake.wait()
		if _is_stopping():
			return true
		var req: Dictionary = _pop()
		if req.is_empty():
			continue
		var alive: bool = _synthesise(req)
		if not alive:
			_push(req, true, PackedByteArray(), rate, "piper process ended")
		_done()
		if not alive:
			return _is_stopping()
	return true


## After giving up: every request ends with an error part at once.
func _fail_forever() -> void:
	while true:
		_wake.wait()
		if _is_stopping():
			return
		var req: Dictionary = _pop()
		if not req.is_empty():
			_push(req, true, PackedByteArray(), rate, "piper unavailable")
			_done()


func _pop() -> Dictionary:
	_mutex.lock()
	var req: Dictionary = _requests.pop_front() if not _requests.is_empty() else {}
	_mutex.unlock()
	return req


func _done() -> void:
	_mutex.lock()
	_in_flight -= 1
	_mutex.unlock()


func _is_stopping() -> bool:
	_mutex.lock()
	var s: bool = _stopping
	_mutex.unlock()
	return s


func _set_ready(ready: bool) -> void:
	_mutex.lock()
	_ready = ready
	_mutex.unlock()


func _kill() -> void:
	_mutex.lock()
	var pid: int = _pid
	_pid = -1
	_mutex.unlock()
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)


func _close_process() -> void:
	_kill()
	_mutex.lock()
	if _stdio != null:
		_stdio.close()
	if _stderr != null:
		_stderr.close()
	_stdio = null
	_stderr = null
	_pid = -1
	_mutex.unlock()
