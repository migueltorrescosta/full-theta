class_name S9Orient
extends RefCounted
## Orientation model of one faction, shared by its ships' S9Near sections:
## orientation and angular velocity of every contact near one of its player
## ships, dead reckoned with the angular velocity. A contact is refreshed when
## the extrapolation is off by more than `tol_deg`, so the check runs once per
## contact per snapshot, not once per observing ship.
##
## Model: id -> [int packed quaternion, Vector3i angular velocity, int tick].

const MAX_AGE: int = 30000

var model: Dictionary = {}
## Ids refreshed by the last update.
var refreshed: Dictionary = {}
var records: int = 0
var _cos_half_tol: float = 1.0
## Decoded copy of the model: id -> [Quaternion, axis, rad per tick].
var _pred: Dictionary = {}


func _init(tol_deg: float = 1.0) -> void:
	_cos_half_tol = cos(deg_to_rad(tol_deg) * 0.5)


## Refreshes the contacts in `ids` (any order) and drops the others.
func update(world: S9World, ids: Dictionary, tick: int) -> void:
	refreshed = {}
	for id: int in ids:
		var q: Quaternion = world.ship_rot(id)
		var cached: Array = _pred.get(id, [])
		if not cached.is_empty():
			var dt: int = tick - int(cached[3])
			var pred: Quaternion = cached[0]
			var rate: float = cached[2]
			if rate > 0.0:
				pred = pred * Quaternion(cached[1], rate * dt)
			if absf(pred.dot(q)) >= _cos_half_tol and dt < MAX_AGE:
				continue
		var bits: int = S9Codec.pack_quat(q)
		var w: Vector3i = S9Codec.quant_ang(world.ship_ang(id))
		model[id] = [bits, w, tick]
		var wf: Vector3 = S9Codec.ang_of(w)
		var r: float = wf.length()
		var moving: bool = r > 1.0e-6
		_pred[id] = [
			S9Codec.unpack_quat(bits),
			wf / r if moving else Vector3.UP,
			r / S9Codec.TICK_HZ if moving else 0.0,
			tick
		]
		refreshed[id] = true
		records += 1
	if model.size() > ids.size():
		for id: int in model.keys():
			if not ids.has(id):
				model.erase(id)
				_pred.erase(id)
