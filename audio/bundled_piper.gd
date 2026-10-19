class_name BundledPiper
extends RefCounted
## Finds the Piper program and voices a release package carries (FT-ARC-022,
## TECH-4) and synthesises one line with them (the L6 smoke test, FT-TST-019).
## Packages ship rhasspy/piper 2023.11.14-2, a standalone program (no Python);
## docs/release.md and tools/release/piper.json pin it. Layout
## (tools/release/package.py):
##   Linux, Windows: <exe dir>/piper/piper[.exe], <exe dir>/piper/espeak-ng-data/,
##                   <exe dir>/piper/voices/<voice>/<voice>.onnx(.json)
##   macOS:          Contents/Helpers/piper/piper (with its dylibs),
##                   Contents/Resources/piper/espeak-ng-data/ and voices/
## The runtime voice processes (E10, FT-ARC-019) use the same paths.


## Paths for an executable at `executable` on the given platform; all "" when
## `executable` is "".
static func paths_for(executable: String, os_name: String) -> Dictionary:
	var paths: Dictionary = {"program": "", "data": "", "voices": ""}
	if executable == "":
		return paths
	var dir: String = executable.get_base_dir()
	var data: String = dir.path_join("piper")
	var program: String = data.path_join("piper")
	if os_name == "macOS":
		data = dir.path_join("../Resources/piper").simplify_path()
		program = dir.path_join("../Helpers/piper/piper").simplify_path()
	elif os_name == "Windows":
		program += ".exe"
	paths["program"] = program
	paths["data"] = data.path_join("espeak-ng-data")
	paths["voices"] = data.path_join("voices")
	return paths


## This build's paths; all "" when running from a checkout (development uses the
## tools/tts environment instead).
static func paths() -> Dictionary:
	var exe: String = OS.get_executable_path() if OS.has_feature("template") else ""
	return paths_for(exe, OS.get_name())


## Voice names the package carries (sorted), from the voices folder.
static func voices() -> PackedStringArray:
	var dir: String = paths()["voices"]
	var names: PackedStringArray = []
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return names
	for name: String in DirAccess.get_directories_at(dir):
		if FileAccess.file_exists(dir.path_join(name).path_join(name + ".onnx")):
			names.append(name)
	names.sort()
	return names


## The command line that writes each line given on stdin as a WAV file in
## `out_dir`, printing that file's path on stdout.
static func command(p: Dictionary, voice: String, out_dir: String) -> PackedStringArray:
	var model: String = (p["voices"] as String).path_join(voice).path_join(voice + ".onnx")
	return ["--model", model, "--espeak_data", p["data"], "--output_dir", out_dir, "--quiet"]


## Synthesises `text` with the bundled `voice` into `wav_path`; returns the
## process exit code, or -1 when there is no bundled Piper or voice. Blocks:
## for the smoke test and tools only, never on the sim thread.
static func synthesise(text: String, voice: String, wav_path: String) -> int:
	var p: Dictionary = paths()
	if p["program"] == "" or not FileAccess.file_exists(p["program"]):
		push_error("no bundled Piper at '%s'" % p["program"])
		return -1
	if not voices().has(voice):
		push_error("no bundled voice %s (have %s)" % [voice, ", ".join(voices())])
		return -1
	var out_dir: String = wav_path.get_base_dir()
	var pipe: Dictionary = OS.execute_with_pipe(p["program"], command(p, voice, out_dir), true)
	if pipe.is_empty():
		push_error("could not start %s" % p["program"])
		return -1
	# One line in; Piper answers with the WAV's path once it is written. Closing
	# the pipe then ends its input, and it exits.
	var stdio: FileAccess = pipe["stdio"]
	stdio.store_string(text.replace("\n", " ") + "\n")
	stdio.flush()
	var written: String = stdio.get_line().strip_edges()
	stdio.close()
	var pid: int = pipe["pid"]
	while OS.is_process_running(pid):
		OS.delay_msec(20)
	var code: int = OS.get_process_exit_code(pid)
	if written == "" or not FileAccess.file_exists(written):
		push_error("Piper wrote no WAV (exit %d)" % code)
		return code if code != 0 else 1
	DirAccess.remove_absolute(wav_path)
	return code if DirAccess.rename_absolute(written, wav_path) == OK else 1
