class_name SimRng
extends RefCounted
## One seeded RandomNumberGenerator per sim subsystem (FT-ARC-008), so adding draws in
## one subsystem never shifts another's sequence. Streams are created in a fixed way
## from the world seed and the stream name.

var seed_value: int = 0
var _streams: Dictionary[StringName, RandomNumberGenerator] = {}


func _init(world_seed: int) -> void:
	seed_value = world_seed


func stream(name: StringName) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = _streams.get(name)
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = hash("%d:%s" % [seed_value, name])
		_streams[name] = rng
	return rng


## [name, state] pairs in name order, for the state hash.
func states() -> Array:
	var names: Array[StringName] = _streams.keys()
	names.sort_custom(func(a: StringName, b: StringName) -> bool: return str(a) < str(b))
	var out: Array = []
	for n: StringName in names:
		out.append([n, _streams[n].state])
	return out
