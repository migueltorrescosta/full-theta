class_name SetShieldCommand
extends SimCommand
## Engineering sets total shield power and focus tightness (FT-SIM-018, FT-ENG-003, D16).

## Shield pips (count); exactly -1 keeps them, other negatives are rejected.
var power: int = -1
## Focus tightness (dimensionless, ShieldDef range); exactly -1 keeps it, other
## negatives are rejected.
var tightness: float = -1.0


func kind() -> StringName:
	return &"set_shield"


func apply(world: SimWorld) -> bool:
	return ShieldSystem.set_power_and_tightness(world, ship_id, power, tightness)
