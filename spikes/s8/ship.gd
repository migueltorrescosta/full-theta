## S8 procedural ship: primitive meshes, a cel shader and an inverted-hull outline.
## Nose points along -Z. The palette is picked by `variant` before the node enters the tree.
class_name S8Ship
extends Node3D

enum Role { HULL, ACCENT, GLASS, GLOW }

const TOON: Shader = preload("res://spikes/s8/toon.gdshader")
const OUTLINE: Shader = preload("res://spikes/s8/outline.gdshader")
## Variant 0: cream and red. Variant 1: mint and violet.
const PALETTES: Array[Dictionary] = [
	{
		Role.HULL: Color(0.97, 0.91, 0.78),
		Role.ACCENT: Color(0.9, 0.24, 0.2),
		Role.GLASS: Color(0.35, 0.82, 0.92),
		Role.GLOW: Color(1.0, 0.6, 0.2),
	},
	{
		Role.HULL: Color(0.6, 0.9, 0.78),
		Role.ACCENT: Color(0.5, 0.32, 0.8),
		Role.GLASS: Color(1.0, 0.86, 0.4),
		Role.GLOW: Color(0.4, 0.9, 1.0),
	},
]

var variant: int = 0


func _ready() -> void:
	var along_z: Vector3 = Vector3(90, 0, 0)
	_part(_capsule(0.55, 2.6), Role.HULL, Vector3.ZERO, along_z)
	_part(_sphere(0.3, 0.6), Role.ACCENT, Vector3(0, 0, -1.15), Vector3.ZERO)
	_part(_cylinder(0.57, 0.57, 0.22), Role.ACCENT, Vector3(0, 0, 0.3), along_z)
	_part(_sphere(0.36, 0.56), Role.GLASS, Vector3(0, 0.4, -0.45), Vector3.ZERO)
	for side: float in [-1.0, 1.0]:
		var sweep: Vector3 = Vector3(0, side * -20, 0)
		_part(_box(Vector3(1.4, 0.1, 0.7)), Role.ACCENT, Vector3(side * 1.0, -0.1, 0.4), sweep)
		_part(_capsule(0.24, 1.1), Role.HULL, Vector3(side * 1.7, -0.1, 0.55), along_z)
		_part(_cylinder(0.15, 0.15, 0.04), Role.GLOW, Vector3(side * 1.7, -0.1, 1.11), along_z)
	_part(_box(Vector3(0.1, 0.7, 0.6)), Role.ACCENT, Vector3(0, 0.62, 0.85), Vector3(-25, 0, 0))
	_part(_sphere(0.3, 0.3), Role.GLOW, Vector3(0, 0, 1.2), Vector3.ZERO)


## Adds a toon-shaded part and, except for glows, its outline hull.
func _part(mesh: PrimitiveMesh, role: Role, at: Vector3, rotation_deg: Vector3) -> void:
	var colour: Color = PALETTES[variant][role]
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = TOON
	material.set_shader_parameter("albedo", colour)
	if role == Role.GLOW:
		material.set_shader_parameter("glow", colour)
	var body: MeshInstance3D = MeshInstance3D.new()
	body.mesh = mesh
	body.material_override = material
	body.position = at
	body.rotation_degrees = rotation_deg
	add_child(body)
	if role == Role.GLOW:
		return
	var hull: MeshInstance3D = MeshInstance3D.new()
	hull.mesh = _smoothed(mesh)
	var outline: ShaderMaterial = ShaderMaterial.new()
	outline.shader = OUTLINE
	hull.material_override = outline
	body.add_child(hull)


## A copy of the mesh for the outline hull. Each vertex's normal becomes the mean of the
## distinct face normals at its position, so the hull has no gaps at hard edges.
func _smoothed(mesh: PrimitiveMesh) -> ArrayMesh:
	var arrays: Array = mesh.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var at: Dictionary[Vector3, PackedVector3Array] = {}
	for i: int in verts.size():
		var seen: PackedVector3Array = at.get(verts[i], PackedVector3Array())
		if not _has_near(seen, normals[i]):
			seen.append(normals[i])
			at[verts[i]] = seen
	var smooth: PackedVector3Array = PackedVector3Array()
	smooth.resize(verts.size())
	for i: int in verts.size():
		var sum: Vector3 = Vector3.ZERO
		for n: Vector3 in at[verts[i]]:
			sum += n
		smooth[i] = sum.normalized()
	var hull: Array = []
	hull.resize(Mesh.ARRAY_MAX)
	hull[Mesh.ARRAY_VERTEX] = verts
	hull[Mesh.ARRAY_NORMAL] = smooth
	hull[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
	var result: ArrayMesh = ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, hull)
	return result


func _has_near(list: PackedVector3Array, n: Vector3) -> bool:
	for m: Vector3 in list:
		if m.dot(n) > 0.99:
			return true
	return false


func _capsule(radius: float, height: float) -> CapsuleMesh:
	var m: CapsuleMesh = CapsuleMesh.new()
	m.radius = radius
	m.height = height
	return m


func _cylinder(top: float, bottom: float, height: float) -> CylinderMesh:
	var m: CylinderMesh = CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	return m


func _sphere(radius: float, height: float) -> SphereMesh:
	var m: SphereMesh = SphereMesh.new()
	m.radius = radius
	m.height = height
	return m


func _box(size: Vector3) -> BoxMesh:
	var m: BoxMesh = BoxMesh.new()
	m.size = size
	return m
