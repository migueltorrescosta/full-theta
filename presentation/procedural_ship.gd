## Procedural ship (S8 v2, the approved style, D107; FT-AUD-016): a lofted hull, flat
## slabs for wings and fins, engine nacelles and seeded greebles, shaded with PBR
## StandardMaterial3D (metallic, roughness, a plating texture and its normal map, all
## generated in code). Nose points along -Z.
## `wear` (0 clean, 1 weathered) is set before the node enters the tree.
## The Compatibility renderer has no SSAO, so a fake ambient occlusion is baked into vertex
## colours once the parts are built (`_bake_ao`).
class_name ProceduralShip
extends Node3D

enum Role { HULL, ACCENT, METAL, DARK, GLASS, GLOW }
enum Shape { BOX, CYLINDER, SPHERE, SLAB, HULL }

## Muted variant B: sage hull, dark violet-graphite accents, metal greys.
const COLOURS: Dictionary[Role, Color] = {
	Role.HULL: Color(0.38, 0.47, 0.42),
	Role.ACCENT: Color(0.2, 0.18, 0.26),
	Role.METAL: Color(0.52, 0.53, 0.55),
	Role.DARK: Color(0.1, 0.1, 0.12),
	Role.GLASS: Color(0.12, 0.15, 0.17),
	Role.GLOW: Color(0.55, 1.0, 0.86),
}
const METALLIC: Dictionary[Role, float] = {
	Role.HULL: 0.35,
	Role.ACCENT: 0.5,
	Role.METAL: 0.9,
	Role.DARK: 0.6,
	Role.GLASS: 0.0,
	Role.GLOW: 0.0,
}
const ROUGHNESS: Dictionary[Role, float] = {
	Role.HULL: 0.45,
	Role.ACCENT: 0.5,
	Role.METAL: 0.35,
	Role.DARK: 0.6,
	Role.GLASS: 0.12,
	Role.GLOW: 1.0,
}
## Hull cross-sections from nose to tail: z, half-width, half-height, centre height.
const SECTIONS: Array[Vector4] = [
	Vector4(-2.7, 0.01, 0.01, -0.04),
	Vector4(-2.55, 0.1, 0.06, -0.03),
	Vector4(-2.2, 0.2, 0.13, -0.01),
	Vector4(-1.6, 0.33, 0.21, 0.02),
	Vector4(-0.8, 0.44, 0.26, 0.04),
	Vector4(0.2, 0.5, 0.28, 0.04),
	Vector4(1.4, 0.5, 0.27, 0.03),
	Vector4(2.1, 0.44, 0.24, 0.02),
	Vector4(2.3, 0.4, 0.21, 0.02),
	Vector4(2.32, 0.3, 0.15, 0.02),
	Vector4(2.34, 0.01, 0.01, 0.02),
]
const RING: int = 64  # points per hull cross-section
const HULL_STEP: float = 0.05  # longest gap between hull rings, so the baked AO has vertices
const SQUARENESS: float = 0.55  # superellipse exponent: 1 is an ellipse, lower is boxier
const TEXTURE_SIZE: int = 256
const TEXTURE_SPAN: float = 1.6  # metres covered by one tile of the plating texture
## Fake AO: distances along the vertex normal at which the other parts' distance field is
## sampled, the weight of each sample, the overall strength and the darkest allowed value.
const AO_STEPS: Array[float] = [0.02, 0.05, 0.1, 0.2]
const AO_WEIGHTS: Array[float] = [0.35, 0.3, 0.2, 0.15]
const AO_CONTACT: float = 0.8  # weight of the contact term
const AO_HALO: float = 1.5  # contact halo radius per metre of the part's smallest dimension
const AO_STRENGTH: float = 1.0
const AO_FLOOR: float = 0.35
const SEAM_AO: float = 0.88  # plating brightness right next to a seam
const AO_CELL: float = 0.2  # grid cell (metres) used to find the parts near a vertex

var wear: float = 0.0
var _materials: Dictionary[Role, StandardMaterial3D] = {}
var _hull_mesh: ArrayMesh = null


