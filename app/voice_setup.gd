class_name VoiceSetup
extends RefCounted
## Composes the host's VoiceService (E10): where the prerendered clips are, and the synth
## factory that picks a Piper adapter per voice. It lives in app/ because it names
## audio/ and the development tools (tools/tts), which net/ may not (spec §2.2).
##
## - Exported build (`OS.has_feature("template")`): the bundled rhasspy/piper
##   2023.11.14-2 binary through PiperBinarySynth, with the paths from BundledPiper
##   (audio/bundled_piper.gd, packaging strand), found at runtime through the global class
##   list, so this script compiles without it. No BundledPiper, or a voice its voices()
##   doesn't list: no synth, and VoiceService makes those lines subtitles only.
## - Development: FT_PIPER_BIN forces the binary adapter (espeak data from FT_PIPER_DATA,
##   else espeak-ng-data next to the binary); otherwise PiperStreamSynth runs
##   tools/tts/piper_stream.py (piper-tts 1.8.0) with the tools/tts venv's Python,
##   resolved once, FT_PIPER_PYTHON overriding it. Models come from the fetch_voices.py
##   cache: $FT_PIPER_CACHE or ~/.cache/full-theta/piper, <voice>/<voice>.onnx.

## The host's blobs: segments and number fragments only (seg:*, num:*).
const CLIP_DIR: String = "res://audio/prerendered_host"
const BUNDLED_CLASS: String = "BundledPiper"
const BIN_ENV: String = "FT_PIPER_BIN"
const DATA_ENV: String = "FT_PIPER_DATA"
const PYTHON_ENV: String = "FT_PIPER_PYTHON"
const CACHE_ENV: String = "FT_PIPER_CACHE"
const WRAPPER: String = "res://tools/tts/piper_stream.py"
const VENV: String = "res://tools/tts/.venv"

static var _python: String = ""
static var _python_resolved: bool = false

## True in an exported build: use the bundled binary only. Static, like make(), so the
## factory Callable stays valid (a Callable doesn't keep a RefCounted alive); tests
## override these and call reset().
static var exported: bool = OS.has_feature("template")
## Callable() -> Object with static paths() and voices() (BundledPiper's API), or null;
## tests inject a stub.
static var bundled_lookup: Callable = find_bundled


## Restores the defaults (tests).
static func reset() -> void:
	exported = OS.has_feature("template")
	bundled_lookup = find_bundled


## The host's voice service, events at tick_source's tick.
static func make_service(transport: NetTransport, tick_source: Callable) -> VoiceService:
	var voice: VoiceService = VoiceService.new(transport, make)
	voice.clip_dir = CLIP_DIR
	voice.tick_source = tick_source
	return voice


## The synth factory: a VoiceSynth for the voice (not started), or null.
static func make(voice: String) -> VoiceSynth:
	if exported:
		return _bundled(voice)
	var model: String = cache_dir().path_join(voice).path_join(voice + ".onnx")
	if not FileAccess.file_exists(model):
		push_warning("voice %s: no model at %s; its lines are subtitles only" % [voice, model])
		return null
	var binary: String = OS.get_environment(BIN_ENV)
	if binary != "":
		var data: String = OS.get_environment(DATA_ENV)
		if data == "":
			data = binary.get_base_dir().path_join("espeak-ng-data")
		if not FileAccess.file_exists(binary):
			push_warning("%s=%s does not exist; voice lines are subtitles only" % [BIN_ENV, binary])
			return null
		return PiperBinarySynth.new(binary, data, model, voice)
	var py: String = python()
	var wrapper: String = ProjectSettings.globalize_path(WRAPPER)
	if py == "" or not FileAccess.file_exists(wrapper):
		push_warning("voice %s: no Piper (set %s or %s)" % [voice, BIN_ENV, PYTHON_ENV])
		return null
	return PiperStreamSynth.new(py, wrapper, model, voice)


## BundledPiper's script from the global class list, or null when the build has none.
static func find_bundled() -> Object:
	for c: Dictionary in ProjectSettings.get_global_class_list():
		if c["class"] == BUNDLED_CLASS:
			return load(c["path"])
	return null


## The voice model cache directory (as tools/tts/fetch_voices.py).
static func cache_dir() -> String:
	var dir: String = OS.get_environment(CACHE_ENV)
	if dir != "":
		return dir
	var home: String = OS.get_environment("HOME")
	if home == "":
		home = OS.get_environment("USERPROFILE")
	return home.path_join(".cache").path_join("full-theta").path_join("piper")


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


static func _bundled(voice: String) -> VoiceSynth:
	var bundled: Object = bundled_lookup.call()
	if bundled == null:
		push_warning("no bundled Piper in this build; voice lines are subtitles only")
		return null
	if not Array(bundled.call("voices")).has(voice):
		push_warning("voice %s is not bundled; its lines are subtitles only" % voice)
		return null
	var paths: Dictionary = bundled.call("paths")
	var model: String = str(paths["voices"]).path_join(voice).path_join(voice + ".onnx")
	return PiperBinarySynth.new(str(paths["program"]), str(paths["data"]), model, voice)
