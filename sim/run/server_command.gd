class_name ServerCommand
extends SimCommand
## A run-wide command from the server (E07, D103): the Scenario API's writes and the run's
## own rules (spawn, open a site, flags, relations, encounters). It names no ship
## (ship_id -1), so SimWorld applies it even when no ship is alive, and it applies to the
## world, not a ship. Its source is SERVER, so it is logged and a replay reproduces the run
## from the command log alone (FT-ARC-008).


func _init() -> void:
	source = Source.SERVER


func applies_to_destroyed() -> bool:
	return true