## One part as the AO bake sees it: its shape, the transform from ship space to the part's
## mesh space and its bounds in ship space.
class AoPart:
	var shape: Shape = Shape.BOX
	var to_local: Transform3D = Transform3D.IDENTITY
	var scale: float = 1.0  # smallest scale factor, for scaled spheres
	var size: Vector3 = Vector3.ZERO  # box size, or cylinder (top, bottom, height), or radius
	var thickness: float = 0.0  # slab thickness
	var edges: Array[Vector3] = []  # slab edges: outward normal (x, z) and offset
	var halo: float = 0.0  # contact darkening radius around the part
	var bounds: AABB = AABB()
	var reach: AABB = AABB()  # bounds grown by twice the longest AO step


func _ready() -> void:
	_make_materials()
	_add(_hull(), Role.HULL, Vector3.ZERO)
	_add_cockpit()
	for side: float in [-1.0, 1.0]:
		_add_wing(side)
		_add_nacelle(side)
	_add_tail()
	_add_greebles()
	_bake_ao()


func _add_cockpit() -> void:
	var canopy: MeshInstance3D = _add(
		_sphere(1.0), Role.GLASS, Vector3(0, _top(-1.55) - 0.04, -1.55)
	)
	canopy.scale = Vector3(0.19, 0.12, 0.5)
	var frame: MeshInstance3D = _add(_sphere(1.0), Role.ACCENT, Vector3(0, _top(-1.3) - 0.06, -1.3))
	frame.scale = Vector3(0.21, 0.1, 0.42)
	# Dorsal spine behind the canopy.
	_add(_box(Vector3(0.22, 0.07, 2.3)), Role.ACCENT, Vector3(0, _top(0.3) + 0.01, 0.3))


func _add_wing(side: float) -> void:
	var outline: PackedVector2Array = [
		Vector2(0.4, -0.4), Vector2(2.2, 1.05), Vector2(2.3, 1.5), Vector2(0.4, 1.8)
	]
	var wing: MeshInstance3D = _add(
		_slab(_mirror(outline, side), 0.07, 12), Role.HULL, Vector3(0, -0.08, 0)
	)
	wing.rotation_degrees = Vector3(0, 0, side * -4)
	# Violet panel inset on the upper surface.
	var panel: PackedVector2Array = [
		Vector2(1.0, 0.4), Vector2(1.95, 1.17), Vector2(2.02, 1.42), Vector2(1.0, 1.55)
	]
	_add(_slab(_mirror(panel, side), 0.015, 8), Role.ACCENT, Vector3(0, 0.03, 0), wing)
	# Wingtip pod with a navigation light.
	var pod_at: Vector3 = Vector3(side * 2.3, 0, 1.3)
	_add(_cylinder(0.05, 0.05, 0.7), Role.METAL, pod_at, wing).rotation_degrees = Vector3(90, 0, 0)
	_add(_sphere(0.035), Role.GLOW, Vector3(side * 2.3, 0, 0.93), wing)


func _add_nacelle(side: float) -> void:
	var x: float = side * 0.78
	var along_z: Vector3 = Vector3(90, 0, 0)
	_add(_cylinder(0.19, 0.19, 1.6), Role.HULL, Vector3(x, 0.02, 1.6)).rotation_degrees = along_z
	_add(_cylinder(0.2, 0.21, 0.1), Role.ACCENT, Vector3(x, 0.02, 0.82)).rotation_degrees = along_z
	_add(_cylinder(0.15, 0.15, 0.02), Role.DARK, Vector3(x, 0.02, 0.76)).rotation_degrees = along_z
	_add(_cylinder(0.2, 0.2, 0.08), Role.ACCENT, Vector3(x, 0.02, 1.95)).rotation_degrees = along_z
	_add(_cylinder(0.2, 0.16, 0.28), Role.METAL, Vector3(x, 0.02, 2.53)).rotation_degrees = along_z
	_add(_cylinder(0.15, 0.15, 0.02), Role.DARK, Vector3(x, 0.02, 2.66)).rotation_degrees = along_z
	_add(_cylinder(0.11, 0.11, 0.02), Role.GLOW, Vector3(x, 0.02, 2.67)).rotation_degrees = along_z
	# Pylon joining the nacelle to the hull.
	_add(_box(Vector3(0.4, 0.06, 1.1)), Role.METAL, Vector3(side * 0.5, 0.0, 1.5))
	# Cooling fins along the nacelle's outer side.
	for i: int in 6:
		var fin: Vector3 = Vector3(x + side * 0.18, 0.02, 1.15 + i * 0.12)
		_add(_box(Vector3(0.06, 0.18, 0.03)), Role.METAL, fin)


