class_name NetCodec
extends RefCounted
## Packed snapshot codec (T040, promoted from S9Codec): fixed-point quantisation,
## integer dead reckoning that server and client compute bit for bit, wrap-aware
## residuals, and smallest-three quaternions. Buffers are little-endian StreamPeerBuffers.
##
## Positions are offsets in the scenario's cube taken as 64-bit floats (D104) and quantised to
## 1/16 m in int32. The cube wraps with period P (D124, D125, D229): a quantised position
## lies in [-P_u / 2, P_u / 2) for P_u = P * POS_Q units, and every position
## difference (dead-reckoning residual, near-range test) is the minimum image, so a
## contact crossing a seam costs one small residual, not an absolute record.
##
## Units: positions 1/16 m (int32), velocities 1/16 m/s (int16, up to 2,048 m/s),
## angular velocities 1/50 rad/s (int8, up to 2.54 rad/s), projectile velocities
## 1/8 m/s (int16, up to 4,096 m/s).

const POS_Q: float = 16.0
const VEL_Q: float = 16.0
const ANG_Q: float = 50.0
const PROJ_VEL_Q: float = 8.0
const TICK_HZ: int = 60
## Velocity units times ticks over this gives position units: VEL_Q * TICK_HZ / POS_Q.
const PRED_DEN: int = 60
## Projectile velocity units times ticks over this gives position units.
const PROJ_PRED_DEN: int = 30
## Most ticks a dead-reckoned record may age before it is refreshed (10 s).
const MAX_AGE: int = 600
const SQRT1_2: float = 0.7071067811865476
## Field modes in a kinematic record's flag byte.
const POS_NONE: int = 0
const POS_S8: int = 1
const POS_S16: int = 2
const POS_ABS: int = 3
const VEL_SAME: int = 0
const VEL_S8: int = 1
const VEL_ABS: int = 2


## The cube's period P (m) in position units; P is a multiple of 500 m (D125), so even.
static func period_units(period: float) -> int:
	return roundi(period * POS_Q)


## A 64-bit offset (m) quantised and wrapped into [-P_u / 2, P_u / 2).
static func quant_pos(x: float, y: float, z: float, p_units: int) -> Vector3i:
	return wrap_units(Vector3i(roundi(x * POS_Q), roundi(y * POS_Q), roundi(z * POS_Q)), p_units)


static func quant_vel(v: Vector3) -> Vector3i:
	return Vector3i((v * VEL_Q).round()).clampi(-32767, 32767)


static func quant_proj_vel(v: Vector3) -> Vector3i:
	return Vector3i((v * PROJ_VEL_Q).round()).clampi(-32767, 32767)


static func quant_ang(w: Vector3) -> Vector3i:
	return Vector3i((w * ANG_Q).round()).clampi(-127, 127)


static func pos_of(p: Vector3i) -> Vector3:
	return Vector3(p) / POS_Q


static func ang_of(w: Vector3i) -> Vector3:
	return Vector3(w) / ANG_Q


## Wraps each axis of a position (units) into [-p_units / 2, p_units / 2); p_units 0
## leaves it unwrapped.
static func wrap_units(v: Vector3i, p_units: int) -> Vector3i:
	if p_units <= 0:
		return v
	return Vector3i(_wrap1(v.x, p_units), _wrap1(v.y, p_units), _wrap1(v.z, p_units))


## The minimum-image difference a - b (units).
static func diff(a: Vector3i, b: Vector3i, p_units: int) -> Vector3i:
	return wrap_units(a - b, p_units)


## Dead-reckoned position after dt ticks (0 <= dt <= MAX_AGE), wrapped: p + round(v dt
## / den) per axis, rounding half up, in 64-bit integers on both ends.
static func predict(
	p: Vector3i, v: Vector3i, dt: int, p_units: int, den: int = PRED_DEN
) -> Vector3i:
	var out: Vector3i = Vector3i(
		p.x + _round_div(v.x * dt, den),
		p.y + _round_div(v.y * dt, den),
		p.z + _round_div(v.z * dt, den)
	)
	return wrap_units(out, p_units)


