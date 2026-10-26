class_name ConversationLibrary
extends RefCounted
## Loads the Comms conversations (content/conversations/**/*.json, FT-DAT-003) as plain
## data for SimWorld.conversations: id -> the file's Dictionary. The sim never reads JSON
## (contracts.md section 5); tools/check_dialogue.py has checked the files.

const DEFAULT_DIR: String = "res://content/conversations"


## Every conversation under dir, recursively (not the schema).
static func load_dir(dir: String = DEFAULT_DIR) -> Dictionary[StringName, Dictionary]:
	var out: Dictionary[StringName, Dictionary] = {}
	for sub: String in DirAccess.get_directories_at(dir):
		out.merge(load_dir(dir.path_join(sub)))
	for file: String in DirAccess.get_files_at(dir):
		if not file.ends_with(".json") or file.ends_with(".schema.json"):
			continue
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(file)))
		if data is Dictionary and (data as Dictionary).get("id") is String:
			out[StringName(data["id"])] = data
		else:
			push_warning("ConversationLibrary: %s/%s is not a conversation" % [dir, file])
	return out
