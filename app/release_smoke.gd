class_name ReleaseSmoke
extends RefCounted
## L6 smoke test of an exported build (FT-TST-019, tools/l6/run.sh):
##   <exe> --headless -- --tts-smoke TEXT --out /ABS/line.wav [--voice NAME]
## synthesises TEXT with the package's bundled Piper (BundledPiper) and exits 0
## when every WAV was written. Without --voice it uses every bundled voice, so
## each one is shown to load (D144), writing /ABS/line.<voice>.wav.


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
	var chosen: String = opts["voice"]
	var todo: PackedStringArray = [chosen] if chosen != "" else voices
	if todo.is_empty():
		push_error("no bundled voices")
		return 1
	var failed: int = 0
	for voice: String in todo:
		var out: String = opts["out"]
		if chosen == "":
			out = "%s.%s.wav" % [out.get_basename(), voice]
		var code: int = BundledPiper.synthesise(opts["text"], voice, out)
		var size: int = 0
		if FileAccess.file_exists(out):
			size = FileAccess.get_file_as_bytes(out).size()
		print("tts-smoke: voice %s exit %d wav %d bytes" % [voice, code, size])
		# A WAV header alone is 44 bytes; one spoken line is tens of kilobytes.
		if code != 0 or size <= 1000:
			failed += 1
	return 0 if failed == 0 else 1


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
