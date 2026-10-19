extends RefCounted

func f() -> void:
	var f: FileAccess = FileAccess.open("user://x", FileAccess.READ)
	DirAccess.make_dir_absolute("user://y")
	print(OS.get_name())
