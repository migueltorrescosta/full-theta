class_name ProjectileTable
extends RefCounted

var px := PackedFloat64Array()
var pz := PackedFloat64Array()

func clear(k: int) -> void:
	self.pz[k] = 0.0
	px[k] = 0.0