func _add_tail() -> void:
	for side: float in [-1.0, 1.0]:
		var outline: PackedVector2Array = [
			Vector2(0.0, 1.0), Vector2(0.62, 1.95), Vector2(0.66, 2.3), Vector2(0.0, 2.3)
		]
		var fin: MeshInstance3D = _add(
			_slab(outline, 0.05, 8), Role.HULL, Vector3(side * 0.78, 0.2, 0)
		)
		fin.rotation_degrees = Vector3(0, 0, 90 - side * 18)
	# Main engine bell and glow at the tail.
	var along_z: Vector3 = Vector3(90, 0, 0)
	_add(_cylinder(0.26, 0.22, 0.3), Role.METAL, Vector3(0, 0.02, 2.46)).rotation_degrees = along_z
	_add(_cylinder(0.21, 0.21, 0.02), Role.DARK, Vector3(0, 0.02, 2.6)).rotation_degrees = along_z
	_add(_cylinder(0.16, 0.16, 0.02), Role.GLOW, Vector3(0, 0.02, 2.61)).rotation_degrees = along_z


## Small boxes on the hull's upper surface and vents on its flanks, from a fixed seed.
func _add_greebles() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	for i: int in 26:
		var z: float = rng.randf_range(-0.9, 2.1)
		var half: float = _section(z).y * 0.55
		var x: float = rng.randf_range(0.14, half) * (1.0 if rng.randf() < 0.5 else -1.0)
		var size: Vector3 = Vector3(
			rng.randf_range(0.04, 0.14), rng.randf_range(0.02, 0.06), rng.randf_range(0.05, 0.25)
		)
		var role: Role = Role.METAL if rng.randf() < 0.6 else Role.ACCENT
		_add(_box(size), role, Vector3(x, _top(z) - 0.01 + size.y * 0.5, z))
	for side: float in [-1.0, 1.0]:
		for i: int in 7:
			var z: float = -0.7 + i * 0.09
			var vent: Vector3 = Vector3(side * (_section(z).y - 0.02), 0.06, z)
			_add(_box(Vector3(0.05, 0.12, 0.035)), Role.DARK, vent)
		# Reaction-control blocks near the nose.
		_add(_box(Vector3(0.08, 0.08, 0.12)), Role.METAL, Vector3(side * 0.3, 0.02, -1.75))
	# Antenna on the spine.
	_add(_cylinder(0.008, 0.008, 0.4), Role.METAL, Vector3(0, _top(1.0) + 0.24, 1.0))


## Fake ambient occlusion, baked into vertex colours that the materials multiply into the
## albedo. For each vertex, the distance field of every other part is sampled at a few
## points along the vertex normal (AO_STEPS); a sample closer to another part than to the
## vertex darkens it. This darkens the hull around greebles and vents, the feet of the
## greebles, and the joints between hull, wings, fins, pylons and nacelles. No randomness and
## no time dependence, so the result is the same on every run.
func _bake_ao() -> void:
	var nodes: Array[MeshInstance3D] = []
	var parts: Array[AoPart] = []
	for node: Node in find_children("*", "MeshInstance3D", true, false):
		var body: MeshInstance3D = node as MeshInstance3D
		if body.material_override != _materials[Role.GLOW]:
			nodes.append(body)
			parts.append(_ao_part(body))
	# Cells reached from each part: a vertex can be darkened by parts within twice the
	# longest sample distance.
	var grid: Dictionary[Vector3i, Array] = {}
	for index: int in parts.size():
		var box: AABB = parts[index].bounds.grow(AO_STEPS[-1] * 2.0)
		parts[index].reach = box
		var lo: Vector3i = Vector3i((box.position / AO_CELL).floor())
		var hi: Vector3i = Vector3i((box.end / AO_CELL).floor())
		for x: int in range(lo.x, hi.x + 1):
			for y: int in range(lo.y, hi.y + 1):
				for z: int in range(lo.z, hi.z + 1):
					var key: Vector3i = Vector3i(x, y, z)
					if not grid.has(key):
						grid[key] = []
					grid[key].append(index)
	for index: int in nodes.size():
		var arrays: Array = nodes[index].mesh.surface_get_arrays(0)
		var to_ship: Transform3D = parts[index].to_local.affine_inverse()
		var normal_basis: Basis = to_ship.basis.inverse().transposed()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colours: PackedColorArray = PackedColorArray()
		colours.resize(vertices.size())
		for v: int in vertices.size():
			var p: Vector3 = to_ship * vertices[v]
			var near: Array = grid.get(Vector3i((p / AO_CELL).floor()), [])
			var ao: float = _ao(p, (normal_basis * normals[v]).normalized(), index, near, parts)
			colours[v] = Color(ao, ao, ao)
		arrays[Mesh.ARRAY_COLOR] = colours
		var mesh: ArrayMesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		nodes[index].mesh = mesh


