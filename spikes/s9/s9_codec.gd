class_name S9Codec
extends RefCounted
## S9 spike codec helpers: fixed-point quantisation, integer dead reckoning
## (bit-exact on server and client, so deltas can carry residuals), and
## smallest-three quaternions. Buffers are little-endian StreamPeerBuffers.
##
## Units: positions 1/16 m in int32 (site-local offsets up to 134 km per
## axis), velocities 1/64 m/s in int16 (up to 512 m/s), angular velocities
## 1/100 rad/s in int8, projectile velocities 1/8 m/s in int16.

const POS_Q: float = 16.0
const VEL_Q: float = 64.0
const ANG_Q: float = 100.0
const PROJ_VEL_Q: float = 8.0
const TICK_HZ: int = 60
## Velocity units times ticks over this gives position units: VEL_Q * TICK_HZ / POS_Q.
const PRED_DEN: int = 240
const PRED_K: Vector3i = Vector3i(131072, 131072, 131072)
const PRED_OFF: Vector3i = Vector3i(62914800, 62914800, 62914800)
const SQRT1_2: float = 0.7071067811865476
## Field modes in a kinematic record's flag byte.
const POS_NONE: int = 0
const POS_S8: int = 1
const POS_S16: int = 2
const POS_ABS: int = 3
const VEL_SAME: int = 0
const VEL_S8: int = 1
const VEL_ABS: int = 2


static func quant_pos(p: Vector3) -> Vector3i:
	return Vector3i((p * POS_Q).round())


static func quant_vel(v: Vector3) -> Vector3i:
	return Vector3i((v * VEL_Q).round()).clampi(-32767, 32767)


static func quant_ang(w: Vector3) -> Vector3i:
	return Vector3i((w * ANG_Q).round()).clampi(-127, 127)


static func pos_of(p: Vector3i) -> Vector3:
	return Vector3(p) / POS_Q


static func vel_of(v: Vector3i) -> Vector3:
	return Vector3(v) / VEL_Q


static func ang_of(w: Vector3i) -> Vector3:
	return Vector3(w) / ANG_Q


## Floor division for b > 0 (GDScript's `/` truncates towards zero).
static func floor_div(a: int, b: int) -> int:
	var q: int = a / b
	if a % b != 0 and a < 0:
		q -= 1
	return q


static func round_div(a: int, b: int) -> int:
	return floor_div(2 * a + b, 2 * b)


## Dead-reckoned position after `dt` ticks (0 <= dt <= 600), in integer units
## on both ends: p + round(v dt / PRED_DEN), rounding half up. Vector3i is
## int32 and its division truncates, so the numerator is shifted positive by
## PRED_K * 2 PRED_DEN first (|2 v dt| < 4e7 < PRED_K * 480).
static func predict(p: Vector3i, v: Vector3i, dt: int) -> Vector3i:
	return p + (v * (2 * dt) + PRED_OFF) / (2 * PRED_DEN) - PRED_K


static func max_abs(v: Vector3i) -> int:
	return maxi(maxi(absi(v.x), absi(v.y)), absi(v.z))


## Smallest three in 32 bits: 2 bits for the largest component's index, then
## the other three in 10 bits each over [-1/sqrt 2, 1/sqrt 2].
static func pack_quat(q: Quaternion) -> int:
	var c: Array[float] = [q.x, q.y, q.z, q.w]
	var big: int = 0
	for i: int in range(1, 4):
		if absf(c[i]) > absf(c[big]):
			big = i
	var sign_value: float = -1.0 if c[big] < 0.0 else 1.0
	var out: int = big << 30
	var shift: int = 20
	for i: int in range(4):
		if i == big:
			continue
		var u: float = (c[i] * sign_value / SQRT1_2) * 0.5 + 0.5
		out |= clampi(roundi(u * 1023.0), 0, 1023) << shift
		shift -= 10
	return out


