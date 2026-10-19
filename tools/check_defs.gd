extends SceneTree
## Definition load gate (FT-DAT-002): loads every .tres under a root (default
## res://content), checks each property against its declared type, finds missing
## references, and runs validate() on every definition reached, sub-resources and
## referenced files included. Prints "<file>: <field>: <problem>" per error and exits 1
## on any.
##   godot --headless --path . -s res://tools/check_defs.gd [-- <root dir>]
##
## Godot drops a wrongly typed value on load without an error (the field keeps its
## default) and refuses to load a file whose ext_resource is missing, so both checks
## read the .tres text: each `key = value` is compared with the type the section's
## script declares, and each ext_resource path must exist.

const REF: String = '(Ext|Sub)Resource\\("([^"]+)"\\)'
const SKIP_KEYS: PackedStringArray = ["script", "resource_name", "resource_local_to_scene"]


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var root: String = args[0] if args.size() > 0 else "res://content"
	var errors: PackedStringArray = check_root(root)
	for e: String in errors:
		print(e)
	print("check_defs: %s: %d error(s)" % [root, errors.size()])
	quit(1 if errors.size() > 0 else 0)


## Every error under root, as "<file>: <field>: <problem>" lines (file relative to res://).
static func check_root(root: String) -> PackedStringArray:
	var errors: PackedStringArray = PackedStringArray()
	var queue: PackedStringArray = DefLibrary.list_tres(root)
	if queue.is_empty():
		errors.append("%s: (root): no .tres files found" % _rel(root))
	var checked: Dictionary[String, bool] = {}
	var validated: Dictionary[int, bool] = {}
	while not queue.is_empty():
		var path: String = queue[0]
		queue.remove_at(0)
		if checked.has(path):
			continue
		checked[path] = true
		# Referenced files outside root are checked too.
		for ref: String in _check_file(path, errors, validated):
			if not checked.has(ref):
				queue.append(ref)
	return errors


## Checks one file; returns the .tres files it references.
static func _check_file(
	path: String, errors: PackedStringArray, validated: Dictionary[int, bool]
) -> PackedStringArray:
	var file: String = _rel(path)
	var parsed: Dictionary = _parse(FileAccess.get_file_as_string(path))
	var exts: Dictionary = parsed.exts
	var missing: Dictionary[String, bool] = {}
	var refs: PackedStringArray = PackedStringArray()
	for ext_id: String in exts:
		var ext_path: String = exts[ext_id].get("path", "")
		if not _exists(ext_path, exts[ext_id].get("uid", "")):
			missing[ext_id] = true
		elif ext_path.get_extension() == "tres":
			refs.append(ext_path)
	var before: int = errors.size()
	for section: Dictionary in parsed.sections:
		_check_section(file, section, parsed, missing, errors)
	if errors.size() > before:
		return refs
	var res: Resource = load(path)
	if res == null:
		errors.append("%s: (file): failed to load" % file)
		return refs
	_validate_tree(res, errors, validated)
	return refs


static func _check_section(
	file: String,
	section: Dictionary,
	parsed: Dictionary,
	missing: Dictionary[String, bool],
	errors: PackedStringArray
) -> void:
	var prefix: String = "" if section.id == "" else "%s." % section.id
	var props: Dictionary = section.props
	var script: Script = null
	if props.has("script"):
		var sid: String = _ref_id(props.script)
		if missing.has(sid):
			errors.append(
				"%s: %sscript: missing reference %s" % [file, prefix, _ext_path(parsed, sid)]
			)
			return
		script = _ref_script(props.script, parsed)
	if script == null:
		if section.id == "":
			errors.append("%s: script: definition has no script" % file)
		return
	var declared: Dictionary = {}
	for info: Dictionary in (script as GDScript).new().get_property_list():
		if info.usage & PROPERTY_USAGE_STORAGE:
			declared[info.name] = info
	for key: String in props:
		if key in SKIP_KEYS or key.begins_with("metadata/"):
			continue
		var field: String = prefix + key
		if not declared.has(key):
			errors.append("%s: %s: unknown field for %s" % [file, field, script.get_global_name()])
			continue
		var problem: String = _type_problem(props[key], declared[key], parsed, missing)
		if problem != "":
			errors.append("%s: %s: %s" % [file, field, problem])


## Returns "" when the value text fits the declared property, else the problem.
static func _type_problem(
	text: String, info: Dictionary, parsed: Dictionary, missing: Dictionary[String, bool]
) -> String:
	var refs: Array[RegExMatch] = _regex(REF).search_all(text)
	for m: RegExMatch in refs:
		if m.get_string(1) == "Ext" and missing.has(m.get_string(2)):
			return "missing reference %s" % _ext_path(parsed, m.get_string(2))
	var type: int = info.type
	if text == "null":
		return "" if type == TYPE_OBJECT else "expected %s, got null" % type_string(type)
	if type == TYPE_OBJECT:
		if refs.size() != 1 or refs[0].get_string() != text:
			return "expected a %s reference, got %s" % [info.hint_string, text]
		return _class_problem(text, info.hint_string, parsed)
	# Exported typed arrays carry "<type>/<hint>:<class>" in a TYPE_STRING hint.
	if type == TYPE_ARRAY and info.hint in [PROPERTY_HINT_TYPE_STRING, PROPERTY_HINT_ARRAY_TYPE]:
		var cls: String = String(info.hint_string).get_slice(":", 1)
		if String(info.hint_string).begins_with("%d/" % TYPE_OBJECT):
			if not text.begins_with("Array[") and text != "[]":
				return "expected Array[%s], got %s" % [cls, text]
			var items: String = text.substr(text.find("(") + 1) if text.contains("(") else text
			for m: RegExMatch in _regex(REF).search_all(items):
				var p: String = _class_problem(m.get_string(), cls, parsed)
				if p != "":
					return "element %s" % p
			return ""
	if not refs.is_empty():
		return "expected %s, got a resource reference" % type_string(type)
	var value: Variant = str_to_var(text)
	var got: int = typeof(value)
	if value == null:
		return "unreadable value %s" % text
	if got == type or (type == TYPE_FLOAT and got == TYPE_INT):
		return ""
	if [type, got] in [[TYPE_STRING_NAME, TYPE_STRING], [TYPE_STRING, TYPE_STRING_NAME]]:
		return ""
	return "expected %s, got %s %s" % [type_string(type), type_string(got), text]


