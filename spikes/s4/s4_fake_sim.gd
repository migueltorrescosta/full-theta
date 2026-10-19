class_name S4FakeSim
extends RefCounted
## Stub simulation: a few ships and contacts moving at 60 Hz, sized like a 6-ship
## station snapshot. Content is synthetic; only sizes and change rates matter.
## Ship fields that change every tick: pos, vel, rot, ang. Subsystems change every
## 0.5 s, hull and shields now and then; name, loadout, cargo and layout are
## static (they go in full snapshots only). Half the contacts move.

const STATIONS: Array[String] = ["helm", "weapons", "engineering", "science", "relay", "comms"]
const SUBSYSTEMS: int = 12

var tick: int = 0
var ships: int = 6
var contacts: int = 40
var layout_floats: int = 2048
var _entities: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(
	ship_count: int = 6, contact_count: int = 40, layout: int = 2048, seed_value: int = 1
) -> void:
	ships = ship_count
	contacts = contact_count
	layout_floats = layout
	_rng.seed = seed_value
	for i: int in range(ships):
		_entities[i] = _make_ship(i)
	for i: int in range(contacts):
		_entities[1000 + i] = _make_contact(i)


## Advances one 1/60 s tick. Returns an event dictionary every 12 ticks (5 Hz), else {}.
func step(dt: float) -> Dictionary:
	tick += 1
	for id: int in _entities:
		var e: Dictionary = _entities[id]
		if id >= 1000 and id % 2 == 1:
			continue
		var vel: Vector3 = (
			e["vel"] + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * dt
		)
		e["vel"] = vel
		e["pos"] = (e["pos"] as Vector3) + vel * dt
		var ang: Vector3 = e["ang"]
		e["rot"] = ((e["rot"] as Quaternion) * Quaternion.from_euler(ang * dt)).normalized()
		if id < 1000 and tick % 30 == id % 30:
			var subs: PackedFloat32Array = (e["subs"] as PackedFloat32Array).duplicate()
			for k: int in range(subs.size()):
				subs[k] = clampf(subs[k] + _rng.randf_range(-0.02, 0.02), 0.0, 1.0)
			e["subs"] = subs
		if id < 1000 and _rng.randf() < 0.01:
			e["hull"] = maxf(0.0, float(e["hull"]) - _rng.randf_range(0.0, 2.0))
			var shields: PackedFloat32Array = (e["shields"] as PackedFloat32Array).duplicate()
			shields[_rng.randi_range(0, 3)] = _rng.randf()
			e["shields"] = shields
	if tick % 12 == 0:
		return {
			"tick": tick,
			"type": "alert",
			"payload": {"ship": _rng.randi_range(0, ships - 1), "text": "Hull hit %d" % tick},
		}
	return {}


## A copy of the current state; entity dictionaries are fresh, values are shared
## but never mutated in place.
func state() -> Dictionary:
	var out: Dictionary = {}
	for id: int in _entities:
		out[id] = (_entities[id] as Dictionary).duplicate()
	return out


func seat_for(index: int) -> Dictionary:
	return {"ship": index % ships, "station": STATIONS[int(index / float(ships)) % STATIONS.size()]}


func _make_ship(i: int) -> Dictionary:
	var layout: PackedFloat32Array = PackedFloat32Array()
	layout.resize(layout_floats)
	for k: int in range(layout_floats):
		layout[k] = _rng.randf()
	var subs: PackedFloat32Array = PackedFloat32Array()
	subs.resize(SUBSYSTEMS * 4)
	for k: int in range(subs.size()):
		subs[k] = _rng.randf()
	var loadout: Array = []
	for m: int in range(6):
		loadout.append({"mount": m, "weapon": "beam_mk%d" % (m % 3), "arc": 90.0, "ammo": 12})
	var cargo: Dictionary = {}
	for c: int in range(40):
		cargo["item_%02d" % c] = _rng.randi_range(0, 50)
	return {
		"kind": "ship",
		"name": "Ship %d" % i,
		"pos": Vector3(_rng.randf_range(-5000, 5000), 0, _rng.randf_range(-5000, 5000)),
		"vel": Vector3(_rng.randf_range(-50, 50), 0, _rng.randf_range(-50, 50)),
		"rot": Quaternion.IDENTITY,
		"ang": Vector3(0, _rng.randf_range(-0.3, 0.3), 0),
		"hull": 100.0,
		"shields": PackedFloat32Array([1.0, 1.0, 1.0, 1.0]),
		"subs": subs,
		"loadout": loadout,
		"cargo": cargo,
		"layout": layout,
	}


func _make_contact(i: int) -> Dictionary:
	return {
		"kind": "asteroid" if i % 2 == 1 else "npc",
		"pos": Vector3(_rng.randf_range(-9000, 9000), 0, _rng.randf_range(-9000, 9000)),
		"vel": Vector3.ZERO if i % 2 == 1 else Vector3(_rng.randf_range(-80, 80), 0, 0),
		"rot": Quaternion.IDENTITY,
		"ang": Vector3(0, 0.1, 0),
	}
