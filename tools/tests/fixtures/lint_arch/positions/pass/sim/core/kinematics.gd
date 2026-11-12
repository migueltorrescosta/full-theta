class_name Kinematics
extends RefCounted

var pos_x := PackedFloat64Array()
var pos_y := PackedFloat64Array()
var pos_z := PackedFloat64Array()


func relative(i: int, j: int) -> Vector3:
	return Vector3(pos_x[j] - pos_x[i], self.pos_y[j] - pos_y[i], pos_z[j] - pos_z[i])


func copy_from(other: Kinematics) -> void:
	pos_x = other.pos_x