## AO at ship-space point `p` with normal `n` on part `own`: 1 is unoccluded.
func _ao(p: Vector3, n: Vector3, own: int, near: Array, parts: Array[AoPart]) -> float:
	# A sample at distance h from p is at least distance(p) - h from a part, so only parts
	# closer than twice the longest step can darken p.
	# A point at distance h from p is at least distance(p) - h from a part, so a part at
	# distance d0 from p can only darken the samples with h > d0 / 2.
	# Contact: a part beside or in front of the vertex, within its halo, darkens it; one
	# behind the vertex (getting further away along the normal) doesn't.
	var close: Array[AoPart] = []
	var gaps: PackedFloat32Array = PackedFloat32Array()
	var contact: float = 0.0
	for other: int in near:
		var part: AoPart = parts[other]
		if other == own or not part.reach.has_point(p):
			continue
		var d0: float = _distance(part, p)
		if d0 >= AO_STEPS[-1] * 2.0:
			continue
		close.append(part)
		gaps.append(d0)
		if d0 < part.halo + AO_STEPS[0]:
			var d1: float = _distance(part, p + n * AO_STEPS[0])
			var facing: float = clampf(0.5 + (d0 - d1) / (2.0 * AO_STEPS[0]), 0.0, 1.0)
			contact = maxf(contact, facing * (1.0 - smoothstep(0.0, part.halo, d1)))
	if close.is_empty():
		return 1.0
	var occlusion: float = AO_CONTACT * contact
	for s: int in AO_STEPS.size():
		var h: float = AO_STEPS[s]
		var q: Vector3 = p + n * h
		var d: float = INF
		for c: int in close.size():
			if gaps[c] < 2.0 * h:
				d = minf(d, _distance(close[c], q))
		occlusion += AO_WEIGHTS[s] * clampf((h - d) / h, 0.0, 1.0)
	return clampf(1.0 - AO_STRENGTH * occlusion, AO_FLOOR, 1.0)


## Describes a part for the AO bake, from its mesh and its transform within the ship.
func _ao_part(body: MeshInstance3D) -> AoPart:
	var to_ship: Transform3D = body.transform
	var parent: Node3D = body.get_parent() as Node3D
	while parent != self:
		to_ship = parent.transform * to_ship
		parent = parent.get_parent() as Node3D
	var part: AoPart = AoPart.new()
	part.to_local = to_ship.affine_inverse()
	var scale: Vector3 = to_ship.basis.get_scale()
	part.scale = minf(scale.x, minf(scale.y, scale.z))
	part.bounds = to_ship * body.mesh.get_aabb()
	var mesh: Mesh = body.mesh
	var smallest: float = 1.0  # the part's smallest dimension, which sets its halo
	if mesh is BoxMesh:
		part.size = (mesh as BoxMesh).size
		smallest = minf(part.size.x, minf(part.size.y, part.size.z))
	elif mesh is CylinderMesh:
		var c: CylinderMesh = mesh as CylinderMesh
		part.shape = Shape.CYLINDER
		part.size = Vector3(c.top_radius, c.bottom_radius, c.height)
		smallest = minf(2.0 * c.top_radius, c.height)
	elif mesh is SphereMesh:
		part.shape = Shape.SPHERE
		part.size = Vector3.ONE * (mesh as SphereMesh).radius
		smallest = 2.0 * part.size.x * part.scale
	elif mesh == _hull_mesh:
		part.shape = Shape.HULL
	else:
		part.shape = Shape.SLAB
		part.thickness = mesh.get_meta("thickness")
		smallest = part.thickness
		var outline: PackedVector2Array = mesh.get_meta("outline")
		var centre: Vector2 = Vector2.ZERO
		for p: Vector2 in outline:
			centre += p / outline.size()
		for k: int in outline.size():
			var a: Vector2 = outline[k]
			var b: Vector2 = outline[(k + 1) % outline.size()]
			var normal: Vector2 = Vector2(b.y - a.y, a.x - b.x).normalized()
			if normal.dot((a + b) * 0.5 - centre) < 0.0:
				normal = -normal
			part.edges.append(Vector3(normal.x, normal.y, normal.dot(a)))
	part.halo = clampf(AO_HALO * smallest, AO_STEPS[0], AO_STEPS[2])
	return part


