extends Control

func f() -> void:
	var f: FileAccess = FileAccess.open("user://x", FileAccess.READ)
	print(OS.get_name())
