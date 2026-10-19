class_name VoiceFixture
extends RefCounted
## Test data for the host voice service: a prerender directory written like
## tools/tts/prerender.py's output (DIR/<lang>/<role>.pcm and .json), with every clip a
## run of CLIP_SAMPLES samples at its own level, so a stitched clip can be read back as a
## sequence of keys; and a spy synth factory.

const CLIP_SAMPLES: int = 20
const FIRST_LEVEL: int = 1000

## key -> level, per lang and role, of the last write().
var levels: Dictionary = {}
var dir: String = ""
## Every request any spy saw, in order.
var log: Array[Dictionary] = []
## voice -> SpyVoiceSynth made by factory().
var spies: Dictionary = {}
var hold: bool = false
## Voices factory() returns null for (a missing model).
var missing: PackedStringArray = []


func _init(path: String) -> void:
	dir = path


## Writes the host blobs the prerender would make for `lang` from the real dialogue JSON
## (audio/prerendered_host): seg:<id>:<k> and every num:<key>, in both roles.
func write(lang: String) -> void:
	var dialogue: DialogueLines = DialogueLines.load_dir()
	var numbers: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/dialogue/numbers.json")
	)
	var fragments: Dictionary = numbers["languages"][lang]["fragments"]
	var by_role: Dictionary = {"computer": PackedStringArray(), "npc": PackedStringArray()}
	for id: String in dialogue.lines:
		var line: Dictionary = dialogue.line(id)
		var keys: PackedStringArray = by_role[line["role"]]
		if (line.get("slots", {}) as Dictionary).is_empty():
			continue
		var pieces: PackedStringArray = DialogueLines.pieces(line["text"][lang])
		for k: int in pieces.size():
			if VoiceSynth.has_letter(pieces[k]):
				keys.append("seg:%s:%d" % [id, k])
	levels[lang] = {}
	for role: String in by_role:
		var keys: PackedStringArray = by_role[role]
		for key: String in fragments:
			keys.append("num:" + key)
		var clips: Dictionary = {}
		var pcm: PackedByteArray = PackedByteArray()
		var role_levels: Dictionary = {}
		for i: int in keys.size():
			var level: int = FIRST_LEVEL + i + (0 if role == "computer" else 5000)
			clips[keys[i]] = [i * CLIP_SAMPLES, CLIP_SAMPLES]
			role_levels[level] = keys[i]
			pcm.append_array(SpyVoiceSynth.tone(CLIP_SAMPLES, level))
		levels[lang][role] = role_levels
		DirAccess.make_dir_recursive_absolute(dir.path_join(lang))
		var base: String = dir.path_join(lang).path_join(role)
		var f: FileAccess = FileAccess.open(base + ".pcm", FileAccess.WRITE)
		f.store_buffer(pcm)
		f.close()
		var index: Dictionary = {"rate": SpyVoiceSynth.RATE, "voice": "spy", "clips": clips}
		f = FileAccess.open(base + ".json", FileAccess.WRITE)
		f.store_string(JSON.stringify(index))
		f.close()


## Removes the directory tree.
func clean() -> void:
	_remove(dir)


func factory() -> Callable:
	return func(voice: String) -> VoiceSynth:
		if missing.has(voice):
			return null
		var spy: SpyVoiceSynth = SpyVoiceSynth.new(voice, log)
		spy.hold = hold
		spies[voice] = spy
		return spy


## A stitched clip read back: one entry per run between 70 ms gaps, the clip key for a
## prerendered piece or "name:<chars>" for a synthesised (normalised) name.
func decode(lang: String, role: String, pcm: PackedByteArray) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var samples: int = pcm.size() / 2
	var i: int = 0
	var role_levels: Dictionary = levels[lang][role]
	while i < samples:
		var v: int = pcm.decode_s16(i * 2)
		if v == 0:
			i += 1
			continue
		var j: int = i
		while j < samples and pcm.decode_s16(j * 2) == v:
			j += 1
		if role_levels.has(v):
			# Adjacent prerendered clips of one piece have different levels, so each run
			# is one clip.
			out.append(role_levels[v])
		else:
			out.append("name:%d" % ((j - i) / SpyVoiceSynth.LEN_PER_CHAR))
		i = j
	return out


static func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d: String in DirAccess.get_directories_at(path):
		_remove(path.path_join(d))
	for f: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)
