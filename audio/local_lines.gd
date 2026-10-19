class_name LocalLines
extends RefCounted
## Prerendered lines played on the client (D152): a `voice_line` with `local` true plays
## `<dir>/<lang>/<line_id>.ogg` (Ogg Vorbis, one file per line, listed in
## `<dir>/<lang>/index.json`). Exports import the files, so they load as resources; in a
## development tree before an import they are read from disk. A missing file gives null,
## and the line shows its subtitle only. The line id and language come off the wire, so
## both are checked before they become a path: a line id must match the dialogue schema's
## id pattern and the language must be a launch language (I18n.LANGUAGES); anything else
## gives null too.

## PROVISIONAL: where the prerender writes the client's clips.
const CLIP_DIR: String = "res://audio/prerendered"
## content/dialogue/dialogue.schema.json's line id pattern.
const LINE_ID_PATTERN: String = "^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)+$"

var lang: String
var dir: String
var _cache: Dictionary = {}  # line id -> AudioStream (or null)
var _line_id: RegEx = RegEx.create_from_string(LINE_ID_PATTERN)


func _init(language: String, base_dir: String = CLIP_DIR) -> void:
	lang = language
	dir = base_dir


func path(line_id: String) -> String:
	return "%s/%s/%s.ogg" % [dir, lang, line_id]


## Whether `line_id` and the language are safe to build a path from.
func valid(line_id: String) -> bool:
	if lang not in I18n.LANGUAGES:
		return false
	var m: RegExMatch = _line_id.search(line_id)
	return m != null and m.get_string() == line_id  # `$` also matches before a final \n


## The line's stream, or null when it has none (or its id or language is invalid).
func stream(line_id: String) -> AudioStream:
	if not valid(line_id):
		return null
	if not _cache.has(line_id):
		_cache[line_id] = _load(path(line_id))
	return _cache[line_id]


func _load(file: String) -> AudioStream:
	if ResourceLoader.exists(file):
		return load(file) as AudioStream
	if FileAccess.file_exists(file):
		return AudioStreamOggVorbis.load_from_file(file)
	return null
