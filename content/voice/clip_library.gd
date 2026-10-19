class_name ClipLibrary
extends RefCounted
## Prerendered voice clips of one session language, read from the prerender output
## (tools/tts/prerender.py, audio/README.md): per role a blob of 16-bit mono PCM and an
## index {"rate", "voice", "clips": {key: [first_sample, samples]}}. Built at packaging
## time from the dialogue JSON and never committed (FT-AUD-002); exports include it, so
## clients play authored lines and the host stitches number fragments locally (D152).
## Keys: line:<id>, seg:<id>:<k>, num:<fragment>. Releases ship them in
## res://audio/prerendered/<lang>/; content/ can't name audio/ (spec §2.2), so the caller
## (VoicePlayer on clients, the app's voice setup on the host) passes the folder.

var lang: String = ""
## role -> {"rate": int, "voice": String, "clips": Dictionary, "pcm": PackedByteArray}
var _roles: Dictionary = {}


## Loads every role found for `language` under `dir`; roles with no files are absent
## (a language without a shipped voice, such as pt_PT before #16, gives an empty library).
static func load_dir(dir: String, language: String) -> ClipLibrary:
	var lib: ClipLibrary = ClipLibrary.new()
	lib.lang = language
	for role: String in ["computer", "npc"]:
		var base: String = "%s/%s/%s" % [dir, language, role]
		if not FileAccess.file_exists(base + ".json") or not FileAccess.file_exists(base + ".pcm"):
			continue
		var index: Variant = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
		if not index is Dictionary:
			push_warning("ClipLibrary: bad index %s.json" % base)
			continue
		var pcm: PackedByteArray = FileAccess.get_file_as_bytes(base + ".pcm")
		lib.add_role(
			role,
			int(index.get("rate", 0)),
			str(index.get("voice", "")),
			index.get("clips", {}),
			pcm
		)
	return lib


## Adds a role from memory (tests, and load_dir).
func add_role(
	role: String, rate: int, voice: String, clips: Dictionary, pcm: PackedByteArray
) -> void:
	_roles[role] = {"rate": rate, "voice": voice, "clips": clips, "pcm": pcm}


func has_role(role: String) -> bool:
	return _roles.has(role)


func has_clip(role: String, key: String) -> bool:
	return _roles.has(role) and (_roles[role]["clips"] as Dictionary).has(key)


## {"pcm": PackedByteArray, "rate": int}, or {} when the role or key is missing.
func clip(role: String, key: String) -> Dictionary:
	if not has_clip(role, key):
		return {}
	var r: Dictionary = _roles[role]
	var span: Array = r["clips"][key]
	var first: int = int(span[0]) * 2
	var size: int = int(span[1]) * 2
	return {"pcm": (r["pcm"] as PackedByteArray).slice(first, first + size), "rate": r["rate"]}


func rate(role: String) -> int:
	return int(_roles[role]["rate"]) if _roles.has(role) else 0


func keys(role: String) -> PackedStringArray:
	if not _roles.has(role):
		return PackedStringArray()
	return PackedStringArray((_roles[role]["clips"] as Dictionary).keys())
