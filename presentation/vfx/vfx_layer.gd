class_name VfxLayer
extends Node3D
## The effects of one SpaceScene (#12, E14), spawned from the sim events the client already
## receives (the ones the sound strand uses): a hit on a ship (a spark on the hull, or the
## shield's shell when the shields took all of it: the event's `value`, the energy that got
## through, is 0), an explosion, the jump drive spooling and arriving. The own ship's hits
## and destruction also shake the camera. Comfort (FT-STN-017) turns the flashes and the
## shake off. Few effects at once (MAX_LIVE), each a shader quad that frees itself.

## Most effects alive at once; the oldest goes first.
const MAX_LIVE: int = 12
## Camera shake (rad) at full strength, its decay (per s) and its pace (rad/s).
const SHAKE_RAD: float = 0.012
const SHAKE_DECAY: float = 2.5
const SHAKE_HZ: float = 38.0
## How far in front of a camera at the own ship a hit on it shows (m), when no model of the
## own ship is drawn.
const COCKPIT_REACH: float = 8.0

var space: SpaceScene
## Whether comfort is on; set by the SpaceScene from the settings.
var comfort: bool = false
var _shake: float = 0.0
var _clock: float = 0.0
var _count: int = 0


func _init(p_space: SpaceScene = null) -> void:
	space = p_space
	name = "Vfx"


func _process(delta: float) -> void:
	_clock += delta
	_shake = maxf(_shake - SHAKE_DECAY * delta, 0.0)


## Number of effects alive.
func live() -> int:
	var n: int = 0
	for c: Node in get_children():
		n += 1 if c is VfxEffect and not c.is_queued_for_deletion() else 0
	for ship: Node3D in space.ships.values():
		for c: Node in ship.get_children():
			n += 1 if c is VfxEffect and not c.is_queued_for_deletion() else 0
	return n


## A sim event (CrewState.sim_event payload: ship, other, value, vector, tag). `own` is the
## own ship's id, `own_rot` its orientation (world).
func on_event(kind: StringName, p: Dictionary, own: int, own_rot: Quaternion) -> void:
	var id: int = int(p.get("ship", -1))
	var mine: bool = id == own
	var parent: Node3D = space.model_of(id, mine)
	match kind:
		&"hit":
			var dir: Vector3 = (p.get("vector", Vector3.FORWARD) as Vector3).normalized()
			if dir == Vector3.ZERO:
				dir = Vector3.FORWARD
			var absorbed: bool = float(p.get("value", 0.0)) <= 0.0
			if parent != null:
				if absorbed:
					attach(parent, VfxEffect.Kind.SHIELD, Vector3.ZERO, dir)
				else:
					attach(parent, VfxEffect.Kind.HIT, dir * 2.4, dir)
			elif mine:
				var at: Vector3 = own_rot * dir * COCKPIT_REACH
				attach(space, VfxEffect.Kind.HIT, at, dir)
			if mine:
				kick(0.35 if absorbed else 0.8)
		&"destroyed":
			if parent != null:
				attach(
					space, VfxEffect.Kind.EXPLOSION, parent.position, Vector3.ZERO, space.ship_scale
				)
			if mine:
				kick(1.0)
		&"jump_spool":
			if parent != null:
				attach(parent, VfxEffect.Kind.JUMP_SPOOL, Vector3.ZERO, Vector3.ZERO)
		&"jump_arrive":
			if parent != null:
				attach(parent, VfxEffect.Kind.JUMP_ARRIVE, Vector3.ZERO, Vector3.ZERO)


## Adds an effect of `kind` under `parent` at `at` (in the parent's frame) and returns it.
## `direction` is the hit direction; `scale_by` scales a quad placed in the space.
func attach(
	parent: Node3D, kind: VfxEffect.Kind, at: Vector3, direction: Vector3, scale_by: float = 1.0
) -> VfxEffect:
	_trim()
	var e: VfxEffect = VfxEffect.make(kind, comfort, direction, float(_count % 7) / 7.0)
	_count += 1
	e.position = at
	e.scale = Vector3.ONE * scale_by
	parent.add_child(e)
	return e


## Frees the oldest effects so that adding one keeps within MAX_LIVE.
func _trim() -> void:
	var all: Array[VfxEffect] = []
	for c: Node in space.get_children():
		if c is VfxEffect and not c.is_queued_for_deletion():
			all.append(c)
	for ship: Node3D in space.ships.values():
		for c: Node in ship.get_children():
			if c is VfxEffect and not c.is_queued_for_deletion():
				all.append(c)
	while all.size() >= MAX_LIVE:
		all.pop_front().queue_free()


## Shakes the camera by `amount` (0..1); nothing with comfort on.
func kick(amount: float) -> void:
	if not comfort:
		_shake = minf(_shake + amount, 1.0)


## The camera's shake now: a small rotation, identity at rest or with comfort on.
func shake_basis() -> Basis:
	if comfort or _shake <= 0.0:
		return Basis.IDENTITY
	var amp: float = SHAKE_RAD * _shake * _shake
	var t: float = _clock * SHAKE_HZ
	return Basis.from_euler(
		Vector3(sin(t) * amp, sin(t * 1.31 + 1.0) * amp, sin(t * 0.77 + 2.0) * amp)
	)


## Current shake strength 0..1.
func shake_level() -> float:
	return _shake