## Approximate signed distance from ship-space point `p` to a part (negative inside).
func _distance(part: AoPart, p: Vector3) -> float:
	var q: Vector3 = part.to_local * p
	match part.shape:
		Shape.BOX:
			var b: Vector3 = q.abs() - part.size * 0.5
			return b.max(Vector3.ZERO).length() + minf(maxf(b.x, maxf(b.y, b.z)), 0.0)
		Shape.CYLINDER:
			var t: float = clampf(q.y / part.size.z + 0.5, 0.0, 1.0)
			var r: float = lerpf(part.size.y, part.size.x, t)
			return _extrude(Vector2(q.x, q.z).length() - r, absf(q.y) - part.size.z * 0.5)
		Shape.SPHERE:
			return (q.length() - part.size.x) * part.scale
		Shape.SLAB:
			var d: float = -INF
			for e: Vector3 in part.edges:
				d = maxf(d, e.x * q.x + e.y * q.z - e.z)
			return _extrude(d, absf(q.y) - part.thickness * 0.5)
	return _hull_distance(q)


## Distance to a 2D shape (signed `across`) extruded to a half-height (signed `along`).
func _extrude(across: float, along: float) -> float:
	return Vector2(maxf(across, 0.0), maxf(along, 0.0)).length() + minf(maxf(across, along), 0.0)


## Approximate signed distance to the hull: the superellipse section's level set, scaled by
## the half-width on the flanks and the half-height on top and bottom.
func _hull_distance(p: Vector3) -> float:
	var s: Vector4 = _section(p.z)
	var e: float = 1.0 / SQUARENESS
	var a: float = pow(absf(p.x) / maxf(s.y, 0.01), e)
	var b: float = pow(absf(p.y - s.w) / maxf(s.z, 0.01), e)
	var scale: float = (a * s.y + b * s.z) / (a + b) if a + b > 1e-6 else minf(s.y, s.z)
	var d: float = (pow(a + b, SQUARENESS) - 1.0) * scale
	var dz: float = maxf(SECTIONS[0].x - p.z, p.z - SECTIONS[-1].x)
	return Vector2(maxf(d, 0.0), maxf(dz, 0.0)).length() + minf(maxf(d, dz), 0.0)


