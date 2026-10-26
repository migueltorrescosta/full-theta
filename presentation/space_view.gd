class_name SpaceView
extends Node3D
## The 3D space behind Helm's cockpit, the Weapons turret camera and the main screen:
## background, ambient and sun, one camera, a star field and the other ships. Put it in a
## SubViewport with its own world. The own ship sits at the origin with world axes; every
## other ship is drawn at its minimum-image offset (D124), so precision never depends on
## where the ship is in the cube. Ships are the approved procedural ship (D107), oriented
## from NEAR when known (the last known orientation otherwise). All ships share one
## template's meshes and materials, built on the first ship, so a view with no ships pays
## no AO bake. Kept cheap for llvmpipe: no post-processing, the stars one point mesh.

const STARS: int = 700
## Star sphere radius (m). It follows the camera position, so stars never parallax.
const STAR_R: float = 9000.0
const CAMERA_FAR: float = 30000.0

## Scale of every ship model (ProceduralShip is about 5 m long).
var ship_scale: float = 1.0
## The ships' wear (ProceduralShip.wear); set before the first ship is drawn.
var wear: float = 0.6
## Draw only contacts with a NEAR orientation (within 2 km), as the main screen does.
var near_only: bool = false
## A contact drawn even when near_only would drop it (the main screen's target, which can
## be farther than NEAR's range): its orientation is the last known, else the default.
var show_id: int = -1
var camera: Camera3D
## Contact id -> Node3D of each drawn contact.
var ships: Dictionary = {}

var _stars: MeshInstance3D
var _template: ProceduralShip


func _init() -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Palette.color("background")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.38, 0.42)
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	add_child(sun)
	camera = Camera3D.new()
	camera.near = 0.5
	camera.far = CAMERA_FAR
	camera.current = true
	add_child(camera)
	_stars = MeshInstance3D.new()
	_stars.mesh = _star_mesh()
	add_child(_stars)


## Places the camera (own-ship-centred world axes) and the stars around it.
func place_camera(xform: Transform3D, fov_deg: float) -> void:
	camera.transform = xform
	camera.fov = fov_deg
	_stars.position = xform.origin


## Places every other ship at its minimum-image offset from the own ship, less `origin`
## (the camera's place on the own ship, e.g. a turret mount); frees ships that are gone.
func sync_ships(ctx: StationContext, origin: Vector3 = Vector3.ZERO) -> void:
	var seen: Dictionary = {}
	for id: int in ctx.interp.contact_ids():
		var near: bool = ctx.view.near.has(id)
		if id == ctx.crew.ship or (near_only and not near and id != show_id):
			continue
		seen[id] = true
		if not ships.has(id):
			ships[id] = copy_ship()
			(ships[id] as Node3D).scale = Vector3.ONE * ship_scale
		var node: Node3D = ships[id]
		if near:
			var q: Quaternion = NetCodec.unpack_quat(int(ctx.view.near[id][0]))
			node.basis = Basis(q).scaled(Vector3.ONE * ship_scale)
		node.scale = Vector3.ONE * ship_scale
		node.position = ctx.interp.offset_to(ctx.interp.contact_position(id)) - origin
	for id: int in ships.keys():
		if not seen.has(id):
			(ships[id] as Node3D).queue_free()
			ships.erase(id)


## A new ship model (unscaled), sharing the template's meshes and materials. Needs the
## view in the tree: the template builds when it enters.
func copy_ship() -> Node3D:
	if _template == null:
		_template = ProceduralShip.new()
		_template.wear = wear
		_template.visible = false
		add_child(_template)
	var n: Node3D = Node3D.new()
	for c: Node in _template.get_children():
		n.add_child(c.duplicate())
	add_child(n)
	return n


## Seeded points on a sphere, with a little brightness variation.
static func _star_mesh() -> ArrayMesh:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var verts: PackedVector3Array = PackedVector3Array()
	var cols: PackedColorArray = PackedColorArray()
	for i: int in STARS:
		var v: Vector3 = Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		verts.append(v * STAR_R)
		var b: float = rng.randf_range(0.35, 0.9)
		cols.append(Color(b, b, b * 1.05))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.use_point_size = true
	mat.point_size = 2.0
	mesh.surface_set_material(0, mat)
	return mesh
