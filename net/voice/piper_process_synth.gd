class_name PiperProcessSynth
extends VoiceSynth
## The persistent-process half of the Piper adapters (FT-AUD-019, FT-ARC-019, spike
## S7b): one process per voice, started with OS.execute_with_pipe below the server's
## priority (`nice`), and one worker Thread that does every pipe write and read. The
## main loop only queues requests and takes finished parts under a mutex.
##
## The pipes are non-blocking and the worker polls them, so it never waits on a process
## for ever: stdout is read into a buffer, stderr is read and discarded (a chatty Piper
## would otherwise block once the pipe is full), and every launch and request has a
## deadline. A process that dies, or misses a deadline, is killed and restarted; the
## request it was working on ends with an error part, so its line stays subtitles only.
## A process that died while idle is relaunched before the next request is sent. After
## MAX_LAUNCH_FAILURES launches in a row fail, the voice gives up and fails every request
## at once.
##
## Subclasses implement _command(), _handshake() and _synthesise(), reading through
## _read_exact() and _read_line().

## Niceness of the Piper process: the sim thread wins the CPU (S7b). PROVISIONAL.
const NICENESS: int = 5
const MAX_LAUNCH_FAILURES: int = 3
## Process start to ready (model load and warm-up). PROVISIONAL.
const LAUNCH_TIMEOUT_MS: int = 30000
## A request's deadline from when the worker sends it: base plus per character of text.
## PROVISIONAL.
const REQUEST_BASE_MS: int = 4000
const REQUEST_MS_PER_CHAR: int = 25
## Largest PCM part handed over (about 45 s at 22,050 Hz); longer ones are cut, and a
## wrapper frame announcing more is refused as a bad frame. PROVISIONAL.
const MAX_PART_BYTES: int = 2_000_000
## The worker's sleep when the process has nothing for it. PROVISIONAL.
const POLL_MS: int = 2
const READ_CHUNK: int = 65536

var niceness: int = NICENESS
## Voice sample rate, once ready.
var rate: int = 0
## Deadlines (the constants; tests shorten them).
var launch_timeout_ms: int = LAUNCH_TIMEOUT_MS
var request_base_ms: int = REQUEST_BASE_MS
var request_ms_per_char: int = REQUEST_MS_PER_CHAR

## Settings applied to the whole process (start()).
var _defaults: Dictionary = {}
var _stdio: FileAccess
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
# Worker thread only: the running process, stdout read but not consumed, the deadline.
var _worker_pid: int = -1
var _buf: PackedByteArray = PackedByteArray()
var _deadline_ms: int = 0
var _timed_out: bool = false


func start(defaults: Dictionary = {}) -> Error:
	_defaults = defaults
	_thread = Thread.new()
	return _thread.start(_run)


func request(id: int, text: String, settings: Dictionary = {}, whole: bool = false) -> void:
	_mutex.lock()
	_requests.append(
		{
			"id": id,
			"text": text,
			"settings": settings,
			"whole": whole,
			"pcm": PackedByteArray(),
			"next_part": 0
		}
	)
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


## Synthesises one request, pushing its parts with _push(); returns false when the
## process ended or missed the deadline mid-request.
func _synthesise(_req: Dictionary) -> bool:
	return false


## Hands over a part (cut to MAX_PART_BYTES). A `whole` request collects its PCM and
## hands over one part at the end: whole_clip() of it, or no PCM after an error.
func _push(
	req: Dictionary, last: bool, pcm: PackedByteArray, part_rate: int, error: String = ""
) -> void:
	if pcm.size() > MAX_PART_BYTES:
		pcm = pcm.slice(0, MAX_PART_BYTES)
	if req.get("whole", false):
		req["pcm"] = (req["pcm"] as PackedByteArray) + pcm
		if not last:
			return
		pcm = VoiceSynth.whole_clip(req["pcm"], part_rate) if error == "" else PackedByteArray()
	var part: Dictionary = VoiceSynth.make_part(
		req["id"], req["next_part"], last, pcm, part_rate, error
	)
	req["next_part"] = int(req["next_part"]) + 1
	_mutex.lock()
	_parts.append(part)
	_mutex.unlock()


## Reads n bytes from the process's stdout; fewer only when the process ended, missed
## its deadline or the voice is stopping.
func _read_exact(n: int) -> PackedByteArray:
	while _buf.size() < n:
		if not _poll():
			break
	var out: PackedByteArray = _buf.slice(0, n)
	_buf = _buf.slice(out.size())
	return out


## Reads one line from stdout without its newline; "" when the process ended, missed its
## deadline or the voice is stopping.
func _read_line() -> String:
	while true:
		var at: int = _buf.find(10)
		if at >= 0:
			var line: String = _buf.slice(0, at).get_string_from_utf8()
			_buf = _buf.slice(at + 1)
			return line
		if not _poll():
			return ""
	return ""


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
		push_warning("voice %s: Piper process ended; restarting" % voice)


## Starts the process and waits until it is ready.
func _launch() -> bool:
	var cmd: Array = _command()
	var path: String = cmd[0]
	var args: PackedStringArray = cmd[1]
	if niceness > 0 and OS.get_name() != "Windows":
		args = PackedStringArray(["-n", str(niceness), path]) + args
		path = "nice"
	var info: Dictionary = OS.execute_with_pipe(path, args, false)
	if info.is_empty():
		return false
	_mutex.lock()
	_stdio = info["stdio"]
	_stderr = info["stderr"]
	_pid = info["pid"]
	var stopping: bool = _stopping
	_mutex.unlock()
	_worker_pid = info["pid"]
	_buf = PackedByteArray()
	_deadline_ms = Time.get_ticks_msec() + launch_timeout_ms
	return not stopping and _handshake()


## Serves requests until stop (returns true) or the process dies or misses a deadline
## (false).
func _serve() -> bool:
	while true:
		_wake.wait()
		if _is_stopping():
			return true
		if not OS.is_process_running(_worker_pid):
			# It died while idle: relaunch first, and keep this wake for the request.
			_wake.post()
			return false
		var req: Dictionary = _pop()
		if req.is_empty():
			continue
		_timed_out = false
		_deadline_ms = (
			Time.get_ticks_msec()
			+ request_base_ms
			+ request_ms_per_char * (req["text"] as String).length()
		)
		var alive: bool = _synthesise(req)
		if not alive:
			var why: String = "piper timed out" if _timed_out else "piper process ended"
			_push(req, true, PackedByteArray(), rate, why)
		_done()
		if not alive:
			return _is_stopping()
	return true


## One poll of the process: appends what it wrote to stdout to the buffer and discards
## its stderr. False when it ended (and nothing is left to read), missed the deadline or
## the voice is stopping; sleeps POLL_MS when nothing came.
func _poll() -> bool:
	var got: PackedByteArray = _stdio.get_buffer(READ_CHUNK)
	_stderr.get_buffer(READ_CHUNK)
	if not got.is_empty():
		_buf.append_array(got)
		return true
	if _is_stopping():
		return false
	if Time.get_ticks_msec() > _deadline_ms:
		_timed_out = true
		return false
	if not OS.is_process_running(_worker_pid):
		# What it wrote just before it ended.
		got = _stdio.get_buffer(READ_CHUNK)
		_buf.append_array(got)
		return not got.is_empty()
	OS.delay_msec(POLL_MS)
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
