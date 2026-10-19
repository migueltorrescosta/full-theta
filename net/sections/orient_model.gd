class_name OrientModel
extends RefCounted
## Orientation model of one faction, shared by its ships' NearSections (promoted from
## S9Orient): orientation and angular velocity of every contact near one of the
## faction's viewed ships, dead reckoned with the angular velocity. A contact is
## refreshed when the extrapolation is off by more than tol_deg, so the check runs
## once per contact per snapshot, not once per observing ship.
##
## Model: id -> [int packed quaternion, Vector3i angular velocity, int tick].

const MAX_AGE: int = 30000

var model: Dictionary = {}
## Ids refreshed by the last update.
var refreshed: Dictionary = {}
var _cos_half_tol: float = 1.0
## Decoded copy of the model: id -> [Quaternion, axis, rad per tick, tick].
var _pred: Dictionary = {}


func _init(tol_deg: float = 1.0) -> void:
	_cos_half_tol = cos(deg_to_rad(tol_deg) * 0.5)


## Refreshes the contacts in `ids` (a set) and drops the others.
func update(world: SimWorld, ids: Dictionary) -> void:
	refreshed = {}
	var tick: int = world.tick
	for id: int in ids:
		var q: Quaternion = world.kin.rot[id]
		var cached: Array = _pred.get(id, [])
		if not cached.is_empty():
			var dt: int = tick - int(cached[3])
			var pred: Quaternion = cached[0]
			var rate: float = cached[2]
			if rate > 0.0:
				pred = pred * Quaternion(cached[1], rate * dt)
			if absf(pred.dot(q)) >= _cos_half_tol and dt < MAX_AGE:
				continue
		var bits: int = NetCodec.pack_quat(q)
		var w: Vector3i = NetCodec.quant_ang(world.kin.ang_vel[id])
		model[id] = [bits, w, tick]
		var wf: Vector3 = NetCodec.ang_of(w)
		var r: float = wf.length()
		var moving: bool = r > 1.0e-6
		_pred[id] = [
			NetCodec.unpack_quat(bits),
			wf / r if moving else Vector3.UP,
			r / NetCodec.TICK_HZ if moving else 0.0,
			tick
		]
		refreshed[id] = true
	for id: int in model.keys():
		if not ids.has(id):
			model.erase(id)
			_pred.erase(id)
