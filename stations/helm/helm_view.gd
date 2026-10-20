class_name HelmView
extends SpaceView
## Helm's 3D view (§5.1, S5) on the shared SpaceView: cockpit camera at the origin
## looking along the bow, or the chase camera behind and above with the own ship drawn
## (FT-HLM-002); comfort sets its roll and field of view (FT-STN-017). Dust specks within
## DUST_BOX give the sense of drift; the stars give attitude.

const DUST_COUNT: int = 300
const DUST_BOX: float = 500.0
## ProceduralShip is about 5 m long; ships are drawn at about M1's 50 m.
const SHIP_SCALE: float = 9.0
## Chase camera offset in the ship frame (m).
const CHASE_OFFSET: Vector3 = Vector3(0.0, 18.0, 70.0)
## Vertical field of view (degrees), before comfort narrows it.
const FOV_DEG: float = 70.0

var own_ship: Node3D

var _dust: MultiMesh
var _dust_points: PackedVector3Array = PackedVector3Array()


func _ready() -> void:
	ship_scale = SHIP_SCALE
	wear = 1.0
	own_ship = copy_ship()
	_build_dust()


## Places camera, ships and dust for the interpolated state. `chase` swaps the camera.
func show_state(ctx: StationContext, chase: bool) -> void:
	var interp: SnapshotInterpolator = ctx.interp
	var rot: Quaternion = interp.own_rotation()
	var deck: Vector3 = rot * Vector3.UP
	var up: Vector3 = ComfortCamera.plane_up(ctx.settings, rot, ComfortCamera.target_rot(ctx))
	var origin: Vector3 = (rot * CHASE_OFFSET) if chase else Vector3.ZERO
	place_camera(
		Transform3D(ComfortCamera.look(rot * Vector3.FORWARD, up, deck), origin),
		ComfortCamera.fov_deg(ctx.settings, FOV_DEG)
	)
	own_ship.visible = chase
	own_ship.transform = Transform3D(Basis(rot).scaled(Vector3.ONE * SHIP_SCALE), Vector3.ZERO)
	sync_ships(ctx)
	_place_dust(interp.own_position())


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
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.7, 0.75)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	node.material_override = mat
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
