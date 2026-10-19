extends RefCounted
## Seeded Godot --check-only failure: an untyped declaration (FT-ARC-002).


func twice(value: int) -> int:
	var doubled = value * 2
	return doubled
