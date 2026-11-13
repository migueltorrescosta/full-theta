## One frame of an effect (#12, E14) for the L5 harness: a SpaceScene with one generic ship
## 12 m ahead of the camera and the effect named in `effect` ("hit", "shield", "explosion",
## "jump_spool" or "jump_arrive") frozen at `age` (0..1 of its duration). `comfort` draws it
## the way the comfort setting does.
extends Node3D

var effect: String = "hit"
var age: float = 0.35
var comfort: bool = false
## Camera position, looking at the ship (m).
var eye: Vector3 = Vector3(5.0, 3.0, 10.0)


func _ready() -> void:
	var space: SpaceScene = SpaceScene.new()
	add_child(space)
	var ship: ProceduralShip = space.copy_ship()
	ship.basis = Basis.from_euler(Vector3(0.0, deg_to_rad(-25.0), 0.0))
	space.ships[1] = ship
	space.vfx.comfort = comfort
	var xform: Transform3D = Transform3D(Basis(), eye).looking_at(Vector3.ZERO, Vector3.UP)
	space.place_camera(xform, 50.0)
	var fx: VfxEffect = null
	match effect:
		"hit":
			fx = space.vfx.attach(
				ship, VfxEffect.Kind.HIT, Vector3(0.9, 0.5, 0.6) * 2.0, Vector3.ZERO
			)
		"shield":
			fx = space.vfx.attach(
				ship, VfxEffect.Kind.SHIELD, Vector3.ZERO, Vector3(0.7, 0.3, 0.65)
			)
		"explosion":
			fx = space.vfx.attach(space, VfxEffect.Kind.EXPLOSION, Vector3.ZERO, Vector3.ZERO)
		"jump_spool":
			fx = space.vfx.attach(ship, VfxEffect.Kind.JUMP_SPOOL, Vector3.ZERO, Vector3.ZERO)
		"jump_arrive":
			fx = space.vfx.attach(ship, VfxEffect.Kind.JUMP_ARRIVE, Vector3.ZERO, Vector3.ZERO)
	fx.frozen = true
	fx.set_age(age * fx.duration)
