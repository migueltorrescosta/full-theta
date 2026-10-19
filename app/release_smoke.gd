class_name ReleaseSmoke
extends RefCounted
## L6 smoke test of an exported build (FT-TST-019, tools/l6/run.sh):
##   <exe> --headless -- --tts-smoke TEXT --out WAV [--voice NAME]
## synthesises TEXT with the package's bundled Piper (BundledPiper) and exits 0
## when the WAV was written. Without --voice it uses the first bundled voice.


static func handles(args: PackedStringArray) -> bool:
	return args.has("--tts-smoke")


## Runs the smoke test; returns the process exit code.
static func run(args: PackedStringArray) -> int:
	var opts: Dictionary = parse(args)
	if opts.is_empty():
		push_error("usage: --tts-smoke TEXT --out /ABSOLUTE/WAV [--voice NAME]")
		return 2
	var voices: PackedStringArray = BundledPiper.voices()
	print("tts-smoke: bundled voices %s" % ", ".join(voices))
	var voice: String = opts["voice"]
	if voice == "" and not voices.is_empty():
		voice = voices[0]
	var code: int = BundledPiper.synthesise(opts["text"], voice, opts["out"])
	var size: int = 0
	if FileAccess.file_exists(opts["out"]):
		size = FileAccess.get_file_as_bytes(opts["out"]).size()
	print("tts-smoke: voice %s exit %d wav %d bytes" % [voice, code, size])
	# A WAV header alone is 44 bytes; one spoken line is tens of kilobytes.
	return 0 if code == 0 and size > 1000 else 1


## {"text", "out", "voice"} from the command line, or {} when TEXT is missing or
## WAV is not an absolute path.
static func parse(args: PackedStringArray) -> Dictionary:
	var opts: Dictionary = {"text": "", "out": "", "voice": ""}
	var flags: Dictionary = {"--tts-smoke": "text", "--out": "out", "--voice": "voice"}
	var i: int = 0
	while i < args.size():
		if flags.has(args[i]) and i + 1 < args.size():
			opts[flags[args[i]]] = args[i + 1]
			i += 1
		i += 1
	# Relative paths would resolve against res:// in an export.
	if opts["text"] == "" or not (opts["out"] as String).is_absolute_path():
		return {}
	return opts
