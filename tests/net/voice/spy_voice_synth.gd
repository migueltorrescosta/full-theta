class_name SpyVoiceSynth
extends VoiceSynth
## A VoiceSynth that records every request and answers it without Piper: one part per
## sentence (PiperBinarySynth.split_sentences), each LEN_PER_CHAR samples per character
## at a constant level, so tests can recognise what was stitched; a `whole` request is one
## part, whole_clip() of the whole text's tone. With `hold`, parts wait for release().

const RATE: int = 1000
const LEN_PER_CHAR: int = 10
const LEVEL: int = 12000

## Every request: {"voice", "id", "text", "settings", "whole"} (shared across spies of a factory).
var log: Array[Dictionary] = []
var hold: bool = false
## takes_settings() (false: like PiperBinarySynth, only start()'s defaults apply).
var per_request_settings: bool = true
var started_with: Dictionary = {}
var started: bool = false
var stopped: bool = false

var _held: Array[Dictionary] = []
var _parts: Array[Dictionary] = []


func _init(name: String, shared_log: Array[Dictionary]) -> void:
	voice = name
	log = shared_log


func start(defaults: Dictionary = {}) -> Error:
	started = true
	started_with = defaults
	return OK


func request(id: int, text: String, settings: Dictionary = {}, whole: bool = false) -> void:
	log.append({"voice": voice, "id": id, "text": text, "settings": settings, "whole": whole})
	var sentences: PackedStringArray = PiperBinarySynth.split_sentences(text)
	var parts: Array[Dictionary] = []
	if whole:
		parts.append(
			VoiceSynth.make_part(
				id, 0, true, VoiceSynth.whole_clip(tone(text.length() * LEN_PER_CHAR), RATE), RATE
			)
		)
		sentences = PackedStringArray()
	for i: int in sentences.size():
		parts.append(
			VoiceSynth.make_part(
				id, i, i == sentences.size() - 1, tone(sentences[i].length() * LEN_PER_CHAR), RATE
			)
		)
	if hold:
		_held.append_array(parts)
	else:
		_parts.append_array(parts)


## Hands over every held part.
func release() -> void:
	_parts.append_array(_held)
	_held.clear()


func take_parts() -> Array[Dictionary]:
	var out: Array[Dictionary] = _parts
	_parts = []
	return out


func pending() -> int:
	return _held.size()


func takes_settings() -> bool:
	return per_request_settings


func stop() -> void:
	stopped = true


static func tone(samples: int, level: int = LEVEL) -> PackedByteArray:
	var pcm: PackedByteArray = PackedByteArray()
	pcm.resize(samples * 2)
	for i: int in samples:
		pcm.encode_s16(i * 2, level)
	return pcm
