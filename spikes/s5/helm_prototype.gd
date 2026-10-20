class_name S5HelmPrototype
extends Node3D
## S5 Helm flight prototype (T012, NAV-3): one ship, the moving target H2, the free mark
## Bravo and the station F1, flown from a cockpit or chase camera with the S5 HUD.
## The sim (spikes/s5/sim/) steps at 60 Hz on its own accumulator (FT-ARC-006); this
## node only feeds it input and draws it.
##
## User args (after `--`): --s5-autopilot flies the intercept by itself,
## --s5-no-help starts with the help hidden, --s5-quit-after=SECONDS quits with a
## summary line, --s5-screenshot=PATH saves the
## window just before quitting.

const DUST_COUNT: int = 500
const DUST_BOX: float = 600.0
const STAR_COUNT: int = 1500
const STAR_DISTANCE: float = 60000.0
const CHASE_OFFSET: Vector3 = Vector3(0.0, 22.0, 85.0)
const RADAR_RANGES: Array[float] = [2000.0, 10000.0, 50000.0]

var world: S5World
var mapper: S5InputMapper = S5InputMapper.new()
var stepper: S5FixedStep = S5FixedStep.new()
var autopilot: S5Autopilot = null
var camera: Camera3D
var chase: bool = false
var show_help: bool = true
var radar_range_index: int = 1
## Wall-clock-free run timer for the intercept drill: sim time when H2 was first within
## the capture radius, or -1.
var intercept_time: float = -1.0
var last_input: S5HelmInput = S5HelmInput.new()

var _quit_after: float = -1.0
var _screenshot: String = ""
var _ship_mesh: MeshInstance3D
var _target_mesh: MeshInstance3D
var _station_mesh: Node3D
var _dust: MultiMesh
var _stars: MultiMeshInstance3D
var _prev_pos: Vector3
var _prev_rot: Quaternion
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _elapsed: float = 0.0


func _ready() -> void:
	S5InputMapper.register()
	_parse_args()
	_rng.seed = 5
	_reset_world()
	_build_scene()
	var hud_layer: CanvasLayer = CanvasLayer.new()
	add_child(hud_layer)
	var hud: S5Hud = S5Hud.new()
	hud.proto = self
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_layer.add_child(hud)
	if DisplayServer.get_name() != "headless" and autopilot == null:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _parse_args() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--s5-autopilot":
			autopilot = S5Autopilot.new()
		elif arg == "--s5-no-help":
			show_help = false
		elif arg.begins_with("--s5-quit-after="):
			_quit_after = arg.get_slice("=", 1).to_float()
		elif arg.begins_with("--s5-screenshot="):
			_screenshot = arg.get_slice("=", 1)


func _reset_world() -> void:
	world = S5World.new()
	intercept_time = -1.0
	_prev_pos = world.ship.position
	_prev_rot = world.ship.orientation


func _unhandled_input(event: InputEvent) -> void:
	var captured: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.is_pressed() and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("s5_fullscreen"):
		var full: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN
		)
	mapper.handle_event(event, captured)


func _process(delta: float) -> void:
	_elapsed += delta
	_consume_ui_edges()
	var input: S5HelmInput = mapper.read(delta)
	var ticks: int = stepper.advance(delta)
	for i: int in ticks:
		_prev_pos = world.ship.position
		_prev_rot = world.ship.orientation
		if autopilot != null:
			input = autopilot.input_for(world, world.items[S5World.TARGET])
		world.step(input)
		last_input = input
		if i == 0:
			mapper.consume_edges()
			input.all_stop_pressed = false
			input.decoupled_pressed = false
			input.level_pressed = false
			input.select_pressed = false
		var target: S5Item = world.items[S5World.TARGET]
		var dist: float = (target.position - world.ship.position).length()
		if intercept_time < 0.0 and dist < S5Scenarios.CAPTURE_RADIUS:
			intercept_time = world.time
	_update_visuals(stepper.alpha())
	if _quit_after >= 0.0 and _elapsed >= _quit_after:
		_finish()


func _consume_ui_edges() -> void:
	if mapper.reset_pressed:
		_reset_world()
	if mapper.chase_toggled:
		chase = not chase
	if mapper.help_toggled:
		show_help = not show_help
	if mapper.zoom_pressed:
		radar_range_index = (radar_range_index + 1) % RADAR_RANGES.size()
	if mapper.mark_ahead:
		world.place_mark(world.ship.position + world.ship.forward() * 5000.0)
	if mapper.mark_here:
		world.place_mark(world.ship.position)
	mapper.reset_pressed = false
	mapper.chase_toggled = false
	mapper.help_toggled = false
	mapper.zoom_pressed = false
	mapper.mark_ahead = false
	mapper.mark_here = false


func radar_range() -> float:
	return RADAR_RANGES[radar_range_index]


