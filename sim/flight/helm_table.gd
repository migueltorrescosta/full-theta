class_name HelmTable
extends SimTable
## Helm's flight-control state per ship (T028, promoted from S5's S5HelmState): mode,
## throttle setpoint, the latched stick and holds, the latched assist modes and the
## selected target. Commands write it (HelmInputCommand and the edge commands);
## AssistSystem reads it each tick and turns it into thrust. Assist tuning is read from
## the ship's AssistDef (world.defs[id].assist), never copied or changed.

## Align stage (FT-HLM-007, D124): OFF, roll the target to 12 o'clock, or roll and face it.
enum Align { OFF, ROLL, ROLL_AND_FACE }
## What is selected: nothing, a ship (contact; moving targets are ships) or a
## site-local point (a mark or a site).
enum Target { NONE, SHIP, POINT }

## 1 in decoupled mode, which turns the holds off (FT-SIM-005); 0, assist on, is the
## default (FT-SIM-004).
var decoupled: PackedByteArray = PackedByteArray()
## Forward speed setpoint the assist holds (m/s; negative is astern): throttle sets
## speed, not force (FT-SIM-004).
var throttle_setpoint: PackedFloat64Array = PackedFloat64Array()
## Latched rotation stick, each axis in [-1, 1]: x pitch (nose up +), y yaw (nose to
## port +), z roll (to port +), the right-hand rotations about the body axes.
var input_rotation: PackedVector3Array = PackedVector3Array()
## Latched translation input, each in [-1, 1]: x strafe (starboard +), y lift (up +),
## z throttle (forward +). With assist, throttle ramps the setpoint; decoupled, it fires
## the main drive or the retro thrusters directly.
var input_translation: PackedVector3Array = PackedVector3Array()
## 1 while face is held (FT-HLM-005).
var face_held: PackedByteArray = PackedByteArray()
## 1 while hold-to-approach is held (FT-SIM-037).
var approach_held: PackedByteArray = PackedByteArray()
## 1 while all-stop is latched (FT-SIM-036): until at rest or manual input.
var all_stop: PackedByteArray = PackedByteArray()
## Align stage, an Align value; it works on the selected target.
var align: PackedByteArray = PackedByteArray()
## Selected target kind, a Target value.
var target_kind: PackedByteArray = PackedByteArray()
## Selected ship id when target_kind is SHIP, else -1.
var target_ship: PackedInt32Array = PackedInt32Array()
## Site of the selected point when target_kind is POINT, else -1.
var target_site: PackedInt32Array = PackedInt32Array()
## Site-local 64-bit offset of the selected point (m, D104).
var target_x: PackedFloat64Array = PackedFloat64Array()
var target_y: PackedFloat64Array = PackedFloat64Array()
var target_z: PackedFloat64Array = PackedFloat64Array()


func add_ship(ship_id: int, faction: int, _def: ShipDef) -> void:
	add_key(ship_id, faction)
	decoupled.append(0)
	throttle_setpoint.append(0.0)
	input_rotation.append(Vector3.ZERO)
	input_translation.append(Vector3.ZERO)
	face_held.append(0)
	approach_held.append(0)
	all_stop.append(0)
	align.append(Align.OFF)
	target_kind.append(Target.NONE)
	target_ship.append(-1)
	target_site.append(-1)
	target_x.append(0.0)
	target_y.append(0.0)
	target_z.append(0.0)


func is_decoupled(row: int) -> bool:
	return decoupled[row] == 1


func columns() -> Array:
	return (
		super()
		+ [
			["decoupled", decoupled],
			["throttle_setpoint", throttle_setpoint],
			["input_rotation", input_rotation],
			["input_translation", input_translation],
			["face_held", face_held],
			["approach_held", approach_held],
			["all_stop", all_stop],
			["align", align],
			["target_kind", target_kind],
			["target_ship", target_ship],
			["target_site", target_site],
			["target_x", target_x],
			["target_y", target_y],
			["target_z", target_z],
		]
	)
