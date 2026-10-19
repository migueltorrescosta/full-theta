class_name KnowledgeSystem
extends RefCounted
## Per-faction detection (T034). Stub until its task lands.


static func step(_world: SimWorld) -> void:
	pass


## Whether the faction currently detects the ship (FT-ARC-013).
static func is_detected(_world: SimWorld, _faction: int, _ship_id: int) -> bool:
	return true


## The callsign the faction uses for the ship, for example "H2" (FT-SPA-001, FT-SPA-002).
static func callsign(_world: SimWorld, _faction: int, _ship_id: int) -> String:
	return ""
