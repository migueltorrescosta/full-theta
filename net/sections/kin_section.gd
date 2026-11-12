class_name KinSection
extends SnapshotSection
## Own-ship kinematics (Section.KIN), absolute every snapshot (25 B): position
## 3 x s32 (1/16 m, wrapped), velocity 3 x s16, orientation u32 (smallest three),
## angular velocity 3 x s8. Camera, radar centre and the frame for NEAR/PROJECTILES.


func update(world: SimWorld) -> PackedByteArray:
	var kin: Kinematics = world.kin
	var p_units: int = NetCodec.period_units(kin.period)
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	NetCodec.put3_32(buf, NetCodec.quant_pos(kin.point(owner), p_units))
	NetCodec.put3_16(buf, NetCodec.quant_vel(kin.vel[owner]))
	buf.put_u32(NetCodec.pack_quat(kin.rot[owner]))
	NetCodec.put3_8(buf, NetCodec.quant_ang(kin.ang_vel[owner]))
	_last = buf.data_array
	return _last
