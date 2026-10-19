class_name VoiceSynth
extends RefCounted
## One synthesis voice behind a thin adapter (FT-AUD-019): VoiceService queues requests
## and collects finished parts, and never waits on synthesis. The Piper adapters
## (PiperStreamSynth for tools/tts/piper_stream.py, PiperBinarySynth for the standalone
## rhasspy/piper binary) run one persistent process each, driven by a worker thread
## (FT-ARC-019); tests subclass this with a spy.
##
## A part is {"id": int, "part": int, "last": bool, "pcm": PackedByteArray (16-bit mono
## little endian), "rate": int, "error": String}. A request's parts come in order; the
## one with `last` ends it and may hold no PCM. A failed request ends with an error part
## (`last` true, no PCM), so the caller treats it as subtitles only.

## Settings keys a request may carry (voices.json `roles`).
const SETTING_KEYS: PackedStringArray = ["length_scale", "noise_scale", "noise_w_scale"]

## The voice's name (voices.json, tools/tts/voices.json key).
var voice: String = ""


## Starts the voice. `defaults` are settings applied to the whole process by adapters
## that can't take them per request (PiperBinarySynth); others ignore them.
func start(_defaults: Dictionary = {}) -> Error:
	return OK


## Queues a request; never blocks. `settings` holds any of SETTING_KEYS.
func request(_id: int, _text: String, _settings: Dictionary = {}) -> void:
	pass


## Parts finished since the last call, oldest first.
func take_parts() -> Array[Dictionary]:
	return []


## Requests queued or being synthesised.
func pending() -> int:
	return 0


## True once the voice is loaded and warmed up.
func is_ready() -> bool:
	return true


## Stops the voice and its process; pending requests are dropped.
func stop() -> void:
	pass


## A part dictionary (see the class comment).
static func make_part(
	id: int, part: int, last: bool, pcm: PackedByteArray, rate: int, error: String = ""
) -> Dictionary:
	return {"id": id, "part": part, "last": last, "pcm": pcm, "rate": rate, "error": error}


## True when text holds a letter (or, with digits, a digit): something a voice speaks.
static func has_letter(text: String, digits: bool = false) -> bool:
	for c: String in text:
		if c.to_lower() != c.to_upper() or (digits and c.is_valid_int()):
			return true
	return false
