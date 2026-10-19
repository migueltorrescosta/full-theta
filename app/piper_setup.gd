class_name PiperSetup
extends RefCounted
## Picks and configures the Piper adapter for a voice: the synth factory ServerMain gives
## VoiceService (make()). It lives in app/ because it names the development tools
## (tools/tts), which net/ may not (spec §2.2).
##
## - FT_PIPER_BIN set: PiperBinarySynth with that rhasspy/piper 2023.11.14-2 binary
##   (what releases ship, TECH-4).
## - Otherwise: PiperStreamSynth, tools/tts/piper_stream.py run by the tools/tts venv's
##   Python (piper-tts 1.8.0, development), resolved once; FT_PIPER_PYTHON overrides it.
## - Voice models: <cache>/<voice>/<voice>.onnx, the tools/tts/fetch_voices.py cache,
##   $FT_PIPER_CACHE or ~/.cache/full-theta/piper. A missing model gives no synth (null),
##   and VoiceService makes that voice's lines subtitles only.

const BIN_ENV: String = "FT_PIPER_BIN"
const PYTHON_ENV: String = "FT_PIPER_PYTHON"
const CACHE_ENV: String = "FT_PIPER_CACHE"
const WRAPPER: String = "res://tools/tts/piper_stream.py"
const VENV: String = "res://tools/tts/.venv"

static var _python: String = ""
static var _python_resolved: bool = false


## The default synth factory: a VoiceSynth for the voice (not started), or null.
static func make(voice: String) -> VoiceSynth:
	var model: String = model_path(voice)
	if not FileAccess.file_exists(model):
		push_warning("voice %s: no model at %s; its lines are subtitles only" % [voice, model])
		return null
	var binary: String = OS.get_environment(BIN_ENV)
	if binary != "":
		if not FileAccess.file_exists(binary):
			push_warning("%s=%s does not exist; voice lines are subtitles only" % [BIN_ENV, binary])
			return null
		return PiperBinarySynth.new(binary, model, voice)
	var py: String = python()
	var wrapper: String = ProjectSettings.globalize_path(WRAPPER)
	if py == "" or not FileAccess.file_exists(wrapper):
		push_warning("voice %s: no Piper (set %s or %s)" % [voice, BIN_ENV, PYTHON_ENV])
		return null
	return PiperStreamSynth.new(py, wrapper, model, voice)


## The voice model cache directory (as tools/tts/fetch_voices.py).
static func cache_dir() -> String:
	var dir: String = OS.get_environment(CACHE_ENV)
	if dir != "":
		return dir
	var home: String = OS.get_environment("HOME")
	if home == "":
		home = OS.get_environment("USERPROFILE")
	return home.path_join(".cache").path_join("full-theta").path_join("piper")


static func model_path(voice: String) -> String:
	return cache_dir().path_join(voice).path_join(voice + ".onnx")


## The Python that runs the wrapper: $FT_PIPER_PYTHON, else the tools/tts venv's
## interpreter (asked of uv once if the venv isn't there yet); "" when there is none.
static func python() -> String:
	if _python_resolved:
		return _python
	_python_resolved = true
	_python = OS.get_environment(PYTHON_ENV)
	if _python != "":
		return _python
	var venv: String = ProjectSettings.globalize_path(VENV)
	for candidate: String in ["bin/python", "Scripts/python.exe"]:
		if FileAccess.file_exists(venv.path_join(candidate)):
			_python = venv.path_join(candidate)
			return _python
	if OS.has_feature("template"):
		return _python
	var out: Array = []
	var project: String = ProjectSettings.globalize_path("res://tools/tts")
	var code: int = OS.execute(
		"uv",
		["run", "--project", project, "python", "-c", "import sys; print(sys.executable)"],
		out
	)
	if code == 0 and not out.is_empty():
		var lines: PackedStringArray = str(out[0]).strip_edges().split("\n")
		_python = lines[lines.size() - 1].strip_edges()
	return _python
