class_name ProjectileTable
extends RefCounted

var pos_x := PackedFloat64Array()
var pos_z := PackedFloat64Array()


func clear(k: int) -> void:
	self.pos_z[k] = 0.0
	pos_x[k] = 0.0
