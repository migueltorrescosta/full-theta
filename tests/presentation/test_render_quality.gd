extends GdUnitTestSuite
## The graphics settings of the 3D views (E2) and the cheap 3D waste fixes (E4).


func after_test() -> void:
	ProceduralShip.low_graphics = false
	Engine.max_fps = 0
	RenderQuality.shrink = 1


# FT: FT-STN-013
# Auto halves the 3D size on touch layouts only; Full and Half ignore the layout.
func test_the_shrink_follows_the_mode_and_the_layout() -> void:
	assert_int(RenderQuality.shrink_for("auto", true)).is_equal(2)
	assert_int(RenderQuality.shrink_for("auto", false)).is_equal(1)
	assert_int(RenderQuality.shrink_for("full", true)).is_equal(1)
	assert_int(RenderQuality.shrink_for("half", false)).is_equal(2)


# FT: FT-STN-013
# Apply reaches the tracked containers, the frame cap and the ships' tier; the default
# settings leave a desktop as it was (full size, no cap, full graphics).
func test_apply_sets_the_containers_the_cap_and_the_tier() -> void:
	var box: SubViewportContainer = auto_free(SubViewportContainer.new())
	add_child(box)
	RenderQuality.track(box)
	var s: ClientSettings = ClientSettings.new("user://test_render_quality.cfg")
	RenderQuality.apply(s, false, get_tree())
	assert_int(box.stretch_shrink).is_equal(1)
	assert_int(Engine.max_fps).is_equal(0)
	assert_bool(ProceduralShip.low_graphics).is_false()
	s.fps_cap = true
	s.low_graphics = true
	RenderQuality.apply(s, true, get_tree())
	assert_int(box.stretch_shrink).is_equal(2)
	assert_int(Engine.max_fps).is_equal(RenderQuality.FPS_CAP)
	assert_bool(ProceduralShip.low_graphics).is_true()
	var later: SubViewportContainer = auto_free(SubViewportContainer.new())
	RenderQuality.track(later)
	assert_int(later.stretch_shrink).is_equal(2)


# FT: FT-STN-013
# The graphics options survive the file; a broken mode falls back to auto.
func test_graphics_settings_round_trip() -> void:
	var path: String = "user://test_render_quality.cfg"
	var a: ClientSettings = ClientSettings.new(path)
	a.render_3d = "half"
	a.fps_cap = true
	a.low_graphics = true
	assert_int(a.save()).is_equal(OK)
	var b: ClientSettings = ClientSettings.new(path)
	b.load_file()
	assert_str(b.render_3d).is_equal("half")
	assert_bool(b.fps_cap).is_true()
	assert_bool(b.low_graphics).is_true()
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(path)
	cfg.set_value("graphics", "render_3d", "bogus")
	cfg.save(path)
	var c: ClientSettings = ClientSettings.new(path)
	c.load_file()
	assert_str(c.render_3d).is_equal("auto")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# FT: FT-AUD-022
# E4: every SpaceView shares the one star mesh.
func test_every_view_shares_the_star_mesh() -> void:
	var a: SpaceView = auto_free(SpaceView.new())
	var b: SpaceView = auto_free(SpaceView.new())
	assert_object(a._stars.mesh).is_same(b._stars.mesh)
	assert_object(SpaceView.star_mesh()).is_same(a._stars.mesh)


# FT: FT-AUD-016
# E4: the rim light is off while its energy is 0 and on when a view raises it.
func test_the_rim_light_is_off_at_zero_energy() -> void:
	var view: SpaceView = auto_free(SpaceView.new())
	assert_bool(view.rim.visible).is_false()
	view.set_rim_energy(0.9)
	assert_bool(view.rim.visible).is_true()
	assert_float(view.rim.light_energy).is_equal_approx(0.9, 0.001)
	view.set_rim_energy(0.0)
	assert_bool(view.rim.visible).is_false()


# FT: FT-HLM-002
# E4: the dust moves in its vertex shader: a frame sets one uniform (the ship's place
# within one tile) and leaves the instance transforms alone.
func test_the_dust_wraps_in_the_shader() -> void:
	var view: HelmView = auto_free(HelmView.new())
	add_child(view)
	var dust: MultiMeshInstance3D = view.find_children("*", "MultiMeshInstance3D", true, false)[0]
	var first: Transform3D = dust.multimesh.get_instance_transform(0)
	view._place_dust(Vector3(1250.0, -30.0, 10.5))
	var mat: ShaderMaterial = dust.material_override as ShaderMaterial
	assert_object(mat).is_not_null()
	var at: Vector3 = mat.get_shader_parameter("own_pos")
	assert_float(at.x).is_equal_approx(250.0, 0.001)
	assert_float(at.y).is_equal_approx(470.0, 0.001)
	assert_float(at.z).is_equal_approx(10.5, 0.001)
	assert_bool(dust.multimesh.get_instance_transform(0) == first).is_true()
	assert_int(dust.multimesh.instance_count).is_equal(HelmView.DUST_COUNT)


# FT: FT-AUD-016
# R20-11: the lobby's off-screen warm-up draws a ship and the two effect shaders, then frees
# itself.
func test_the_gpu_warm_up_frees_itself() -> void:
	var warm: GpuWarm = GpuWarm.new("kestrel")
	add_child(warm)
	assert_int(warm.find_children("*", "VfxEffect", true, false).size()).is_equal(2)
	for i: int in GpuWarm.FRAMES + 2:
		await get_tree().process_frame
	assert_bool(is_instance_valid(warm) and not warm.is_queued_for_deletion()).is_false()
