class_name KinSection
extends SnapshotSection
## Own-ship kinematics (Section.KIN), absolute every snapshot (25 B): position
## 3 x s32 (1/16 m, wrapped), velocity 3 x s16, orientation u32 (smallest three),
## angular velocity 3 x s8. Camera, radar centre and the frame for NEAR/PROJECTILES.

var _last: PackedByteArray = PackedByteArray()


func update(world: SimWorld) -> PackedByteArray:
	var kin: Kinematics = world.kin
	var p_units: int = NetCodec.period_units(kin.period)
	var at: PackedFloat64Array = kin.point_at(owner, Vector3.ZERO)
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	NetCodec.put3_32(buf, NetCodec.quant_pos(at[0], at[1], at[2], p_units))
	NetCodec.put3_16(buf, NetCodec.quant_vel(kin.vel[owner]))
	buf.put_u32(NetCodec.pack_quat(kin.rot[owner]))
	NetCodec.put3_8(buf, NetCodec.quant_ang(kin.ang_vel[owner]))
	_last = buf.data_array
	return _last


func full() -> PackedByteArray:
	return _last


## Client side: {"pos" (Vector3i units), "vel" (Vector3i), "rot" (Quaternion),
## "ang" (Vector3i)}.
static func read(buf: StreamPeerBuffer) -> Dictionary:
	return {
		"pos": NetCodec.get3_32(buf),
		"vel": NetCodec.get3_16(buf),
		"rot": NetCodec.unpack_quat(buf.get_u32()),
		"ang": NetCodec.get3_8(buf),
	}
