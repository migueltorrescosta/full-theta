class_name PowerTable
extends SimTable
## Boost and weapons energy, one row per ship in id order (T030, FT-SIM-006). Per-subsystem
## power state (pips, heat, fault_armed) lives on the subsystem rows of DamageTable.

## Ticks of boost left; 0 when not boosting (P1).
var boost_ticks: PackedInt32Array = PackedInt32Array()
## Energy in the weapons store (J), drawn per shot.
var weapon_energy: PackedFloat64Array = PackedFloat64Array()

## Derived cache, not state: per ship and envelope (engines, thrusters), the last
## inputs of PowerSystem.envelope (pip ratio, effectiveness, heat ratio; NAN before
## any) and its result (envelope_of).
var _env_in: PackedFloat64Array = PackedFloat64Array()
var _env: PackedFloat64Array = PackedFloat64Array()


func add_ship(ship_id: int, faction: int, def: ShipDef) -> void:
	add_key(ship_id, faction)
	boost_ticks.append(0)
	weapon_energy.append(def.power.weapons_capacity)
	for k: int in 6:
		_env_in.append(NAN)
	_env.append_array([1.0, 1.0])


## PowerSystem.envelope(power, pip_ratio, effectiveness, heat_ratio) for the ship's
## envelope k (0 engines, 1 thrusters), recomputed only when an input changed (the
## ship's PowerDef is fixed).
func envelope_of(
	row: int, k: int, power: PowerDef, pip_ratio: float, effectiveness: float, heat_ratio: float
) -> float:
	var i: int = 6 * row + 3 * k
	if pip_ratio != _env_in[i] or effectiveness != _env_in[i + 1] or heat_ratio != _env_in[i + 2]:
		_env_in[i] = pip_ratio
		_env_in[i + 1] = effectiveness
		_env_in[i + 2] = heat_ratio
		_env[2 * row + k] = PowerSystem.envelope(power, pip_ratio, effectiveness, heat_ratio)
	return _env[2 * row + k]


func columns() -> Array:
	return (
		super()
		+ [
			["boost_ticks", boost_ticks],
			["weapon_energy", weapon_energy],
		]
	)
