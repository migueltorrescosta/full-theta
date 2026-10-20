## L5 harness scene (FT-TST-003, R2): a lit 3D shape and a UI panel, fixed camera, no animation.
extends Node3D


func _ready() -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.1, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.35, 0.45)
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = env
	add_child(world)

	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	add_child(light)

	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0, 1.2, 4)
	camera.rotation_degrees = Vector3(-15, 0, 0)
	add_child(camera)

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.45, 0.2)
	var torus: MeshInstance3D = MeshInstance3D.new()
	torus.mesh = TorusMesh.new()
	torus.material_override = material
	torus.position = Vector3(0.9, 0.3, 0)
	torus.rotation_degrees = Vector3(60, 20, 0)
	add_child(torus)

	var ui: CanvasLayer = CanvasLayer.new()
	add_child(ui)
	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(24, 24)
	ui.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	panel.add_child(box)
	var label: Label = Label.new()
	label.text = "Helm  ·  thrust 42 %"
	box.add_child(label)
	var button: Button = Button.new()
	button.text = "All stop"
	box.add_child(button)