static func max_abs(v: Vector3i) -> int:
	return maxi(maxi(absi(v.x), absi(v.y)), absi(v.z))


## Smallest three in 32 bits: 2 bits for the largest component's index, then the
## other three in 10 bits each over [-1/sqrt 2, 1/sqrt 2] (worst error under 0.2°).
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


## Writes one kinematic record: id u16, flags u8 (pos mode | vel mode << 2), the
## position (minimum-image residual against `pred`, or absolute) and the velocity
## (unchanged, residual against `base_v`, or absolute).
static func put_kin(
	buf: StreamPeerBuffer,
	id: int,
	p: Vector3i,
	v: Vector3i,
	pred: Vector3i,
	base_v: Vector3i,
	absolute: bool,
	p_units: int
) -> void:
	var pos_mode: int = POS_ABS
	var err: Vector3i = diff(p, pred, p_units)
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
			put3_8(buf, err)
		POS_S16:
			put3_16(buf, err)
		_:
			put3_32(buf, p)
	match vel_mode:
		VEL_S8:
			put3_8(buf, dv)
		VEL_ABS:
			put3_16(buf, v)


## Reads a record written by put_kin against the model (id -> [p, v, tick]); returns
## [id, p, v]. A residual against an id missing from the model is a corrupt stream:
## returns [] (the caller drops the snapshot and the client asks for a full one).
static func get_kin(buf: StreamPeerBuffer, model: Dictionary, tick: int, p_units: int) -> Array:
	var id: int = buf.get_u16()
	var flags: int = buf.get_u8()
	var pos_mode: int = flags & 3
	var vel_mode: int = (flags >> 2) & 3
	var base_p: Vector3i = Vector3i.ZERO
	var base_v: Vector3i = Vector3i.ZERO
	if pos_mode != POS_ABS or vel_mode != VEL_ABS:
		if not model.has(id):
			return []
		var entry: Array = model[id]
		base_v = entry[1]
		base_p = predict(entry[0], base_v, tick - int(entry[2]), p_units)
	var p: Vector3i
	match pos_mode:
		POS_S8:
			p = wrap_units(base_p + get3_8(buf), p_units)
		POS_S16:
			p = wrap_units(base_p + get3_16(buf), p_units)
		_:
			p = get3_32(buf)
	var v: Vector3i = base_v
	match vel_mode:
		VEL_S8:
			v = base_v + get3_8(buf)
		VEL_ABS:
			v = get3_16(buf)
	return [id, p, v]


static func put3_8(buf: StreamPeerBuffer, v: Vector3i) -> void:
	buf.put_8(v.x)
	buf.put_8(v.y)
	buf.put_8(v.z)


static func put3_16(buf: StreamPeerBuffer, v: Vector3i) -> void:
	buf.put_16(v.x)
	buf.put_16(v.y)
	buf.put_16(v.z)


static func put3_32(buf: StreamPeerBuffer, v: Vector3i) -> void:
	buf.put_32(v.x)
	buf.put_32(v.y)
	buf.put_32(v.z)


static func get3_8(buf: StreamPeerBuffer) -> Vector3i:
	return Vector3i(buf.get_8(), buf.get_8(), buf.get_8())


static func get3_16(buf: StreamPeerBuffer) -> Vector3i:
	return Vector3i(buf.get_16(), buf.get_16(), buf.get_16())


static func get3_32(buf: StreamPeerBuffer) -> Vector3i:
	return Vector3i(buf.get_32(), buf.get_32(), buf.get_32())


## round(n / d) for d > 0, halves rounded up, in 64-bit integers.
static func _round_div(n: int, d: int) -> int:
	var num: int = 2 * n + d
	var den: int = 2 * d
	var q: int = num / den
	if num % den != 0 and num < 0:
		q -= 1
	return q


static func _wrap1(v: int, p: int) -> int:
	var half: int = p / 2
	return posmod(v + half, p) - half
