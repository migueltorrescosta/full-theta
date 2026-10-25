class_name HackTable
extends SimTable
## Open hack windows (FT-SCI-008, P7): one row per hacked subsystem, keyed by the
## HACKED ship id and the HACKING ship's faction. Rows come and go as windows open and
## close, so reset_ship is overridden. HackSystem-side effects are applied by
## ScienceSystem.step, which writes DamageTable.hack_scale from these rows.

## Index of the subsystem in the hacked ship's ShipDef.subsystems.
var subsystem: PackedInt32Array = PackedInt32Array()
## Effectiveness multiplier while open (0..1).
var factor: PackedFloat64Array = PackedFloat64Array()
## Tick the window closes on (exclusive).
var until_tick: PackedInt32Array = PackedInt32Array()
## Ship that hacked.
var by: PackedInt32Array = PackedInt32Array()


func add_ship(_ship_id: int, _faction: int, _def: ShipDef) -> void:
	pass


func columns() -> Array:
	return (
		super()
		+ [
			["subsystem", subsystem],
			["factor", factor],
			["until_tick", until_tick],
			["by", by],
		]
	)


## Opens a window, or renews the same hacker faction's window on that subsystem.
func open(ship_id: int, faction: int, sub_index: int, eff: float, until: int, hacker: int) -> void:
	for r: int in size():
		if ship_ids[r] == ship_id and factions[r] == faction and subsystem[r] == sub_index:
			factor[r] = eff
			until_tick[r] = until
			by[r] = hacker
			return
	add_key(ship_id, faction)
	subsystem.append(sub_index)
	factor.append(eff)
	until_tick.append(until)
	by.append(hacker)


func remove_row(r: int) -> void:
	ship_ids.remove_at(r)
	factions.remove_at(r)
	subsystem.remove_at(r)
	factor.remove_at(r)
	until_tick.remove_at(r)
	by.remove_at(r)


## A reset ship loses the windows on it and the ones it opened.
func reset_ship(ship_id: int, _def: ShipDef) -> void:
	var r: int = size() - 1
	while r >= 0:
		if ship_ids[r] == ship_id or by[r] == ship_id:
			remove_row(r)
		r -= 1