func _add(mesh: Mesh, role: Role, at: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var body: MeshInstance3D = MeshInstance3D.new()
	body.mesh = mesh
	body.material_override = _materials[role]
	body.position = at
	parent.add_child(body)
	return body


func _make_materials() -> void:
	var textures: Array[ImageTexture] = _plating()
	for role: Role in COLOURS:
		var m: StandardMaterial3D = StandardMaterial3D.new()
		m.albedo_color = COLOURS[role]
		m.metallic = METALLIC[role]
		m.roughness = ROUGHNESS[role]
		if role == Role.GLOW:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.emission_enabled = true
			m.emission = COLOURS[role]
			m.emission_energy_multiplier = 2.0
		elif role != Role.GLASS:
			m.albedo_texture = textures[0]
			m.roughness_texture = textures[1]
			m.normal_enabled = true
			m.normal_texture = textures[2]
			m.normal_scale = 0.6
			m.uv1_triplanar = true
			m.uv1_triplanar_sharpness = 4.0
			m.uv1_scale = Vector3.ONE / TEXTURE_SPAN
			m.vertex_color_use_as_albedo = true
		else:
			m.metallic_specular = 0.9
			m.vertex_color_use_as_albedo = true
		_materials[role] = m


## Plating textures: albedo tint, roughness and normal map. Panels in staggered rows with
## seams between them; `wear` varies the panel shades more and adds grime (blotches and
## streaks) that darkens and roughens.
func _plating() -> Array[ImageTexture]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	var n: int = TEXTURE_SIZE
	var rows: int = 8
	var row_h: int = n / rows
	var tint: PackedFloat32Array = PackedFloat32Array()
	tint.resize(n * n)
	var height: PackedFloat32Array = PackedFloat32Array()
	height.resize(n * n)
	for r: int in rows:
		var x0: int = rng.randi_range(0, 63)
		var cuts: Array[int] = []
		var x: int = x0
		while x < x0 + n:
			cuts.append(x)
			x += rng.randi_range(40, 110)
		cuts.append(x0 + n)
		for c: int in cuts.size() - 1:
			var shade: float = 1.0 + rng.randf_range(-1.0, 1.0) * (0.05 + 0.07 * wear)
			for px: int in range(cuts[c], cuts[c + 1]):
				for py: int in range(r * row_h, (r + 1) * row_h):
					var seam: bool = px - cuts[c] < 2 or py - r * row_h < 2
					var i: int = py * n + (px % n)
					# Fake AO: plating darkens towards the seams around it.
					var edge: int = mini(
						mini(px - cuts[c] - 2, cuts[c + 1] - 1 - px),
						mini(py - r * row_h - 2, (r + 1) * row_h - 1 - py)
					)
					var ao: float = lerpf(SEAM_AO, 1.0, smoothstep(0.0, 4.0, float(edge)))
					tint[i] = 0.72 if seam else shade * ao
					height[i] = 0.0 if seam else 1.0
	var blotches: PackedFloat32Array = _value_noise(n, 8, 8, rng)
	var streaks: PackedFloat32Array = _value_noise(n, 24, 3, rng)
	var albedo: PackedByteArray = PackedByteArray()
	var rough: PackedByteArray = PackedByteArray()
	var bump: PackedByteArray = PackedByteArray()
	for i: int in n * n:
		var dirt: float = wear * smoothstep(0.4, 0.95, 0.75 * blotches[i] + 0.25 * streaks[i])
		var a: int = clampi(int(255.0 * tint[i] * (1.0 - 0.3 * dirt) / 1.06), 0, 255)
		albedo.append_array([a, a, a])
		rough.append(clampi(int(255.0 * (0.85 + 0.15 * dirt) * (2.0 - tint[i])), 0, 255))
		bump.append(int(255.0 * height[i]))
	var images: Array[Image] = [
		Image.create_from_data(n, n, false, Image.FORMAT_RGB8, albedo),
		Image.create_from_data(n, n, false, Image.FORMAT_L8, rough),
		Image.create_from_data(n, n, false, Image.FORMAT_L8, bump),
	]
	images[2].convert(Image.FORMAT_RGBA8)
	images[2].bump_map_to_normal_map(4.0)
	var textures: Array[ImageTexture] = []
	for image: Image in images:
		image.generate_mipmaps()
		textures.append(ImageTexture.create_from_image(image))
	return textures


## Tileable value noise in [0, 1] on an n x n image: a random grid of cells_x by cells_y,
## smoothly interpolated.
func _value_noise(
	n: int, cells_x: int, cells_y: int, rng: RandomNumberGenerator
) -> PackedFloat32Array:
	var grid: PackedFloat32Array = PackedFloat32Array()
	for i: int in cells_x * cells_y:
		grid.append(rng.randf())
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n * n)
	for y: int in n:
		for x: int in n:
			var gx: float = float(x) * cells_x / n
			var gy: float = float(y) * cells_y / n
			var ix: int = int(gx)
			var iy: int = int(gy)
			var fx: float = smoothstep(0.0, 1.0, gx - ix)
			var fy: float = smoothstep(0.0, 1.0, gy - iy)
			var x1: int = (ix + 1) % cells_x
			var y1: int = (iy + 1) % cells_y
			var top: float = lerpf(grid[iy * cells_x + ix], grid[iy * cells_x + x1], fx)
			var bottom: float = lerpf(grid[y1 * cells_x + ix], grid[y1 * cells_x + x1], fx)
			out[y * n + x] = lerpf(top, bottom, fy)
	return out


## The hull: superellipse cross-sections lofted along Z, with smooth normals. Extra rings
## are interpolated between the sections (the shape stays the same) for the baked AO.
func _hull() -> ArrayMesh:
	var rings: Array[Vector4] = []
	for i: int in SECTIONS.size() - 1:
		var steps: int = ceili((SECTIONS[i + 1].x - SECTIONS[i].x) / HULL_STEP)
		for j: int in steps:
			rings.append(SECTIONS[i].lerp(SECTIONS[i + 1], float(j) / steps))
	rings.append(SECTIONS[-1])
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s: Vector4 in rings:
		for k: int in RING + 1:
			var angle: float = TAU * k / RING
			var c: float = cos(angle)
			var si: float = sin(angle)
			var px: float = s.y * signf(c) * pow(absf(c), SQUARENESS)
			var py: float = s.w + s.z * signf(si) * pow(absf(si), SQUARENESS)
			st.set_uv(Vector2(float(k) / RING * 3.0, s.x / TEXTURE_SPAN))
			st.add_vertex(Vector3(px, py, s.x))
	for i: int in rings.size() - 1:
		for k: int in RING:
			var a: int = i * (RING + 1) + k
			var b: int = a + RING + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
	st.generate_normals()
	st.generate_tangents()
	_hull_mesh = st.commit()
	return _hull_mesh


