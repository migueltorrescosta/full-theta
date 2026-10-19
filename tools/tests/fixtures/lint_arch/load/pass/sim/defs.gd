extends RefCounted

func f(cfg: ConfigLike) -> void:
	cfg.load("res://content/ship.tres")  # a method named load is fine
