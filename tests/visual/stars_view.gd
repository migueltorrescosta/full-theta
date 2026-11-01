## Star backdrop for the L5 harness (D310): a SpaceView with no ships and its camera turned
## by yaw and pitch (yaw 0 looks along -Z, 90 along -X); the galaxy band crosses the view at
## yaw 0 and pitch 15.
extends Node3D

var yaw_degrees: float = 0.0
var pitch_degrees: float = 0.0
var fov_degrees: float = 70.0


func _ready() -> void:
	var space: SpaceView = SpaceView.new()
	add_child(space)
	var basis: Basis = Basis.from_euler(
		Vector3(deg_to_rad(pitch_degrees), deg_to_rad(yaw_degrees), 0.0), EULER_ORDER_YXZ
	)
	space.place_camera(Transform3D(basis, Vector3.ZERO), fov_degrees)
