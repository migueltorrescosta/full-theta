extends GdUnitTestSuite
## A 3D view opens without waiting for the shared ship model (#27, D294): a ship asked for
## before the model is built is an empty node that SpaceView fills in on a later frame.

var _parts: Array = []
var _materials: Dictionary = {}


func before_test() -> void:
	# The model is built once per process: start from not built, put it back after.
	_parts = ProceduralShip._parts
	_materials = ProceduralShip._materials_by_wear
	ProceduralShip._parts = []
	ProceduralShip._materials_by_wear = {}
	ProceduralShip._bake = null
	ProceduralShip._plates = {}


func after_test() -> void:
	ProceduralShip._parts = _parts
	ProceduralShip._materials_by_wear = _materials
	ProceduralShip._bake = null
	ProceduralShip._plates = {}


func _view() -> SpaceView:
	var v: SpaceView = auto_free(SpaceView.new())
	add_child(v)
	return v


func _bodies(n: Node) -> int:
	return n.find_children("*", "MeshInstance3D", true, false).size()


# FT: FT-AUD-016
# Before the model is built the copy is empty, and each frame builds a slice until it fills.
func test_a_copy_is_empty_until_the_model_is_built() -> void:
	var view: SpaceView = _view()
	var ship: Node3D = view.copy_ship()
	assert_int(_bodies(ship)).is_equal(0)
	var frames: int = 0
	while _bodies(ship) == 0 and frames < 5000:
		view._process(0.0)
		frames += 1
	assert_int(_bodies(ship)).is_equal(88)
	assert_bool(ProceduralShip.is_warm(view.wear)).is_true()


# FT: FT-AUD-016
# Once the model is built a copy is full at once, as before.
func test_a_copy_is_full_at_once_when_the_model_is_built() -> void:
	var view: SpaceView = _view()
	ProceduralShip.warm(view.wear, -1)
	assert_int(_bodies(view.copy_ship())).is_equal(88)


# FT: FT-AUD-016
# A copy freed before the model is built is skipped, and the others still fill.
func test_a_freed_copy_does_not_stop_the_others_filling() -> void:
	var view: SpaceView = _view()
	var gone: Node3D = view.copy_ship()
	var kept: Node3D = view.copy_ship()
	gone.free()
	var frames: int = 0
	while _bodies(kept) == 0 and frames < 5000:
		view._process(0.0)
		frames += 1
	assert_int(_bodies(kept)).is_equal(88)


func _albedo_of(wear: float) -> String:
	var m: StandardMaterial3D = ProceduralShip._materials_by_wear[wear][ProceduralShip.Role.HULL]
	return m.albedo_texture.get_image().get_data().hex_encode().sha256_text()


# FT: FT-AUD-016
# The plating is made in steps over several calls; calls for two wears in turn give each
# wear the textures it gets when built in one go.
func test_the_plating_steps_keep_each_wear_apart() -> void:
	ProceduralShip.warm(0.6, -1)
	var whole: String = _albedo_of(0.6)
	ProceduralShip._materials_by_wear = {}
	for i: int in 3:
		ProceduralShip.warm(1.0, 0)
		ProceduralShip.warm(0.6, 0)
	assert_bool(ProceduralShip.is_warm(0.6)).is_true()
	assert_str(_albedo_of(0.6)).is_equal(whole)
	ProceduralShip.warm(1.0, -1)
	assert_str(_albedo_of(1.0)).is_not_equal(whole)
