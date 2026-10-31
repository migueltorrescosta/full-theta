class_name SpaceView
extends Node3D
## The 3D space behind Helm's cockpit, the Weapons turret camera and the main screen:
## background, ambient and sun, one camera, a star backdrop and the other ships. Put it in a
## SubViewport with its own world. The own ship sits at the origin with world axes; every
## other ship is drawn at its minimum-image offset (D124), so precision never depends on
## where the ship is in the cube. Ships are the approved ship (D107) in the baked look of
## their name (ProceduralShip, D308, D309), oriented from NEAR when known (the last known
## orientation otherwise). Kept cheap for llvmpipe: no post-processing, the stars three
## point meshes and the galaxy band one strip.

const STARS: int = 2600
const BRIGHT_STARS: int = 160
const BAND_STARS: int = 5000
## Star sphere radius (m). It follows the camera position, so stars never parallax.
const STAR_R: float = 9000.0
const CAMERA_FAR: float = 30000.0
## The galaxy band: its great circle's normal, the spread of its stars (rad, one standard
## deviation of the latitude) and the half-width of its haze (rad).
const BAND_NORMAL: Vector3 = Vector3(0.35, 0.85, 0.4)
const BAND_SPREAD: float = 0.1
const BAND_HAZE: float = 0.32
const HAZE_SEGMENTS: int = 96
const HAZE_ROWS: int = 8
const HAZE_PEAK: float = 0.2  # haze brightness on the band's centre line

## Scale of every ship model (ProceduralShip is about 5 m long).
var ship_scale: float = 1.0
## Draw only contacts with a NEAR orientation (within 2 km), as the main screen does.
var near_only: bool = false
## A contact drawn even when near_only would drop it (the main screen's target, which can
## be farther than NEAR's range): its orientation is the last known, else the default.
var show_id: int = -1
var camera: Camera3D
## Contact id -> Node3D of each drawn contact.
var ships: Dictionary = {}

## The effects (hits, shields, explosions, jumps) of the sim events of the bound context.
var vfx: VfxLayer

var _stars: MeshInstance3D
var _ctx: StationContext


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
	vfx = VfxLayer.new(self)
	add_child(vfx)


## Places the camera (own-ship-centred world axes) and the stars around it.
func place_camera(xform: Transform3D, fov_deg: float) -> void:
	camera.transform = Transform3D(xform.basis * vfx.shake_basis(), xform.origin)
	camera.fov = fov_deg
	_stars.position = xform.origin


## Places every other ship at its minimum-image offset from the own ship, less `origin`
## (the camera's place on the own ship, e.g. a turret mount); frees ships that are gone.
func sync_ships(ctx: StationContext, origin: Vector3 = Vector3.ZERO) -> void:
	_bind(ctx)
	var seen: Dictionary = {}
	for id: int in ctx.interp.contact_ids():
		var near: bool = ctx.view.near.has(id)
		if id == ctx.crew.ship or (near_only and not near and id != show_id):
			continue
		seen[id] = true
		var look: String = ProceduralShip.look_for(ctx.crew.ship_name(id))
		if not ships.has(id):
			ships[id] = copy_ship(look)
		var node: ProceduralShip = ships[id]
		if node.look != look:
			node.set_look(look)
		if near:
			var q: Quaternion = NetCodec.unpack_quat(int(ctx.view.near[id][0]))
			node.basis = Basis(q).scaled(Vector3.ONE * ship_scale)
		node.scale = Vector3.ONE * ship_scale
		node.position = ctx.interp.offset_to(ctx.interp.contact_position(id)) - origin
	for id: int in ships.keys():
		if not seen.has(id):
			(ships[id] as Node3D).queue_free()
			ships.erase(id)


## The model effects follow for ship `id`: the drawn contact, the own ship's model when one
## is drawn (Helm's chase view), else null.
func model_of(id: int, mine: bool) -> Node3D:
	if mine:
		return own_model()
	return ships.get(id)


## The own ship's drawn model, or null when this view draws none.
func own_model() -> Node3D:
	return null


func _bind(ctx: StationContext) -> void:
	if _ctx == ctx:
		return
	_ctx = ctx
	ctx.crew.sim_event.connect(_on_sim_event)


func _on_sim_event(kind: StringName, p: Dictionary) -> void:
	vfx.comfort = _ctx.settings.comfort
	vfx.on_event(kind, p, _ctx.crew.ship, _ctx.interp.own_rotation())


