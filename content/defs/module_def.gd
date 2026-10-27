class_name ModuleDef
extends Resource
## A slot module (FT-MIS-035, FT-DAT-014, D86): an upgrade with a trade-off, bought while
## docked through Comms and fitted at once. Each delta is a fractional change of one
## ship stat (0.2 is 20 % more); ModuleSystem.refit applies the sum per stat to a copy of
## the ship's definition. A module must give something up: at least one delta is positive
## and one negative. Read-only at runtime (FT-ARC-020).

## The stats a delta may name. thrust and torque scale the whole envelope; reactor_output
## and weapons_capacity are the PowerDef's; heat_capacity raises how hot every subsystem
## may run before a fault (SubsystemDef.fault_heat_threshold); heat_dissipation and
## repair_rate are the subsystems'; shield_strength and shield_regen the ShieldDef's.
const STATS: Array[StringName] = [
	&"thrust",
	&"torque",
	&"mass",
	&"sensor_range",
	&"reactor_output",
	&"weapons_capacity",
	&"heat_capacity",
	&"heat_dissipation",
	&"repair_rate",
	&"shield_strength",
	&"shield_regen",
]

## Unique among modules (dimensionless id, for example hx2_drive).
@export var id: StringName = &""
## I18n key of the name shown on the offer card.
@export var name_key: String = ""
## The slot type it fits (SlotDef.slot_type).
@export var slot_type: StringName = &""
## (dimensionless, credits) Price when bought; selling pays MarketDef.sell_ratio of it.
@export var price: int = 0
## Stat -> fractional change (dimensionless).
@export var deltas: Dictionary[StringName, float] = {}


func validate() -> Array[String]:
	var errors: Array[String] = []
	DefCheck.id(errors, "id", id)
	DefCheck.id(errors, "slot_type", slot_type)
	if name_key.strip_edges().is_empty():
		errors.append("name_key: must not be empty")
	DefCheck.non_negative(errors, "price", price)
	var up: bool = false
	var down: bool = false
	for stat: StringName in deltas:
		if not STATS.has(stat):
			errors.append("deltas: unknown stat %s" % stat)
			continue
		var d: float = deltas[stat]
		if not (is_finite(d) and d > -1.0 and d != 0.0):
			errors.append("deltas.%s: must be finite, above -1 and not 0, got %s" % [stat, d])
		# mass is a cost when it grows.
		var gain: bool = d < 0.0 if stat == &"mass" else d > 0.0
		up = up or gain
		down = down or not gain
	if not (up and down):
		errors.append("deltas: needs at least one gain and one cost (a trade-off, FT-MIS-035)")
	return errors
