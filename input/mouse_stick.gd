class_name MouseStick
extends RefCounted
## Helm's mouse virtual stick (S5, docs/spikes/S5.md): mouse motion deflects a stick
## that re-centres with a 0.12 s half-life, so the turn rate follows mouse speed and
## the nose stops when the mouse stops. x right, y down, each -1..1.

const HALF_LIFE_S: float = 0.12
## Stick deflection per pixel of motion (S5's sensitivity).
const SENSITIVITY: float = 0.006

var value: Vector2 = Vector2.ZERO


func move(relative: Vector2) -> void:
	value = (value + relative * SENSITIVITY).limit_length(1.0)


func decay(delta: float) -> void:
	value *= pow(0.5, delta / HALF_LIFE_S)