## A flat plate: a convex outline in the XZ plane extruded by `thickness` along Y, with
## flat normals on every face. Each fan triangle of the top and bottom is split into
## `grid` x `grid` smaller ones so the baked AO can vary across the plate.
func _slab(outline: PackedVector2Array, thickness: float, grid: int) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h: float = thickness * 0.5
	var count: int = outline.size()
	var centre: Vector2 = Vector2.ZERO
	for p: Vector2 in outline:
		centre += p / count
	for face: float in [h, -h]:
		var corners: Array[Vector3] = []
		for p: Vector2 in outline:
			corners.append(Vector3(p.x, face, p.y))
		var up: Vector3 = Vector3(0, signf(face), 0)
		for k: int in range(1, count - 1):
			var du: Vector3 = (corners[k] - corners[0]) / grid
			var dv: Vector3 = (corners[k + 1] - corners[0]) / grid
			for i: int in grid:
				for j: int in grid - i:
					var o: Vector3 = corners[0] + du * i + dv * j
					_face(st, [o, o + du, o + dv], up)
					if i + j < grid - 1:
						_face(st, [o + du, o + du + dv, o + dv], up)
	for k: int in count:
		var p: Vector2 = outline[k]
		var q: Vector2 = outline[(k + 1) % count]
		var mid: Vector2 = (p + q) * 0.5 - centre
		var normal: Vector3 = Vector3(q.y - p.y, 0, p.x - q.x).normalized()
		if normal.dot(Vector3(mid.x, 0, mid.y)) < 0.0:
			normal = -normal
		var a: Vector3 = Vector3(p.x, h, p.y)
		var b: Vector3 = Vector3(q.x, h, q.y)
		var c: Vector3 = Vector3(q.x, -h, q.y)
		var d: Vector3 = Vector3(p.x, -h, p.y)
		_face(st, [a, b, c], normal)
		_face(st, [a, c, d], normal)
	st.index()
	st.generate_tangents()
	var mesh: ArrayMesh = st.commit()
	mesh.set_meta("outline", outline)
	mesh.set_meta("thickness", thickness)
	return mesh


## Adds one flat triangle facing `normal` (Godot's front faces wind clockwise).
func _face(st: SurfaceTool, tri: Array[Vector3], normal: Vector3) -> void:
	if (tri[1] - tri[0]).cross(tri[2] - tri[0]).dot(normal) > 0.0:
		tri = [tri[0], tri[2], tri[1]]
	for v: Vector3 in tri:
		st.set_normal(normal)
		st.set_uv(Vector2(v.x + v.y, v.z))
		st.add_vertex(v)


func _mirror(outline: PackedVector2Array, side: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in outline:
		out.append(Vector2(p.x * side, p.y))
	return out


## Hull section at z, interpolated: (z, half-width, half-height, centre height).
func _section(z: float) -> Vector4:
	for i: int in SECTIONS.size() - 1:
		var a: Vector4 = SECTIONS[i]
		var b: Vector4 = SECTIONS[i + 1]
		if z <= b.x:
			return a.lerp(b, clampf((z - a.x) / (b.x - a.x), 0.0, 1.0))
	return SECTIONS[-1]


## Height of the hull's upper surface on the centre line at z.
func _top(z: float) -> float:
	var s: Vector4 = _section(z)
	return s.w + s.z


func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var m: CylinderMesh = CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = 32
	m.rings = maxi(1, ceili(height / 0.1))
	return m


func _sphere(radius: float) -> SphereMesh:
	var m: SphereMesh = SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 32
	m.rings = 16
	return m


func _box(size: Vector3) -> BoxMesh:
	var m: BoxMesh = BoxMesh.new()
	m.size = size
	m.subdivide_width = floori(size.x / 0.15)
	m.subdivide_height = floori(size.y / 0.15)
	m.subdivide_depth = floori(size.z / 0.15)
	return m