static func unpack_quat(bits: int) -> Quaternion:
	var big: int = (bits >> 30) & 3
	var c: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var shift: int = 20
	var sum: float = 0.0
	for i: int in range(4):
		if i == big:
			continue
		var v: float = (((bits >> shift) & 1023) / 1023.0 - 0.5) * 2.0 * SQRT1_2
		c[i] = v
		sum += v * v
		shift -= 10
	c[big] = sqrt(maxf(0.0, 1.0 - sum))
	return Quaternion(c[0], c[1], c[2], c[3]).normalized()


## Body-frame angular velocity applied for `dt` ticks (as S6 integrates it).
static func extrapolate_rot(q: Quaternion, w: Vector3, dt: int) -> Quaternion:
	var rate: float = w.length()
	if rate < 1.0e-6 or dt <= 0:
		return q
	return q * Quaternion(w / rate, rate * dt / float(TICK_HZ))


## Writes one kinematic record: id u16, flags u8 (pos mode | vel mode << 2),
## the position (residual against `pred`, or absolute) and the velocity
## (unchanged, residual against `base_v`, or absolute).
static func put_kin(
	buf: StreamPeerBuffer,
	id: int,
	p: Vector3i,
	v: Vector3i,
	pred: Vector3i,
	base_v: Vector3i,
	absolute: bool
) -> void:
	var pos_mode: int = POS_ABS
	var err: Vector3i = p - pred
	if not absolute:
		var e: int = max_abs(err)
		pos_mode = POS_S8 if e <= 127 else (POS_S16 if e <= 32767 else POS_ABS)
	var vel_mode: int = VEL_ABS
	var dv: Vector3i = v - base_v
	if not absolute:
		var e: int = max_abs(dv)
		vel_mode = VEL_SAME if e == 0 else (VEL_S8 if e <= 127 else VEL_ABS)
	buf.put_u16(id)
	buf.put_u8(pos_mode | (vel_mode << 2))
	match pos_mode:
		POS_S8:
			_put3_8(buf, err)
		POS_S16:
			_put3_16(buf, err)
		_:
			buf.put_32(p.x)
			buf.put_32(p.y)
			buf.put_32(p.z)
	match vel_mode:
		VEL_S8:
			_put3_8(buf, dv)
		VEL_ABS:
			_put3_16(buf, v)


## Reads a record written by put_kin; returns [id, p, v].
static func get_kin(buf: StreamPeerBuffer, pred_of: Dictionary, tick: int) -> Array:
	var id: int = buf.get_u16()
	var flags: int = buf.get_u8()
	var pos_mode: int = flags & 3
	var vel_mode: int = (flags >> 2) & 3
	var base_p: Vector3i = Vector3i.ZERO
	var base_v: Vector3i = Vector3i.ZERO
	if pos_mode != POS_ABS or vel_mode != VEL_ABS:
		var entry: Array = pred_of[id]
		base_v = entry[1]
		base_p = predict(entry[0], base_v, tick - int(entry[2]))
	var p: Vector3i
	match pos_mode:
		POS_S8:
			p = base_p + _get3_8(buf)
		POS_S16:
			p = base_p + _get3_16(buf)
		_:
			p = Vector3i(buf.get_32(), buf.get_32(), buf.get_32())
	var v: Vector3i = base_v
	match vel_mode:
		VEL_S8:
			v = base_v + _get3_8(buf)
		VEL_ABS:
			v = _get3_16(buf)
	return [id, p, v]


static func _put3_8(buf: StreamPeerBuffer, v: Vector3i) -> void:
	buf.put_8(v.x)
	buf.put_8(v.y)
	buf.put_8(v.z)


static func _put3_16(buf: StreamPeerBuffer, v: Vector3i) -> void:
	buf.put_16(v.x)
	buf.put_16(v.y)
	buf.put_16(v.z)


static func _get3_8(buf: StreamPeerBuffer) -> Vector3i:
	return Vector3i(buf.get_8(), buf.get_8(), buf.get_8())


static func _get3_16(buf: StreamPeerBuffer) -> Vector3i:
	return Vector3i(buf.get_16(), buf.get_16(), buf.get_16())
