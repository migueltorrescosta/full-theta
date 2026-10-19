class_name LocalLines
extends RefCounted
## Prerendered lines played on the client (D152): a `voice_line` with `local` true plays
## `<dir>/<lang>/<line_id>.ogg` (Ogg Vorbis, one file per line, listed in
## `<dir>/<lang>/index.json`). Exports import the files, so they load as resources; in a
## development tree before an import they are read from disk. A missing file gives null,
## and the line shows its subtitle only.

## PROVISIONAL: where the prerender writes the client's clips.
const CLIP_DIR: String = "res://audio/prerendered"

var lang: String
var dir: String
var _cache: Dictionary = {}  # line id -> AudioStream (or null)


func _init(language: String, base_dir: String = CLIP_DIR) -> void:
	lang = language
	dir = base_dir


func path(line_id: String) -> String:
	return "%s/%s/%s.ogg" % [dir, lang, line_id]


## The line's stream, or null when it has none.
func stream(line_id: String) -> AudioStream:
	if not _cache.has(line_id):
		_cache[line_id] = _load(path(line_id))
	return _cache[line_id]


func _load(file: String) -> AudioStream:
	if ResourceLoader.exists(file):
		return load(file) as AudioStream
	if FileAccess.file_exists(file):
		return AudioStreamOggVorbis.load_from_file(file)
	return null