func _finish() -> void:
	if _screenshot != "":
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(_screenshot)
	var target: S5Item = world.items[S5World.TARGET]
	print(
		(
			"s5: t=%.1f s ticks=%d dist_H2=%.0f m intercept=%.1f s propellant=%.0f kg"
			% [
				world.time,
				world.tick,
				(target.position - world.ship.position).length(),
				intercept_time,
				world.ship.propellant,
			]
		)
	)
	get_tree().quit(0)
	set_process(false)


func _build_scene() -> void:
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
	camera.fov = 70.0
	camera.near = 0.5
	camera.far = 150000.0
	add_child(camera)
	camera.make_current()

	_ship_mesh = _mesh(_prism(Vector3(14.0, 6.0, 36.0)), Color(0.75, 0.78, 0.85), false)
	_target_mesh = _mesh(_prism(Vector3(24.0, 10.0, 48.0)), Color(1.0, 0.55, 0.15), true)
	_station_mesh = Node3D.new()
	add_child(_station_mesh)
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(120.0, 120.0, 120.0)
	var ring: TorusMesh = TorusMesh.new()
	ring.inner_radius = 220.0
	ring.outer_radius = 250.0
	for m: Mesh in [box, ring]:
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = _material(Color(0.3, 0.8, 0.95), true)
		_station_mesh.add_child(mi)

	# Dust close by, so speed and drift are visible.
	_dust = MultiMesh.new()
	_dust.transform_format = MultiMesh.TRANSFORM_3D
	var speck: BoxMesh = BoxMesh.new()
	speck.size = Vector3(0.3, 0.3, 0.3)
	_dust.mesh = speck
	_dust.instance_count = DUST_COUNT
	for i: int in DUST_COUNT:
		var p: Vector3 = Vector3(
			_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)
		)
		_dust.set_instance_transform(i, Transform3D(Basis(), p * DUST_BOX * 0.5))
	var dust_node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	dust_node.multimesh = _dust
	dust_node.material_override = _material(Color(0.7, 0.7, 0.75), true)
	add_child(dust_node)

	# Stars at a fixed distance that follow the camera, for attitude.
	var stars: MultiMesh = MultiMesh.new()
	stars.transform_format = MultiMesh.TRANSFORM_3D
	var star: BoxMesh = BoxMesh.new()
	star.size = Vector3(70.0, 70.0, 70.0)
	stars.mesh = star
	stars.instance_count = STAR_COUNT
	for i: int in STAR_COUNT:
		var dir: Vector3 = Vector3(_rng.randfn(), _rng.randfn(), _rng.randfn()).normalized()
		var s: float = _rng.randf_range(0.5, 1.6)
		stars.set_instance_transform(
			i, Transform3D(Basis().scaled(Vector3.ONE * s), dir * STAR_DISTANCE)
		)
	_stars = MultiMeshInstance3D.new()
	_stars.multimesh = stars
	_stars.material_override = _material(Color(0.85, 0.88, 1.0), true)
	add_child(_stars)


func _prism(size: Vector3) -> PrismMesh:
	var p: PrismMesh = PrismMesh.new()
	p.size = size
	return p


func _mesh(m: Mesh, colour: Color, unshaded: bool) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = _material(colour, unshaded)
	add_child(mi)
	return mi


func _material(colour: Color, unshaded: bool) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = colour
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


## Basis for a prism (tip along +Y) pointing its tip along `fwd`.
func _prism_basis(rot: Quaternion) -> Basis:
	return Basis(rot) * Basis(Vector3.RIGHT, -PI / 2.0)


func _update_visuals(alpha: float) -> void:
	var pos: Vector3 = _prev_pos.lerp(world.ship.position, alpha)
	var rot: Quaternion = _prev_rot.slerp(world.ship.orientation, alpha)
	var basis: Basis = Basis(rot)
	_ship_mesh.transform = Transform3D(_prism_basis(rot), pos)
	_ship_mesh.visible = chase
	if chase:
		camera.transform = Transform3D(basis, pos + basis * CHASE_OFFSET)
	else:
		camera.transform = Transform3D(basis, pos)

	var target: S5Item = world.items[S5World.TARGET]
	var heading: Quaternion = Quaternion(Vector3.FORWARD, target.velocity.normalized())
	_target_mesh.transform = Transform3D(_prism_basis(heading), target.position)
	_station_mesh.position = world.items[S5World.STATION].position
	_stars.position = camera.global_position

	var half: float = DUST_BOX * 0.5
	for i: int in DUST_COUNT:
		var t: Transform3D = _dust.get_instance_transform(i)
		var d: Vector3 = t.origin - pos
		if absf(d.x) > half or absf(d.y) > half or absf(d.z) > half:
			d = Vector3(
				fposmod(d.x + half, DUST_BOX) - half,
				fposmod(d.y + half, DUST_BOX) - half,
				fposmod(d.z + half, DUST_BOX) - half
			)
			t.origin = pos + d
			_dust.set_instance_transform(i, t)
