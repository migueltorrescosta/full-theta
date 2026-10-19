class_name S9Own
extends RefCounted
## Own-ship sections of one ship. KIND_OWN goes to every view of the ship: the
## ship's kinematics every snapshot (camera and radar centre) and the top-bar
## status block when it changes. KIND_ENG goes to Engineering only: the
## subsystem table when it changes. S6 has no ship systems, so both blocks are
## stand-ins of a realistic size that change twice a second and on each hit.

const KIND_OWN: int = 1
const KIND_ENG: int = 5
const STATUS_BYTES: int = 16
## 8 subsystems x (power, heat, damage, coolant, crew, fault).
const ENG_BYTES: int = 48

var ship: int = 0
var hits: int = 0
var status: PackedByteArray = PackedByteArray()
var eng: PackedByteArray = PackedByteArray()
var _kin: PackedByteArray = PackedByteArray()
var _status_changed: bool = true
var _eng_changed: bool = true
var _stamp: Vector2i = Vector2i(-1, -1)


func _init(own_ship: int) -> void:
	ship = own_ship


## Recomputes the blocks for `tick`; returns [own delta, eng delta].
func update(world: S9World, tick: int) -> Array[PackedByteArray]:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	var p: Vector3i = S9Codec.quant_pos(world.ship_pos(ship))
	buf.put_32(p.x)
	buf.put_32(p.y)
	buf.put_32(p.z)
	var v: Vector3i = S9Codec.quant_vel(world.ship_vel(ship))
	buf.put_16(v.x)
	buf.put_16(v.y)
	buf.put_16(v.z)
	buf.put_u32(S9Codec.pack_quat(world.ship_rot(ship)))
	var w: Vector3i = S9Codec.quant_ang(world.ship_ang(ship))
	buf.put_8(w.x)
	buf.put_8(w.y)
	buf.put_8(w.z)
	_kin = buf.data_array
	var phase: int = tick / 30
	var stamp: Vector2i = Vector2i(phase, hits)
	_status_changed = stamp != _stamp
	_eng_changed = _status_changed
	if _status_changed:
		_stamp = stamp
		status = _block(STATUS_BYTES, phase, hits)
		eng = _block(ENG_BYTES, phase * 7 + 1, hits)
	return [_own_bytes(_status_changed), _eng_bytes(_eng_changed)]


func full_own() -> PackedByteArray:
	return _own_bytes(true)


func full_eng() -> PackedByteArray:
	return _eng_bytes(true)


## Client side: into = {"kin": PackedByteArray, "status": ..., "eng": ...}.
static func apply(into: Dictionary, kind: int, data: PackedByteArray) -> void:
	var has_block: bool = data[0] & 1 == 1
	if kind == KIND_OWN:
		into["kin"] = data.slice(1, 26)
		if has_block:
			into["status"] = data.slice(26)
	elif has_block:
		into["eng"] = data.slice(1)


func _own_bytes(with_status: bool) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray([1 if with_status else 0])
	out.append_array(_kin)
	if with_status:
		out.append_array(status)
	return out


func _eng_bytes(with_table: bool) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray([1 if with_table else 0])
	if with_table:
		out.append_array(eng)
	return out


## Deterministic filler that changes with `phase` and `salt`.
static func _block(size: int, phase: int, salt: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	out.resize(size)
	for i: int in range(size):
		out[i] = (phase * 31 + salt * 17 + i * 13) & 0xFF
	return out
