class_name DamageTable
extends SimTable
## Per-part state: hull and subsystem health, spare parts and repair crews (T033,
## FT-SIM-020, FT-SIM-021, FT-SIM-024), and the power pips, heat and fault state
## PowerSystem keeps per subsystem (T030, FT-SIM-026). Each ship owns a contiguous block
## of rows: first its hull row (part &"hull"), then one row per subsystem in
## ShipDef.subsystems order. The hull row's health is the hull (J) and its spare_parts is
## the ship's stock; subsystem rows keep spare_parts at 0. The power columns are 0 on
## the hull row. Repair crews are numbered 0..repair_crews-1 and identified by bit
## index: crews[row] on a subsystem row is the mask of crews working there (always 0 on
## the hull row); a crew in no mask is idle.

const HULL: StringName = &"hull"
## Crews are bits of a 32-bit mask (ShipDef.validate caps repair_crews at this).
const MAX_CREWS: int = 31

## &"hull" on the hull row, the subsystem id on subsystem rows.
var part_ids: Array[StringName] = []
## Hull or subsystem health (J), 0..its maximum in the definition.
var health: PackedFloat64Array = PackedFloat64Array()
## Spare parts in stock (count) on the hull row; 0 on subsystem rows.
var spare_parts: PackedInt32Array = PackedInt32Array()
## Mask of repair crews assigned to a subsystem row (bit c = crew c).
var crews: PackedInt32Array = PackedInt32Array()
## Pips Engineering set on a subsystem (count); their sum over the ship stays within
## PowerDef.reactor_pips (FT-ENG-002). A boost overrides engines and thrusters.
var pips: PackedInt32Array = PackedInt32Array()
## Subsystem heat: temperature rise above nominal (K, FT-SIM-026).
var heat: PackedFloat64Array = PackedFloat64Array()
## 1 while a heat fault may fire on the subsystem; 0 after one fired, until the heat
## falls back below PowerSystem.FAULT_REARM of the threshold.
var fault_armed: PackedByteArray = PackedByteArray()

## Derived cache, not state: per row, the product of the open hack windows' effectiveness
## factors (1 with none), written by ScienceSystem.step from HackTable (FT-SCI-008, P7).
var hack_scale: PackedFloat64Array = PackedFloat64Array()
## Derived: hack_scale may hold a factor other than 1, so step() must rewrite it.
var hack_dirty: bool = false

## Derived index, not state: first (hull) row by ship id, set at spawn (rows never move).
var _first: PackedInt32Array = PackedInt32Array()
## Derived cache, not state: per row, the health the effectiveness curve was last
## sampled at (NAN before any) and the result (DamageSystem.row_effectiveness).
var _eff_health: PackedFloat64Array = PackedFloat64Array()
var _eff: PackedFloat64Array = PackedFloat64Array()


func add_ship(ship_id: int, faction: int, def: ShipDef) -> void:
	var r: int = add_key(ship_id, faction)
	while _first.size() <= ship_id:
		_first.append(-1)
	_first[ship_id] = r
	part_ids.append(HULL)
	health.append(def.hull_max)
	spare_parts.append(def.spare_parts)
	crews.append(0)
	pips.append(0)
	heat.append(0.0)
	fault_armed.append(0)
	_eff_health.append(NAN)
	_eff.append(1.0)
	hack_scale.append(1.0)
	for s: SubsystemDef in def.subsystems:
		add_key(ship_id, faction)
		part_ids.append(s.id)
		health.append(s.health_max)
		spare_parts.append(0)
		crews.append(0)
		pips.append(s.nominal_pips)
		heat.append(0.0)
		fault_armed.append(1)
		_eff_health.append(NAN)
		_eff.append(1.0)
		hack_scale.append(1.0)


func columns() -> Array:
	return (
		super()
		+ [
			["part_ids", part_ids],
			["health", health],
			["spare_parts", spare_parts],
			["crews", crews],
			["pips", pips],
			["heat", heat],
			["fault_armed", fault_armed],
		]
	)


## Effectiveness of subsystem row r with definition s (FT-SIM-021): its curve at the
## row's health fraction, cached per row by health (the curve is the row's own, fixed).
func row_effectiveness(r: int, s: SubsystemDef) -> float:
	var h: float = health[r]
	if h != _eff_health[r]:
		_eff_health[r] = h
		_eff[r] = PowerSystem.curve_at(s.effectiveness, h / s.health_max)
	return _eff[r] * hack_scale[r]


## The ship's hull row, or -1.
func hull_row(ship_id: int) -> int:
	return _first[ship_id] if ship_id >= 0 and ship_id < _first.size() else -1


## Row of the ship's subsystem with that index in ShipDef.subsystems; the caller passes
## a valid index.
func subsystem_row(ship_id: int, index: int) -> int:
	return hull_row(ship_id) + 1 + index


## Row of the ship's subsystem with that id, or -1 (never the hull row).
func find_subsystem(ship_id: int, subsystem_id: StringName) -> int:
	var h: int = hull_row(ship_id)
	if h < 0 or subsystem_id == HULL:
		return -1
	var r: int = h + 1
	while r < size() and ship_ids[r] == ship_id:
		if part_ids[r] == subsystem_id:
			return r
		r += 1
	return -1
