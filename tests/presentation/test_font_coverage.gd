extends GdUnitTestSuite
## Every character the UI can show is in a bundled font: a browser has no system font to
## fall back on, so a gap draws as the missing-glyph box (the Android Firefox check).

const DIRS: Array[String] = [
	"res://app",
	"res://input",
	"res://net",
	"res://presentation",
	"res://shared",
	"res://stations",
	"res://content/i18n",
	"res://content/tips",
	"res://content/dialogue",
	"res://content/conversations",
]


## Every file under `dir` with a script or JSON suffix.
func _files(dir: String) -> Array[String]:
	var out: Array[String] = []
	for sub: String in DirAccess.get_directories_at(dir):
		out.append_array(_files(dir.path_join(sub)))
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd") or f.ends_with(".json"):
			out.append(dir.path_join(f))
	return out


## The text a file can put on screen: the whole of a JSON file, the string literals of a
## script (comments left out).
func _text(path: String) -> String:
	var src: String = FileAccess.get_file_as_string(path)
	if path.ends_with(".json"):
		return src
	var rx: RegEx = RegEx.create_from_string('"(?:[^"\\\\\\n]|\\\\.)*"')
	var out: String = ""
	for line: String in src.split("\n"):
		if line.strip_edges().begins_with("#"):
			continue
		for m: RegExMatch in rx.search_all(line):
			out += m.get_string()
	return out


# FT: FT-STN-006
func test_every_ui_character_is_in_a_bundled_font() -> void:
	var font: Font = UiTheme.font()
	var missing: Dictionary = {}
	var seen: int = 0
	for dir: String in DIRS:
		for path: String in _files(dir):
			var text: String = _text(path)
			for i: int in text.length():
				var code: int = text.unicode_at(i)
				if code < 128:
					continue
				seen += 1
				if not font.has_char(code):
					missing[String.chr(code)] = path
	assert_int(seen).is_greater(0)
	assert_dict(missing).is_empty()


# FT: FT-STN-006
func test_the_icon_glyphs_are_covered() -> void:
	var font: Font = UiTheme.font()
	for glyph: String in ["☰", "⇄", "▸", "▾", "⚡", "✓", "✕"]:
		assert_bool(font.has_char(glyph.unicode_at(0))).is_true()
