class_name HelmView
extends Node3D
## Helm's 3D view (§5.1, S5): the own ship at the origin, world axes, every other ship at
## its minimum-image offset (D124), so precision never depends on where the ship is in
## the site. Cockpit camera at the origin looking along the bow, or the chase camera
## behind and above (FT-HLM-002); comfort sets its roll and field of view (FT-STN-017).
## Other ships are the approved procedural ship (D107), oriented from NEAR when known.
## Dust specks within DUST_BOX give the sense of drift; distant stars give attitude.
## Kept cheap for llvmpipe: no post-processing, one ship mesh set shared by all.

const STAR_COUNT: int = 900
const STAR_DISTANCE: float = 60000.0
const DUST_COUNT: int = 300
const DUST_BOX: float = 600.0
## ProceduralShip is about 5 m long; ships are drawn at about M1's 50 m.
const SHIP_SCALE: float = 9.0
## Chase camera offset in the ship frame (m).
const CHASE_OFFSET: Vector3 = Vector3(0.0, 18.0, 70.0)
## Vertical field of view (degrees), before comfort narrows it.
const FOV_DEG: float = 70.0

var camera: Camera3D
## id -> Node3D of each drawn contact.
var ships: Dictionary = {}
var own_ship: Node3D

var _template: ProceduralShip
var _dust: MultiMesh
var _dust_points: PackedVector3Array = PackedVector3Array()


func _ready() -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.025)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.37, 0.45)
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 40.0, 0.0)
	add_child(sun)
	camera = Camera3D.new()
	camera.fov = FOV_DEG
	camera.near = 0.5
	camera.far = STAR_DISTANCE * 2.0
	add_child(camera)
	camera.current = true
	_template = ProceduralShip.new()
	_template.wear = 1.0
	_template.visible = false
	add_child(_template)
	own_ship = _copy_ship()
	_build_stars()
	_build_dust()


## Places camera, ships and dust for the interpolated state. `chase` swaps the camera.
func show_state(ctx: StationContext, chase: bool) -> void:
	var interp: SnapshotInterpolator = ctx.interp
	var rot: Quaternion = interp.own_rotation()
	var deck: Vector3 = rot * Vector3.UP
	var up: Vector3 = ComfortCamera.plane_up(ctx.settings, rot, ComfortCamera.target_rot(ctx))
	camera.fov = ComfortCamera.fov_deg(ctx.settings, FOV_DEG)
	var origin: Vector3 = (rot * CHASE_OFFSET) if chase else Vector3.ZERO
	camera.transform = Transform3D(ComfortCamera.look(rot * Vector3.FORWARD, up, deck), origin)
	own_ship.visible = chase
	own_ship.transform = Transform3D(Basis(rot).scaled(Vector3.ONE * SHIP_SCALE), Vector3.ZERO)
	_place_ships(ctx)
	_place_dust(interp.own_position())


func _place_ships(ctx: StationContext) -> void:
	var seen: Dictionary = {}
	for id: int in ctx.interp.contact_ids():
		if id == ctx.crew.ship:
			continue
		seen[id] = true
		if not ships.has(id):
			ships[id] = _copy_ship()
		var node: Node3D = ships[id]
		var q: Quaternion = Quaternion.IDENTITY
		if ctx.view.near.has(id):
			q = NetCodec.unpack_quat(int(ctx.view.near[id][0]))
		var offset: Vector3 = ctx.interp.offset_to(ctx.interp.contact_position(id))
		node.transform = Transform3D(Basis(q).scaled(Vector3.ONE * SHIP_SCALE), offset)
	for id: int in ships.keys():
		if not seen.has(id):
			(ships[id] as Node3D).queue_free()
			ships.erase(id)


## A copy of the template ship's meshes (meshes and materials shared).
func _copy_ship() -> Node3D:
	var n: Node3D = Node3D.new()
	for c: Node in _template.get_children():
		n.add_child(c.duplicate())
	add_child(n)
	return n


func _build_stars() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var star: BoxMesh = BoxMesh.new()
	star.size = Vector3.ONE * 70.0
	mm.mesh = star
	mm.instance_count = STAR_COUNT
	for i: int in STAR_COUNT:
		var dir: Vector3 = Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		var b: Basis = Basis().scaled(Vector3.ONE * rng.randf_range(0.5, 1.6))
		mm.set_instance_transform(i, Transform3D(b, dir * STAR_DISTANCE))
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = _unshaded(Color(0.85, 0.88, 1.0))
	add_child(node)


func _build_dust() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	_dust = MultiMesh.new()
	_dust.transform_format = MultiMesh.TRANSFORM_3D
	var speck: BoxMesh = BoxMesh.new()
	speck.size = Vector3.ONE * 0.3
	_dust.mesh = speck
	_dust.instance_count = DUST_COUNT
	for i: int in DUST_COUNT:
		_dust_points.append(Vector3(rng.randf(), rng.randf(), rng.randf()) * DUST_BOX)
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.multimesh = _dust
	node.material_override = _unshaded(Color(0.7, 0.7, 0.75))
	add_child(node)


## Dust is fixed in the site, tiled every DUST_BOX: each speck is drawn at its nearest
## tile's offset from the ship.
func _place_dust(own_pos: Vector3) -> void:
	var half: float = DUST_BOX / 2.0
	for i: int in DUST_COUNT:
		var d: Vector3 = _dust_points[i] - own_pos
		d = Vector3(
			fposmod(d.x + half, DUST_BOX) - half,
			fposmod(d.y + half, DUST_BOX) - half,
			fposmod(d.z + half, DUST_BOX) - half
		)
		_dust.set_instance_transform(i, Transform3D(Basis(), d))


static func _unshaded(colour: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat
