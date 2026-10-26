class_name HelmTable
extends SimTable
## Helm's flight-control state per ship (T028, promoted from S5's S5HelmState): mode,
## throttle setpoint, the latched stick and holds, the latched assist modes and the
## selected target. Commands write it (HelmInputCommand and the edge commands);
## AssistSystem reads it each tick and turns it into thrust. Assist tuning is read from
## the ship's AssistDef (world.defs[id].assist), never copied or changed.

## Align stage (FT-HLM-007, D124): OFF, roll the target to 12 o'clock, or roll and face it.
enum Align { OFF, ROLL, ROLL_AND_FACE }
## What is selected: nothing, a ship (contact; moving targets are ships), a point in the
## cube (a mark) or a named site (D229).
enum Target { NONE, SHIP, POINT, SITE }
## What a jump aims at: a named site or a free point (JumpCommand).
enum JumpKind { SITE, MARK }

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
## Ship-frame direction Align brings onto the target: the bow, or a mount's rest direction
## (AlignCommand.mount_index, FT-JNT-005). Read while align is not OFF.
var align_bow: PackedVector3Array = PackedVector3Array()
## 1 while align_bow is a mount's direction (no roll), 0 for the bow. Explicit, because a
## mount may face straight ahead, like the bow.
var align_mount: PackedByteArray = PackedByteArray()
## Selected target kind, a Target value.
var target_kind: PackedByteArray = PackedByteArray()
## Selected ship id when target_kind is SHIP, else -1.
var target_ship: PackedInt32Array = PackedInt32Array()
## 64-bit offset in the cube of the selected point (m, D104).
var target_x: PackedFloat64Array = PackedFloat64Array()
var target_y: PackedFloat64Array = PackedFloat64Array()
var target_z: PackedFloat64Array = PackedFloat64Array()
## Selected site id when target_kind is SITE, else -1 (FT-HLM-016).
var target_site: PackedInt32Array = PackedInt32Array()
## Ticks of spool left before the jump (FT-SIM-034); 0 when no jump is under way.
var jump_left: PackedInt32Array = PackedInt32Array()
## What the jump aims at, a JumpKind, with the site id (SITE, else -1) and the 64-bit point
## in the cube (MARK; the site's point for SITE) it was commanded to.
var jump_kind: PackedByteArray = PackedByteArray()
var jump_target: PackedInt32Array = PackedInt32Array()
var jump_x: PackedFloat64Array = PackedFloat64Array()
var jump_y: PackedFloat64Array = PackedFloat64Array()
var jump_z: PackedFloat64Array = PackedFloat64Array()
## Site id the ship is docked at, or -1 (FT-HLM-013).
var docked_site: PackedInt32Array = PackedInt32Array()


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
	align_bow.append(Vector3.FORWARD)
	align_mount.append(0)
	target_kind.append(Target.NONE)
	target_ship.append(-1)
	target_x.append(0.0)
	target_y.append(0.0)
	target_z.append(0.0)
	target_site.append(-1)
	jump_left.append(0)
	jump_kind.append(JumpKind.SITE)
	jump_target.append(-1)
	jump_x.append(0.0)
	jump_y.append(0.0)
	jump_z.append(0.0)
	docked_site.append(-1)


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
			["align_bow", align_bow],
			["align_mount", align_mount],
			["target_kind", target_kind],
			["target_ship", target_ship],
			["target_x", target_x],
			["target_y", target_y],
			["target_z", target_z],
			["target_site", target_site],
			["jump_left", jump_left],
			["jump_kind", jump_kind],
			["jump_target", jump_target],
			["jump_x", jump_x],
			["jump_y", jump_y],
			["jump_z", jump_z],
			["docked_site", docked_site],
		]
	)