## Returns "" when the single reference in text is a resource of class cls.
static func _class_problem(text: String, cls: String, parsed: Dictionary) -> String:
	var script: Script = null
	var native: String = "Resource"
	var m: RegExMatch = _regex(REF).search(text)
	if m.get_string(1) == "Ext":
		var res: Resource = load(_ext_path(parsed, m.get_string(2)))
		if res == null:
			return "referenced file %s failed to load" % _ext_path(parsed, m.get_string(2))
		script = res as Script if res is Script else res.get_script()
		native = res.get_class()
	else:
		for section: Dictionary in parsed.sections:
			if section.id == m.get_string(2) and section.props.has("script"):
				script = _ref_script(section.props.script, parsed)
	var name: String = native
	while script != null:
		if script.get_global_name() == cls:
			return ""
		if name == native and script.get_global_name() != &"":
			name = script.get_global_name()
		script = script.get_base_script()
	if ClassDB.class_exists(cls) and ClassDB.is_parent_class(native, cls):
		return ""
	return "expected %s, got %s" % [cls, name]


## Runs validate() on res and every resource it references, once per resource.
static func _validate_tree(
	res: Resource, errors: PackedStringArray, validated: Dictionary[int, bool]
) -> void:
	if res == null or validated.has(res.get_instance_id()):
		return
	validated[res.get_instance_id()] = true
	if res.has_method("validate"):
		var file: String = _rel(res.resource_path.get_slice("::", 0))
		var sub: String = res.resource_path.get_slice("::", 1)
		var prefix: String = "%s." % sub if res.resource_path.contains("::") else ""
		for e: String in res.call("validate"):
			errors.append("%s: %s%s" % [file, prefix, e])
	for info: Dictionary in res.get_property_list():
		if not info.usage & PROPERTY_USAGE_STORAGE or info.name == "script":
			continue
		var value: Variant = res.get(info.name)
		if value is Resource:
			_validate_tree(value, errors, validated)
		elif value is Array:
			for item: Variant in value:
				if item is Resource:
					_validate_tree(item, errors, validated)


## Splits .tres text into ext_resources (id -> attributes) and sections ([resource] has
## id "", [sub_resource] its id), each with its `key = value` texts.
static func _parse(text: String) -> Dictionary:
	var exts: Dictionary = {}
	var sections: Array[Dictionary] = []
	var current: Dictionary = {}
	var last_key: String = ""
	var attr: RegEx = _regex('(\\w+)="([^"]*)"')
	var prop: RegEx = _regex("^([A-Za-z_][\\w/]*) = (.*)$")
	for line: String in text.split("\n"):
		if line.begins_with("[") and line.ends_with("]") and not line.begins_with("[["):
			var attrs: Dictionary = {}
			for m: RegExMatch in attr.search_all(line):
				attrs[m.get_string(1)] = m.get_string(2)
			current = {}
			if line.begins_with("[ext_resource"):
				exts[attrs.get("id", "")] = attrs
			elif line.begins_with("[sub_resource") or line.begins_with("[resource"):
				current = {"id": attrs.get("id", ""), "props": {}}
				sections.append(current)
			continue
		var m: RegExMatch = prop.search(line)
		if current.is_empty():
			continue
		if m != null:
			last_key = m.get_string(1)
			current.props[last_key] = m.get_string(2).strip_edges()
		elif last_key != "" and line.strip_edges() != "":
			current.props[last_key] += "\n" + line
	return {"exts": exts, "sections": sections}


static func _ref_id(text: String) -> String:
	var m: RegExMatch = _regex(REF).search(text)
	return m.get_string(2) if m != null else ""


static func _ref_script(text: String, parsed: Dictionary) -> Script:
	var path: String = _ext_path(parsed, _ref_id(text))
	return load(path) as Script if path != "" and ResourceLoader.exists(path) else null


static func _ext_path(parsed: Dictionary, ext_id: String) -> String:
	return parsed.exts.get(ext_id, {}).get("path", "")


## A reference resolves if its path exists or its uid names a known file.
static func _exists(path: String, uid: String) -> bool:
	if path != "" and ResourceLoader.exists(path):
		return true
	if uid == "":
		return false
	var id: int = ResourceUID.text_to_id(uid)
	return id != ResourceUID.INVALID_ID and ResourceUID.has_id(id)


static func _rel(path: String) -> String:
	return ProjectSettings.localize_path(path).trim_prefix("res://")


static func _regex(pattern: String) -> RegEx:
	var r: RegEx = RegEx.new()
	r.compile(pattern)
	return r
