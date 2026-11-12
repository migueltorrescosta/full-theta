extends GdUnitTestSuite
## EngineeringCutaway's cached projection (R20-6) and its health colours (R05-2): the
## geometry, the draw order and the label layout are redone only when the view, the size,
## the ship or a label's text changed, and the discs take the shared health bands.


func before() -> void:
	I18n.apply("en")
	LayoutMode.forced = LayoutMode.Kind.DESKTOP


func after() -> void:
	LayoutMode.forced = -1


func _cutaway() -> EngineeringCutaway:
	var ctx: StationContext = StationFixture.context("engineering")
	var cut: EngineeringCutaway = auto_free(EngineeringCutaway.new())
	cut.model = EngineeringModel.new(ctx, ctx.ship_def())
	cut.size = Vector2(500, 400)
	return cut


# FT: FT-ENG-001
func test_geometry_is_reused_until_the_view_or_the_size_changes() -> void:
	var cut: EngineeringCutaway = _cutaway()
	var first: Vector2 = cut.subsystem_pos(0)
	var serial: int = cut._geo_serial
	for i: int in 5:
		assert_vector(cut.subsystem_pos(i % cut.model.count())).is_not_equal(Vector2(-1, -1))
		cut.node_r()
		cut.project(Vector3(1, 2, 3))
	assert_int(cut._geo_serial).is_equal(serial)
	assert_vector(cut.subsystem_pos(0)).is_equal(first)
	cut.rotate_by(Vector2(0.4, 0.1))
	assert_vector(cut.subsystem_pos(0)).is_not_equal(first)
	assert_int(cut._geo_serial).is_greater(serial)
	serial = cut._geo_serial
	cut.size = Vector2(300, 350)
	cut.subsystem_pos(0)
	assert_int(cut._geo_serial).is_greater(serial)


# FT: FT-ENG-001
func test_cached_projection_equals_the_plain_projection() -> void:
	var cut: EngineeringCutaway = _cutaway()
	cut.rotate_by(Vector2(0.7, -0.2))
	for i: int in cut.model.count():
		var p: Vector3 = cut.project(cut.model.ship_def.subsystems[i].position)
		assert_vector(cut.subsystem_pos(i)).is_equal(Vector2(p.x, p.y))
	# The draw order runs far to near.
	var depth: Array[float] = []
	for i: int in cut._geo_order:
		depth.append(cut.project(cut.model.ship_def.subsystems[i].position).z)
	for k: int in range(1, depth.size()):
		assert_float(depth[k]).is_greater_equal(depth[k - 1])
	# Every hull ring and spine is in the cache: the sections' rings, then RING spines.
	assert_int(cut._geo_hull.size()).is_equal(
		EngineeringCutaway.SECTIONS.size() + EngineeringCutaway.RING
	)


# FT: FT-ENG-001
func test_labels_are_laid_out_again_only_when_their_inputs_change() -> void:
	var cut: EngineeringCutaway = _cutaway()
	var first: Dictionary = cut.label_rects()
	assert_dict(first).is_not_empty()
	assert_dict(cut.label_rects()).is_same(first)
	# A health change rewrites a label's percentage: the layout is redone.
	var rows: Array = cut.model.ctx.snap.blocks[StationCatalogue.Section.ENGINEERING]["subsystems"]
	rows[2] = (rows[2] as Dictionary).duplicate()
	rows[2]["health"] = 0.0
	var second: Dictionary = cut.label_rects()
	assert_dict(second).is_not_same(first)
	assert_dict(cut.label_rects()).is_same(second)
	cut.rotate_by(Vector2(0.3, 0.0))
	assert_dict(cut.label_rects()).is_not_same(second)


# FT: FT-ENG-001, FT-STN-006
func test_discs_take_the_shared_health_bands() -> void:
	for h: float in [1.0, 0.75, 0.74, 0.5, 0.49, 0.25, 0.24, 0.01]:
		var role: String = StatusView.bar_role(h)
		assert_object(EngineeringCutaway._health_color(h)).is_equal(Palette.color(role))
	assert_object(EngineeringCutaway._health_color(0.0)).is_equal(Palette.color("line"))
	# A part scratched to 80 % is still "ok", one at 30 % "warn", one at 20 % "danger".
	assert_object(EngineeringCutaway._health_color(0.8)).is_equal(Palette.color("ok"))
	assert_object(EngineeringCutaway._health_color(0.3)).is_equal(Palette.color("warn"))
	assert_object(EngineeringCutaway._health_color(0.2)).is_equal(Palette.color("danger"))
