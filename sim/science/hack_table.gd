class_name HackTable
extends SimTable
## Open hack windows (FT-SCI-008, P7): one row per hacked subsystem and hacking faction.
## The row is the hacker's: `owner_ship` is the ship that hacked and `owner_faction` its
## faction; `subject_ship` is the HACKED ship (D404). Rows come and go as windows open and
## close, so reset_ship is overridden. HackSystem-side effects are applied by
## ScienceSystem.step, which writes DamageTable.hack_scale from these rows.

## The hacked ship.
var subject_ship: PackedInt32Array = PackedInt32Array()
## Index of the subsystem in the hacked ship's ShipDef.subsystems.
var subsystem: PackedInt32Array = PackedInt32Array()
## Effectiveness multiplier while open (0..1).
var factor: PackedFloat64Array = PackedFloat64Array()
## Tick the window closes on (exclusive).
var until_tick: PackedInt32Array = PackedInt32Array()


func add_ship(_ship_id: int, _faction: int, _def: ShipDef) -> void:
	pass


## Opens the hacker's window on the subject's subsystem, or renews its faction's window
## there (the renewing hacker then owns it).
func open(subject: int, faction: int, sub_index: int, eff: float, until: int, hacker: int) -> void:
	for r: int in size():
		if subject_ship[r] == subject and owner_faction[r] == faction and subsystem[r] == sub_index:
			owner_ship[r] = hacker
			factor[r] = eff
			until_tick[r] = until
			return
	add_key(hacker, faction)
	subject_ship.append(subject)
	subsystem.append(sub_index)
	factor.append(eff)
	until_tick.append(until)


## A reset ship loses the windows on it and the ones it opened.
func reset_ship(ship_id: int, _def: ShipDef) -> void:
	var r: int = size() - 1
	while r >= 0:
		if subject_ship[r] == ship_id or owner_ship[r] == ship_id:
			remove_rows(PackedInt32Array([r]))
		r -= 1
