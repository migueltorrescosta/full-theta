class_name PiperBinarySynth
extends PiperProcessSynth
## Release adapter: the standalone rhasspy/piper 2023.11.14-2 binary (TECH-4: no
## Python), run persistent with `--json-input --quiet`. That build marks no clip end in
## its raw output, so each request is split into sentences here and each sentence is one
## JSON line with its own `output_file` in a temp directory: the binary prints the path
## once the WAV is written, which ends the sentence. The WAV is read, deleted and handed
## over as one part; the last sentence's part is `last`.
##
## The binary takes length_scale, noise_scale and noise_w only on its command line, not
## per line: start()'s defaults set them for the whole process, and per-request settings
## are ignored.

const _ENDS: String = ".!?…"
const _CLOSERS: String = ".!?…\"')]»”’"
const _FLAGS: Dictionary = {
	"length_scale": "--length_scale", "noise_scale": "--noise_scale", "noise_w_scale": "--noise_w"
}

var binary: String = ""
var model: String = ""
## Where the sentence WAVs go; made by start(), removed by stop().
var tmp_dir: String = ""

var _seq: int = 0


func _init(binary_path: String, model_path: String, name: String = "") -> void:
	binary = binary_path
	model = model_path
	voice = name if name != "" else model_path.get_file().get_basename()


func start(defaults: Dictionary = {}) -> Error:
	if tmp_dir == "":
		tmp_dir = (OS.get_user_data_dir().path_join("voice_tmp").path_join(
			"%s-%d-%d" % [voice.validate_filename(), OS.get_process_id(), get_instance_id()]
		))
	var err: Error = DirAccess.make_dir_recursive_absolute(tmp_dir)
	if err != OK:
		return err
	return super.start(defaults)


func stop() -> void:
	super.stop()
	if tmp_dir != "" and DirAccess.dir_exists_absolute(tmp_dir):
		for f: String in DirAccess.get_files_at(tmp_dir):
			DirAccess.remove_absolute(tmp_dir.path_join(f))
		DirAccess.remove_absolute(tmp_dir)


## Splits text into sentences at . ! ? … followed by a space or the end (closing quotes
## and brackets stay with their sentence); a piece with no letter or digit joins the one
## before it.
static func split_sentences(text: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var start_at: int = 0
	var i: int = 0
	var n: int = text.length()
	while i < n:
		if _ENDS.contains(text[i]):
			var j: int = i + 1
			while j < n and _CLOSERS.contains(text[j]):
				j += 1
			if j == n or text[j] == " " or text[j] == "\n" or text[j] == "\t":
				_add_sentence(out, text.substr(start_at, j - start_at))
				start_at = j
				i = j
				continue
		i += 1
	_add_sentence(out, text.substr(start_at))
	return out


## {"rate": int, "pcm": PackedByteArray} of a 16-bit mono PCM WAV, or {}.
static func parse_wav(data: PackedByteArray) -> Dictionary:
	if data.size() < 12 or data.slice(0, 4).get_string_from_ascii() != "RIFF":
		return {}
	if data.slice(8, 12).get_string_from_ascii() != "WAVE":
		return {}
	var at: int = 12
	var wav_rate: int = 0
	while at + 8 <= data.size():
		var id: String = data.slice(at, at + 4).get_string_from_ascii()
		var size: int = data.decode_u32(at + 4)
		var body: int = at + 8
		if id == "fmt " and size >= 16 and body + 16 <= data.size():
			var pcm_format: int = data.decode_u16(body)
			var channels: int = data.decode_u16(body + 2)
			var bits: int = data.decode_u16(body + 14)
			if pcm_format != 1 or channels != 1 or bits != 16:
				return {}
			wav_rate = data.decode_u32(body + 4)
		elif id == "data":
			if wav_rate == 0:
				return {}
			return {"rate": wav_rate, "pcm": data.slice(body, mini(body + size, data.size()))}
		at = body + size + (size & 1)
	return {}


static func _add_sentence(out: PackedStringArray, piece: String) -> void:
	var s: String = piece.strip_edges()
	if s == "":
		return
	var spoken: bool = false
	for c: String in s:
		if c.to_lower() != c.to_upper() or c.is_valid_int():
			spoken = true
			break
	if not spoken and not out.is_empty():
		out[out.size() - 1] = out[out.size() - 1] + " " + s
	else:
		out.append(s)


func _command() -> Array:
	var args: PackedStringArray = ["--quiet", "--model", model, "--json-input"]
	for key: String in _FLAGS:
		if _defaults.has(key):
			args.append_array([_FLAGS[key], str(float(_defaults[key]))])
	return [binary, args]


## No ready frame: a warm-up sentence proves the voice loaded and gives its rate.
func _handshake() -> bool:
	var wav: Dictionary = _sentence("Ready.")
	if wav.is_empty():
		return false
	rate = wav["rate"]
	return true


func _synthesise(req: Dictionary) -> bool:
	var sentences: PackedStringArray = split_sentences(req["text"])
	if sentences.is_empty():
		_push(req, true, PackedByteArray(), rate)
		return true
	for i: int in sentences.size():
		var last: bool = i == sentences.size() - 1
		var wav: Dictionary = _sentence(sentences[i])
		if wav.is_empty():
			return false
		if wav.has("error"):
			_push(req, true, PackedByteArray(), rate, wav["error"])
			return true
		_push(req, last, wav["pcm"], wav["rate"])
	return true


## Synthesises one sentence: {"rate", "pcm"}, {"error"} for an unreadable WAV, or {} when
## the process ended.
func _sentence(text: String) -> Dictionary:
	_seq += 1
	var path: String = tmp_dir.path_join("s%d.wav" % _seq)
	_write_line(JSON.stringify({"text": text, "output_file": path}))
	var done: String = _stdio.get_line().strip_edges()
	if done == "":
		return {}
	var wav: Dictionary = parse_wav(FileAccess.get_file_as_bytes(path))
	DirAccess.remove_absolute(path)
	return wav if not wav.is_empty() else {"error": "unreadable wav for %s" % voice}
