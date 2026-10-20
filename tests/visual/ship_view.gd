## Ship view for the L5 harness (S8 v2): the semi-realistic ship at the origin, a camera orbiting
## it by yaw and pitch (yaw 0 looks from behind, 90 from starboard), a key, fill and rim
## light fixed to the camera, a procedural sky for ambient light and reflections, and
## filmic tonemapping.
extends Node3D

var yaw_degrees: float = 145.0
var pitch_degrees: float = 20.0
var distance: float = 8.2
var wear: float = 0.0
var tonemap: int = Environment.TONE_MAPPER_AGX
var shadows: bool = true
var _previous_msaa: Viewport.MSAA = Viewport.MSAA_DISABLED


func _ready() -> void:
	_previous_msaa = get_viewport().msaa_3d
	get_viewport().msaa_3d = Viewport.MSAA_4X

	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.05, 0.06, 0.1)
	sky_material.sky_horizon_color = Color(0.2, 0.23, 0.3)
	sky_material.ground_horizon_color = Color(0.2, 0.23, 0.3)
	sky_material.ground_bottom_color = Color(0.03, 0.035, 0.05)
	sky_material.sun_angle_max = 0.0
	var sky: Sky = Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_64

	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.15, 0.2)
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = tonemap as Environment.ToneMapper
	env.tonemap_exposure = 1.0
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = env
	add_child(world)

	var camera: Camera3D = Camera3D.new()
	camera.fov = 40
	var yaw: float = deg_to_rad(yaw_degrees)
	var pitch: float = deg_to_rad(pitch_degrees)
	var direction: Vector3 = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	add_child(camera)
	camera.look_at_from_position(direction * distance, Vector3(0, 0, 0.1))

	_light(camera, Vector3(-45, -65, 0), Color(1.0, 0.96, 0.9), 2.2, shadows)  # key
	_light(camera, Vector3(-10, 60, 0), Color(0.6, 0.7, 0.9), 0.45, false)  # fill
	_light(camera, Vector3(-20, 160, 0), Color(0.75, 0.95, 0.88), 0.8, false)  # rim

	var ship: ProceduralShip = ProceduralShip.new()
	ship.wear = wear
	add_child(ship)


func _light(
	parent: Node3D, rotation_deg: Vector3, colour: Color, energy: float, shadow: bool
) -> void:
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = rotation_deg
	light.light_color = colour
	light.light_energy = energy
	light.shadow_enabled = shadow
	light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	light.directional_shadow_max_distance = 20.0
	parent.add_child(light)


func _exit_tree() -> void:
	get_viewport().msaa_3d = _previous_msaa
