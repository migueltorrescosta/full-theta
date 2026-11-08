class_name GpuWarm
extends SubViewport
## Draws the first-use materials once, off screen, while the lobby waits (R20-11, R21-6):
## one baked ship (hull, glass, glow and decal materials), a burst and a shield effect. A
## browser links a program on its first draw, so without this the first hit of a fight
## stalls a frame. It frees itself after a few frames.

const FRAMES: int = 3

var _look: String
var _left: int = FRAMES


func _init(look: String = ProceduralShip.GENERIC) -> void:
	_look = look
	size = Vector2i(16, 16)
	own_world_3d = true
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	msaa_3d = Viewport.MSAA_DISABLED
	name = "GpuWarm"


func _ready() -> void:
	var cam: Camera3D = Camera3D.new()
	cam.current = true
	add_child(cam)
	add_child(DirectionalLight3D.new())
	var ship: ProceduralShip = ProceduralShip.new()
	ship.look = _look
	ship.position = Vector3(0.0, 0.0, -8.0)
	add_child(ship)
	for kind: VfxEffect.Kind in [VfxEffect.Kind.HIT, VfxEffect.Kind.SHIELD]:
		var e: VfxEffect = VfxEffect.make(kind, false)
		e.frozen = true
		e.position = Vector3(0.0, 0.0, -8.0)
		add_child(e)


func _process(_delta: float) -> void:
	_left -= 1
	if _left <= 0:
		queue_free()
