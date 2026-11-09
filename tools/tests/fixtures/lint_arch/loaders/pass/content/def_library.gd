class_name DefLibrary
extends RefCounted


func read(path: String) -> String:
	return FileAccess.get_file_as_string(path)
