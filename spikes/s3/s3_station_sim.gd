class_name S3StationSim
extends S4FakeSim
## S4's stub sim plus an Engineering model per ship, whose pips and heat ride
## in the snapshots. Every seat is the Engineering station of a ship.

var _eng: Array[S3EngineeringModel] = []


func _init(
	ship_count: int = 6, contact_count: int = 40, layout: int = 2048, seed_value: int = 1
) -> void:
	super(ship_count, contact_count, layout, seed_value)
	for i: int in range(ship_count):
		_eng.append(S3EngineeringModel.new())


func step(dt: float) -> Dictionary:
	for m: S3EngineeringModel in _eng:
		m.step(dt)
	return super(dt)


func state() -> Dictionary:
	var out: Dictionary = super()
	for i: int in range(_eng.size()):
		var ship: Dictionary = out[i]
		ship["pips"] = _eng[i].pips.duplicate()
		ship["heat"] = _eng[i].heat.duplicate()
	return out


func seat_for(index: int) -> Dictionary:
	return {"ship": index % ships, "station": "engineering"}


func set_pips(ship: int, system: int, value: int) -> int:
	if ship < 0 or ship >= _eng.size():
		return -1
	return _eng[ship].set_pips(system, value)
