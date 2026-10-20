class_name S7bPiper
extends RefCounted
## One persistent Piper process for one voice (tools/tts/piper_stream.py),
## started with OS.execute_with_pipe and driven by a worker Thread, so the
## server's 60 Hz sim and network loop never blocks on the pipe (FT-AUD-019,
## FT-ARC-019). The main loop calls request() and take_clips(); both only take
## a mutex. Clip times are unix microseconds, comparable across processes.

var voice: String = ""
var pid: int = -1
## True: hand over each sentence as soon as Piper finishes it, so playback can
## start while later sentences synthesise. False: one part per whole clip.
var per_sentence: bool = true

var _stdio: FileAccess
var _stderr: FileAccess
var _thread: Thread
var _mutex: Mutex = Mutex.new()
var _wake: Semaphore = Semaphore.new()
var _requests: Array[Dictionary] = []
var _clips: Array[Dictionary] = []
var _in_flight: int = 0
var _stop: bool = false
var _ready: bool = false
var _rate: int = 0
var _load_us: int = 0
var _error: String = ""


## Starts `python wrapper voice --threads N` and the worker thread. A niceness
## above 0 runs it through nice(1), so the sim thread wins the CPU when both want it.
func start(
	python: String, wrapper: String, voice_name: String, threads: int, niceness: int = 0
) -> Error:
	voice = voice_name
	var path: String = python
	var args: PackedStringArray = [wrapper, voice_name, "--threads", str(threads)]
	if niceness > 0:
		path = "nice"
		args = PackedStringArray(["-n", str(niceness), python]) + args
	var info: Dictionary = OS.execute_with_pipe(path, args)
	if info.is_empty():
		return FAILED
	_stdio = info["stdio"]
	_stderr = info["stderr"]
	pid = info["pid"]
	_thread = Thread.new()
	return _thread.start(_run)


func is_ready() -> bool:
	_mutex.lock()
	var ready: bool = _ready
	_mutex.unlock()
	return ready


## Voice sample rate and model load time (warm-up included), once ready.
func info() -> Dictionary:
	_mutex.lock()
	var out: Dictionary = {"rate": _rate, "load_us": _load_us, "error": _error}
	_mutex.unlock()
	return out


## Queues a line; never blocks on the pipe.
func request(id: int, text: String) -> void:
	_mutex.lock()
	_requests.append({"id": id, "text": text, "queued_us": unix_us()})
	_in_flight += 1
	_mutex.unlock()
	_wake.post()


## Requests queued or being synthesised.
func pending() -> int:
	_mutex.lock()
	var n: int = _in_flight
	_mutex.unlock()
	return n


## Clip parts finished since the last call: {id, part, last, pcm, rate,
## synth_us, error, queued_us, started_us, first_us, done_us}. With
## per_sentence, a clip arrives as one part per sentence and an empty last part.
func take_clips() -> Array[Dictionary]:
	_mutex.lock()
	var out: Array[Dictionary] = _clips
	_clips = []
	_mutex.unlock()
	return out


## Stops the worker after its current clip; EOF on stdin ends the process.
func stop() -> void:
	_mutex.lock()
	_stop = true
	_mutex.unlock()
	_wake.post()
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
	if _stdio != null:
		_stdio.close()
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)


func _run() -> void:
	var hello: Dictionary = _read_frame()
	var head: Dictionary = hello.get("head", {})
	_mutex.lock()
	_ready = head.get("ready", false)
	_rate = int(head.get("rate", 0))
	_load_us = int(head.get("load_us", 0))
	if not _ready:
		_error = "no ready frame: %s" % _stderr.get_as_text()
	_mutex.unlock()
	while _ready:
		_wake.wait()
		_mutex.lock()
		if _stop:
			_mutex.unlock()
			return
		var req: Dictionary = _requests.pop_front() if not _requests.is_empty() else {}
		_mutex.unlock()
		if req.is_empty():
			continue
		_synthesise(req)
		_mutex.lock()
		_in_flight -= 1
		_mutex.unlock()


func _synthesise(req: Dictionary) -> void:
	var line: String = JSON.stringify({"id": req["id"], "text": req["text"]}) + "\n"
	var started_us: int = unix_us()
	_stdio.store_buffer(line.to_utf8_buffer())
	var pcm: PackedByteArray = PackedByteArray()
	var first_us: int = 0
	var part: int = 0
	var head: Dictionary = {}
	while true:
		var frame: Dictionary = _read_frame()
		if frame.is_empty():
			head = {"error": "piper process ended", "last": true}
			break
		head = frame["head"]
		var sentence: PackedByteArray = frame["pcm"]
		if first_us == 0 and sentence.size() > 0:
			first_us = unix_us()
		if per_sentence and sentence.size() > 0 and not head.get("last", false):
			_push_part(req, part, false, sentence, head, started_us, first_us)
			part += 1
		else:
			pcm.append_array(sentence)
		if head.get("last", false):
			break
	_push_part(req, part, true, pcm, head, started_us, first_us)


func _push_part(
	req: Dictionary,
	part: int,
	last: bool,
	pcm: PackedByteArray,
	head: Dictionary,
	started_us: int,
	first_us: int
) -> void:
	var clip: Dictionary = {
		"id": req["id"],
		"part": part,
		"last": last,
		"pcm": pcm,
		"rate": int(head.get("rate", _rate)),
		"synth_us": int(head.get("synth_us", 0)),
		"error": head.get("error", ""),
		"queued_us": req["queued_us"],
		"started_us": started_us,
		"first_us": first_us,
		"done_us": unix_us(),
	}
	_mutex.lock()
	_clips.append(clip)
	_mutex.unlock()


## One frame: u32 header length, JSON header, u32 PCM length, PCM. {} on EOF.
func _read_frame() -> Dictionary:
	var size: PackedByteArray = _read_exact(4)
	if size.size() < 4:
		return {}
	var head_bytes: PackedByteArray = _read_exact(size.decode_u32(0))
	var head: Variant = JSON.parse_string(head_bytes.get_string_from_utf8())
	size = _read_exact(4)
	if size.size() < 4 or not head is Dictionary:
		return {}
	return {"head": head, "pcm": _read_exact(size.decode_u32(0))}


## A pipe read returns what is available, so loop until n bytes or EOF.
func _read_exact(n: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	while out.size() < n:
		var part: PackedByteArray = _stdio.get_buffer(n - out.size())
		if part.is_empty():
			break
		out.append_array(part)
	return out


static func unix_us() -> int:
	return int(Time.get_unix_time_from_system() * 1_000_000.0)
