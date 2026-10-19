class_name Kinematics
extends RefCounted

var px := PackedFloat64Array()
var py := PackedFloat64Array()
var pz := PackedFloat64Array()

func relative(i: int, j: int) -> Vector3:
	return Vector3(px[j] - px[i], self.py[j] - py[i], pz[j] - pz[i])

func copy_from(other: Kinematics) -> void:
	px = other.px
