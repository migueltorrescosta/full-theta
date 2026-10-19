## S8 view for the L5 harness: one ship at the origin, a camera orbiting it by yaw and pitch
## (yaw 0 looks from behind, 90 from starboard), and a key light fixed to the camera.
extends Node3D

var yaw_degrees: float = 145.0
var pitch_degrees: float = 20.0
var variant: int = 0
var _previous_msaa: Viewport.MSAA = Viewport.MSAA_DISABLED


func _ready() -> void:
	_previous_msaa = get_viewport().msaa_3d
	get_viewport().msaa_3d = Viewport.MSAA_4X

	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.22, 0.25, 0.45)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.32, 0.5)
	env.ambient_light_energy = 0.6
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = env
	add_child(world)

	var camera: Camera3D = Camera3D.new()
	camera.fov = 40
	var yaw: float = deg_to_rad(yaw_degrees)
	var pitch: float = deg_to_rad(pitch_degrees)
	var direction: Vector3 = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	add_child(camera)
	camera.look_at_from_position(direction * 6.0, Vector3.ZERO)

	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -40, 0)
	camera.add_child(light)

	var ship: S8Ship = S8Ship.new()
	ship.variant = variant
	add_child(ship)


func _exit_tree() -> void:
	get_viewport().msaa_3d = _previous_msaa
