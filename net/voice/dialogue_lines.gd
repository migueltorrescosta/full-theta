class_name DialogueLines
extends RefCounted
## The authored dialogue lines (content/dialogue/*.json, audio/README.md) by id, and the
## slot helpers the host uses to fill and stitch them. A slot is `{name}` in a line's
## text, declared in `slots` as a kind (`ship_name`, `callsign`, `npc_name`, `number`)
## or as {"kind": ..., "feminine": [languages]} for numbers.

const DEFAULT_DIR: String = "res://content/dialogue"
## The closed-set slot kinds, synthesised at Start (FT-AUD-018).
const NAME_KINDS: PackedStringArray = ["ship_name", "callsign", "npc_name"]
# --- strand G2 ---
## The text-only slot kind (FT-MIS-039): the subtitle carries the player's current binding of
## the slot's intent, which only the client knows; nothing voices it. fill() leaves
## `{binding:<intent>}` in the text for the client to resolve (BindingText.fill_markers).
const BINDING_KIND: String = "binding"
# --- end strand G2 ---

static var _slot: RegEx

## id -> line Dictionary as in the JSON.
var lines: Dictionary = {}


## Loads every lines file in `dir` (not the schemas, not numbers.json).
static func load_dir(dir: String = DEFAULT_DIR) -> DialogueLines:
	var out: DialogueLines = DialogueLines.new()
	for file: String in DirAccess.get_files_at(dir):
		if not file.ends_with(".json") or file.ends_with(".schema.json"):
			continue
		if file == "numbers.json":
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + "/" + file))
		if not data is Dictionary or not (data as Dictionary).get("lines") is Array:
			push_warning("DialogueLines: %s/%s has no lines" % [dir, file])
			continue
		out.add_lines(data["lines"])
	return out


## Adds lines from memory (tests, and load_dir).
func add_lines(list: Array) -> void:
	for line: Variant in list:
		if line is Dictionary and (line as Dictionary).get("id") is String:
			lines[line["id"]] = line


## The line, or {} for an unknown id.
func line(id: String) -> Dictionary:
	return lines.get(id, {})


## The literal pieces of a template split at its slots, empty pieces kept: piece k is
## the prerendered clip `seg:<id>:<k>` when it holds a letter (tools/tts/prerender.py).
static func pieces(template: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var at: int = 0
	for m: RegExMatch in _slot_re().search_all(template):
		out.append(template.substr(at, m.get_start() - at))
		at = m.get_end()
	out.append(template.substr(at))
	return out


## The slot names of a template, in order (one per gap between pieces).
static func slot_order(template: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for m: RegExMatch in _slot_re().search_all(template):
		out.append(m.get_string(1))
	return out


## A slot's kind ("" when the line doesn't declare it).
static func slot_kind(line_data: Dictionary, slot: String) -> String:
	var spec: Variant = (line_data.get("slots", {}) as Dictionary).get(slot, "")
	if spec is Dictionary:
		return str((spec as Dictionary).get("kind", ""))
	return str(spec)


## True when a number slot counts a feminine noun in `lang` (pt_PT "duas", it "una").
static func is_feminine(line_data: Dictionary, slot: String, lang: String) -> bool:
	var spec: Variant = (line_data.get("slots", {}) as Dictionary).get(slot, "")
	return spec is Dictionary and Array((spec as Dictionary).get("feminine", [])).has(lang)


## The template with its slots filled from args (numbers as whole numbers), in one pass
## over the template: a value holding `{slot}` stays as it is.
static func fill(line_data: Dictionary, template: String, args: Dictionary) -> String:
	var out: String = ""
	var at: int = 0
	for m: RegExMatch in _slot_re().search_all(template):
		var slot: String = m.get_string(1)
		var v: Variant = args.get(slot, "")
		out += template.substr(at, m.get_start() - at)
		if slot_kind(line_data, slot) == BINDING_KIND:  # strand G2
			out += "{%s:%s}" % [BINDING_KIND, binding_intent(line_data, slot)]
		else:
			out += str(int(v)) if slot_kind(line_data, slot) == "number" else str(v)
		at = m.get_end()
	return out + template.substr(at)


# --- strand G2 ---
## The IntentTable id a binding slot shows ("" for any other slot).
static func binding_intent(line_data: Dictionary, slot: String) -> String:
	var spec: Variant = (line_data.get("slots", {}) as Dictionary).get(slot, "")
	if spec is Dictionary:
		return str((spec as Dictionary).get("intent", ""))
	return ""


## Whether the line has a slot a voice has to say (a name or a number): a line with none,
## binding slots aside, is one prerendered clip the clients play themselves.
static func has_voiced_slots(line_data: Dictionary) -> bool:
	for slot: String in line_data.get("slots", {}) as Dictionary:
		if slot_kind(line_data, slot) != BINDING_KIND:
			return true
	return false


# --- end strand G2 ---


static func _slot_re() -> RegEx:
	if _slot == null:
		_slot = RegEx.create_from_string("\\{([a-z][a-z0-9_]*)\\}")
	return _slot
