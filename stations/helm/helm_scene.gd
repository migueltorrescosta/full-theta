class_name HelmScene
extends SpaceScene
## Helm's 3D view (§5.1, S5) on the shared SpaceScene: cockpit camera at the origin
## looking along the bow, or the chase camera behind and above with the own ship drawn
## (FT-HLM-002); comfort sets its roll and field of view (FT-STN-017). Dust specks within
## DUST_BOX give the sense of drift; the stars give attitude.

const DUST_COUNT: int = 300
const DUST_BOX: float = 500.0
## Each speck sits at its tile position; the offset from the ship wraps into +-DUST_BOX/2.
const DUST_SHADER: String = """
shader_type spatial;
render_mode unshaded;
uniform vec3 own_pos;
uniform float box = 500.0;
void vertex() {
	vec3 d = MODEL_MATRIX[3].xyz - own_pos;
	d = mod(d + 0.5 * box, box) - 0.5 * box;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(VERTEX + d, 1.0);
}
void fragment() {
	ALBEDO = vec3(0.7, 0.7, 0.75);
}
"""
## ProceduralShip is about 5 m long; ships are drawn at about M1's 50 m.
const SHIP_SCALE: float = 9.0
## Chase camera offset in the ship frame (m).
const CHASE_OFFSET: Vector3 = Vector3(0.0, 18.0, 70.0)
## Vertical field of view (degrees), before comfort narrows it.
const FOV_DEG: float = 70.0

var own_ship: ProceduralShip

var _dust_material: ShaderMaterial


func _ready() -> void:
	ship_scale = SHIP_SCALE
	own_ship = copy_ship()
	_build_dust()


func own_model() -> Node3D:
	return own_ship if own_ship != null and own_ship.visible else null


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
	var look: String = ProceduralShip.look_for(ctx.crew.ship_name())
	refresh_ship(own_ship, look)
	own_ship.visible = chase
	own_ship.transform = Transform3D(Basis(rot).scaled(Vector3.ONE * SHIP_SCALE), Vector3.ZERO)
	sync_ships(ctx)
	_place_dust(interp.own_position())


func _build_dust() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var dust: MultiMesh = MultiMesh.new()
	dust.transform_format = MultiMesh.TRANSFORM_3D
	var speck: BoxMesh = BoxMesh.new()
	speck.size = Vector3.ONE * 0.3
	dust.mesh = speck
	dust.instance_count = DUST_COUNT
	for i: int in DUST_COUNT:
		var at: Vector3 = Vector3(rng.randf(), rng.randf(), rng.randf()) * DUST_BOX
		dust.set_instance_transform(i, Transform3D(Basis(), at))
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.multimesh = dust
	# The specks move in the vertex shader, so the box the renderer culls by is the tile.
	node.custom_aabb = AABB(Vector3.ONE * -DUST_BOX, Vector3.ONE * DUST_BOX * 2.0)
	_dust_material = ShaderMaterial.new()
	var shader: Shader = Shader.new()
	shader.code = DUST_SHADER
	_dust_material.shader = shader
	_dust_material.set_shader_parameter("box", DUST_BOX)
	node.material_override = _dust_material
	add_child(node)


## Dust is fixed in the site, tiled every DUST_BOX: the vertex shader draws each speck at its
## nearest tile's offset from the ship (E4, R20-7), so a frame costs one uniform.
func _place_dust(own_pos: Vector3) -> void:
	_dust_material.set_shader_parameter(
		"own_pos",
		Vector3(
			fposmod(own_pos.x, DUST_BOX), fposmod(own_pos.y, DUST_BOX), fposmod(own_pos.z, DUST_BOX)
		)
	)
