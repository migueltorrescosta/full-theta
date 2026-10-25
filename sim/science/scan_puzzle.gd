class_name ScanPuzzle
extends RefCounted
## The silhouette-alignment scan (FT-SCI-004, D58), generated and checked on the server
## (FT-SCI-011). A puzzle is a wireframe (vertices on a unit ball) and a sparse point
## cloud: the wireframe turned by a hidden pose, plus position error and clutter points
## that grow with the noise. The player turns the wireframe about the open rotation
## axes (a bit mask: 1 x, 2 y, 4 z) until it matches the cloud and sends the three
## angles; the pose is Basis.from_euler(Vector3(ax, ay, az)) with the closed axes at 0.
## Everything derives from (def, seed, noise, mask), so the sim stores only those.

const AXIS_X: int = 1
const AXIS_Y: int = 2
const AXIS_Z: int = 4


## Bit mask of the open axes: `count` of the three, picked by the seed.
static func axes_mask(puzzle_seed: int, count: int) -> int:
	if count >= 3:
		return 7
	var rng: RandomNumberGenerator = _rng(puzzle_seed, 1)
	if count == 2:
		return 7 ^ (1 << rng.randi_range(0, 2))
	return 1 << rng.randi_range(0, 2)


## The wireframe's vertices: random directions of random length, the longest of length 1,
## so the shape has no symmetry to confuse.
static func wire(def: ScienceDef, puzzle_seed: int) -> PackedVector3Array:
	var rng: RandomNumberGenerator = _rng(puzzle_seed, 2)
	var out: PackedVector3Array = PackedVector3Array()
	var longest: float = 0.0
	for i: int in def.wire_vertices:
		var d: Vector3 = Vector3(rng.randfn(), rng.randfn(), rng.randfn())
		if d.length() < 0.1:
			d = Vector3.RIGHT
		var v: Vector3 = d.normalized() * rng.randf_range(0.45, 1.0)
		longest = maxf(longest, v.length())
		out.append(v)
	for i: int in out.size():
		out[i] = out[i] / longest
	return out


## The hidden pose's angles (rad), 0 on closed axes.
static func target_angles(def: ScienceDef, puzzle_seed: int, mask: int) -> Vector3:
	var rng: RandomNumberGenerator = _rng(puzzle_seed, 3)
	var out: Vector3 = Vector3.ZERO
	for a: int in 3:
		var angle: float = rng.randf_range(def.min_angle, PI) * (1.0 if rng.randf() < 0.5 else -1.0)
		if mask & (1 << a):
			out[a] = angle
	return out


## The point cloud the player sees: the posed vertices with position error, plus
## clutter, shuffled.
static func cloud(def: ScienceDef, puzzle_seed: int, noise: float, mask: int) -> PackedVector3Array:
	var rng: RandomNumberGenerator = _rng(puzzle_seed, 4)
	var pose: Basis = Basis.from_euler(target_angles(def, puzzle_seed, mask))
	var sigma: float = noise * def.sigma_max
	var out: PackedVector3Array = PackedVector3Array()
	for v: Vector3 in wire(def, puzzle_seed):
		var p: Vector3 = pose * v
		out.append(
			p + Vector3(rng.randfn(0.0, sigma), rng.randfn(0.0, sigma), rng.randfn(0.0, sigma))
		)
	for i: int in roundi(noise * def.clutter_max):
		out.append(
			Vector3(
				rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)
			)
		)
	for i: int in range(out.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Vector3 = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


## Match quality 0..1 of the submitted angles against the hidden pose: 1 minus the RMS
## distance between the posed vertices over quality_span. Closed axes count as 0.
static func quality(def: ScienceDef, puzzle_seed: int, mask: int, angles: Vector3) -> float:
	var sub: Vector3 = Vector3.ZERO
	for a: int in 3:
		if mask & (1 << a):
			sub[a] = angles[a]
	var want: Basis = Basis.from_euler(target_angles(def, puzzle_seed, mask))
	var got: Basis = Basis.from_euler(sub)
	var total: float = 0.0
	var verts: PackedVector3Array = wire(def, puzzle_seed)
	for v: Vector3 in verts:
		total += (got * v - want * v).length_squared()
	var rms: float = sqrt(total / verts.size())
	return clampf(1.0 - rms / def.quality_span, 0.0, 1.0)


## Confidence of a scan with this match quality at this noise (FT-SCI-016): the
## quality, less the noise penalty, plus the lock bonus at and above the lock threshold.
static func confidence(def: ScienceDef, quality_value: float, noise: float) -> float:
	var c: float = quality_value * (1.0 - def.noise_penalty * noise)
	if quality_value >= def.lock_threshold:
		c += def.lock_bonus
	return clampf(c, 0.0, 1.0)


static func _rng(puzzle_seed: int, salt: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = puzzle_seed * 8 + salt
	return rng