## A new ship model of `look` (unscaled) in the view, sharing the baked meshes and
## materials of every ship of the look.
func copy_ship(look: String = ProceduralShip.GENERIC) -> ProceduralShip:
	var n: ProceduralShip = ProceduralShip.new()
	n.look = look
	add_child(n)
	return n


## The backdrop, one mesh of four surfaces on a sphere of STAR_R: a field of stars, a few
## bright ones, the stars of the galaxy band (denser and dimmer along a great circle) and
## the band's faint haze. Seeded, so it is the same on every run.
static func _star_mesh() -> ArrayMesh:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var mesh: ArrayMesh = ArrayMesh.new()
	var field: PackedVector3Array = PackedVector3Array()
	var field_cols: PackedColorArray = PackedColorArray()
	for i: int in STARS:
		field.append(_sphere_point(rng) * STAR_R)
		var b: float = 0.45 + 0.55 * pow(rng.randf(), 2.0)
		field_cols.append(Color(b, b, b * 1.05))
	_add_points(mesh, field, field_cols, 2.0)
	var bright: PackedVector3Array = PackedVector3Array()
	var bright_cols: PackedColorArray = PackedColorArray()
	for i: int in BRIGHT_STARS:
		bright.append(_sphere_point(rng) * STAR_R)
		var warm: float = rng.randf()
		bright_cols.append(Color(1.0, 0.92 + 0.08 * warm, 1.0 - 0.2 * warm))
	_add_points(mesh, bright, bright_cols, 3.5)
	var axis_u: Vector3 = BAND_NORMAL.normalized().cross(Vector3.RIGHT).normalized()
	var axis_v: Vector3 = BAND_NORMAL.normalized().cross(axis_u)
	var band: PackedVector3Array = PackedVector3Array()
	var band_cols: PackedColorArray = PackedColorArray()
	for i: int in BAND_STARS:
		var lon: float = rng.randf() * TAU
		var lat: float = rng.randfn(0.0, BAND_SPREAD)
		band.append(_band_point(axis_u, axis_v, lon, lat) * STAR_R)
		var b: float = 0.25 + 0.4 * pow(rng.randf(), 2.0)
		band_cols.append(Color(b * 0.95, b, b * 1.1))
	_add_points(mesh, band, band_cols, 2.0)
	_add_haze(mesh, rng, axis_u, axis_v)
	return mesh


static func _sphere_point(rng: RandomNumberGenerator) -> Vector3:
	return Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()


## The unit vector at longitude `lon` and latitude `lat` of the band's great circle.
static func _band_point(u: Vector3, v: Vector3, lon: float, lat: float) -> Vector3:
	var along: Vector3 = u * cos(lon) + v * sin(lon)
	return (along * cos(lat) + BAND_NORMAL.normalized() * sin(lat)).normalized()


## Adds a surface of points, `size` pixels each, in the given colours.
static func _add_points(
	mesh: ArrayMesh, verts: PackedVector3Array, cols: PackedColorArray, size: float
) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.use_point_size = true
	mat.point_size = size
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)


## Adds the band's haze: a strip round the great circle, added to what is behind it, fading
## out to either side (a Gaussian in latitude) and patchy along the band (smooth noise in
## longitude).
static func _add_haze(mesh: ArrayMesh, rng: RandomNumberGenerator, u: Vector3, v: Vector3) -> void:
	var cells: PackedFloat32Array = PackedFloat32Array()
	for i: int in 12:
		cells.append(rng.randf_range(0.35, 1.0))
	var verts: PackedVector3Array = PackedVector3Array()
	var cols: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	for k: int in HAZE_SEGMENTS + 1:
		var lon: float = TAU * k / HAZE_SEGMENTS
		var g: float = float(k % HAZE_SEGMENTS) * cells.size() / HAZE_SEGMENTS
		var i0: int = int(g)
		var density: float = lerpf(
			cells[i0], cells[(i0 + 1) % cells.size()], smoothstep(0.0, 1.0, g - i0)
		)
		for row: int in HAZE_ROWS + 1:
			var lat: float = lerpf(-BAND_HAZE, BAND_HAZE, float(row) / HAZE_ROWS)
			var a: float = HAZE_PEAK * density * exp(-pow(lat / (BAND_HAZE * 0.45), 2.0))
			verts.append(_band_point(u, v, lon, lat) * STAR_R)
			cols.append(Color(0.5, 0.55, 0.8, a))
		if k < HAZE_SEGMENTS:
			for row: int in HAZE_ROWS:
				var q: int = k * (HAZE_ROWS + 1) + row
				var n: int = q + HAZE_ROWS + 1
				indices.append_array([q, n, q + 1, q + 1, n, n + 1])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
