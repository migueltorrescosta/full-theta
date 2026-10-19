class_name PiperStreamSynth
extends PiperProcessSynth
## Development adapter: piper-tts 1.8.0 through tools/tts/piper_stream.py (spike S7b's
## wrapper protocol), run with the tools/tts venv's Python and `--threads 1`. One JSON
## request per line in; length-prefixed frames out (u32 header length, JSON header, u32
## PCM length, PCM), one per sentence, and a frame with "last" ends the request. Takes
## the role settings per request.

## ONNX intra-op threads per process (S7b). PROVISIONAL.
const THREADS: int = 1
const MAX_HEAD_BYTES: int = 65536

var python: String = ""
var wrapper: String = ""
var model: String = ""


func _init(
	python_path: String, wrapper_path: String, model_path: String, name: String = ""
) -> void:
	python = python_path
	wrapper = wrapper_path
	model = model_path
	voice = name if name != "" else model_path.get_file().get_basename()


## One frame read through `read` (Callable(n: int) -> PackedByteArray, fewer bytes only at
## EOF): {"head": Dictionary, "pcm": PackedByteArray}, or {} at EOF or on a bad frame (a
## header over MAX_HEAD_BYTES or PCM over MAX_PART_BYTES is bad).
static func read_frame(read: Callable) -> Dictionary:
	var size: PackedByteArray = read.call(4)
	if size.size() < 4 or size.decode_u32(0) > MAX_HEAD_BYTES:
		return {}
	var head_bytes: PackedByteArray = read.call(size.decode_u32(0))
	var head: Variant = JSON.parse_string(head_bytes.get_string_from_utf8())
	size = read.call(4)
	if size.size() < 4 or not head is Dictionary:
		return {}
	var n: int = size.decode_u32(0)
	if n > MAX_PART_BYTES:
		return {}
	var pcm: PackedByteArray = read.call(n)
	if pcm.size() < n:
		return {}
	return {"head": head, "pcm": pcm}


## The request line the wrapper reads: id, text and the settings it knows.
static func request_line(id: int, text: String, settings: Dictionary) -> String:
	var req: Dictionary = {"id": id, "text": text}
	for key: String in VoiceSynth.SETTING_KEYS:
		if settings.has(key):
			req[key] = float(settings[key])
	return JSON.stringify(req)


func _command() -> Array:
	return [python, PackedStringArray([wrapper, model, "--threads", str(THREADS)])]


func _handshake() -> bool:
	var frame: Dictionary = read_frame(_read_exact)
	var head: Dictionary = frame.get("head", {})
	if not head.get("ready", false):
		return false
	rate = int(head.get("rate", 0))
	return rate > 0


func _synthesise(req: Dictionary) -> bool:
	_write_line(request_line(req["id"], req["text"], req["settings"]))
	while true:
		var frame: Dictionary = read_frame(_read_exact)
		if frame.is_empty():
			return false
		var head: Dictionary = frame["head"]
		var pcm: PackedByteArray = frame["pcm"]
		var last: bool = head.get("last", false)
		var error: String = str(head.get("error", ""))
		if last or pcm.size() > 0:
			_push(req, last, pcm, int(head.get("rate", rate)), error)
		if last:
			return true
	return true
