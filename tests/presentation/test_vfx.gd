extends GdUnitTestSuite
## The effects of the 3D views (#12, E14): each sim event spawns its effect, each effect frees
## itself, comfort takes out the flashes and the shake, and only a few are alive at once.


func _view(comfort: bool = false) -> Array:
	var ctx: StationContext = StationFixture.context("helm")
	ctx.settings.comfort = comfort
	var view: HelmScene = auto_free(HelmScene.new())
	add_child(view)
	view.show_state(ctx, true)
	return [view, ctx]


func _event(ctx: StationContext, kind: StringName, ship: int, value: float = 0.0) -> void:
	ctx.crew.handle_event(
		{
			"type": String(kind),
			"payload":
			{"ship": ship, "faction": 0, "other": -1, "value": value, "vector": Vector3(0, 0, -1)}
		},
		0
	)


func _effects(view: SpaceScene) -> Array[VfxEffect]:
	var out: Array[VfxEffect] = []
	for n: Node in view.find_children("*", "VfxEffect", true, false):
		out.append(n as VfxEffect)
	return out


# FT: FT-AUD-025
# A hit that got through shows a spark on the hull, a hit the shields took shows the shell.
func test_a_hit_sparks_or_shows_the_shield() -> void:
	var a: Array = _view()
	var view: HelmScene = a[0]
	var ctx: StationContext = a[1]
	_event(ctx, &"hit", StationFixture.H2, 5.0)
	_event(ctx, &"hit", StationFixture.H2, 0.0)
	var kinds: Array = []
	for e: VfxEffect in _effects(view):
		kinds.append(e.kind)
	assert_array(kinds).contains_exactly_in_any_order([VfxEffect.Kind.HIT, VfxEffect.Kind.SHIELD])


# FT: FT-AUD-025
# Destruction, the jump spool and the arrival each spawn their effect on the ship.
func test_explosion_and_jump_effects_spawn_on_their_events() -> void:
	var a: Array = _view()
	var view: HelmScene = a[0]
	var ctx: StationContext = a[1]
	_event(ctx, &"destroyed", StationFixture.H2)
	_event(ctx, &"jump_spool", StationFixture.SHIP)
	_event(ctx, &"jump_arrive", StationFixture.SHIP)
	var kinds: Array = []
	for e: VfxEffect in _effects(view):
		kinds.append(e.kind)
	assert_array(kinds).contains_exactly_in_any_order(
		[VfxEffect.Kind.EXPLOSION, VfxEffect.Kind.JUMP_SPOOL, VfxEffect.Kind.JUMP_ARRIVE]
	)


# FT: FT-AUD-025
# Every effect frees itself once its duration has run.
func test_an_effect_frees_itself() -> void:
	for kind: int in VfxEffect.Kind.values():
		var e: VfxEffect = VfxEffect.make(kind as VfxEffect.Kind, false)
		add_child(e)
		assert_bool(e.finished()).is_false()
		e.advance(e.duration_s * 0.5)
		assert_bool(e.is_queued_for_deletion()).is_false()
		e.advance(e.duration_s)
		assert_bool(e.is_queued_for_deletion()).is_true()


# FT: FT-AUD-025
# An effect with `frozen` holds its age for the L5 shots.
func test_a_frozen_effect_holds_its_age() -> void:
	var e: VfxEffect = auto_free(VfxEffect.make(VfxEffect.Kind.EXPLOSION, false))
	e.frozen = true
	add_child(e)
	e._process(10.0)
	assert_float(e.age_s).is_equal(0.0)


# FT: FT-AUD-025, FT-STN-017
# Comfort takes the flash and the shake out: no core or spokes, a dimmer ring, no shake.
func test_comfort_suppresses_flashes_and_shake() -> void:
	var a: Array = _view(true)
	var view: HelmScene = a[0]
	var ctx: StationContext = a[1]
	_event(ctx, &"hit", StationFixture.SHIP, 5.0)
	_event(ctx, &"destroyed", StationFixture.H2)
	assert_float(view.vfx.shake_level()).is_equal(0.0)
	assert_bool(view.vfx.shake_basis().is_equal_approx(Basis.IDENTITY)).is_true()
	assert_int(_effects(view).size()).is_greater(0)
	for e: VfxEffect in _effects(view):
		assert_float(e.flash).is_equal(0.0)
		var m: ShaderMaterial = e.material_override as ShaderMaterial
		assert_float(float(m.get_shader_parameter("flash"))).is_equal(0.0)
	var loud: VfxEffect = VfxEffect.make(VfxEffect.Kind.EXPLOSION, false)
	var calm: VfxEffect = VfxEffect.make(VfxEffect.Kind.EXPLOSION, true)
	assert_float(loud.flash).is_equal(1.0)
	(
		assert_float(
			float((calm.material_override as ShaderMaterial).get_shader_parameter("ring_gain"))
		)
		. is_less(
			float((loud.material_override as ShaderMaterial).get_shader_parameter("ring_gain"))
		)
	)
	loud.free()
	calm.free()


# FT: FT-AUD-025
# Without comfort a hit on the own ship shakes the camera, and the shake dies away.
func test_a_hit_on_the_own_ship_shakes_the_camera_until_it_decays() -> void:
	var a: Array = _view()
	var view: HelmScene = a[0]
	var ctx: StationContext = a[1]
	_event(ctx, &"hit", StationFixture.SHIP, 5.0)
	assert_float(view.vfx.shake_level()).is_greater(0.5)
	view.vfx._process(1.0)
	view.vfx._process(1.0)
	assert_float(view.vfx.shake_level()).is_equal(0.0)


# FT: FT-AUD-025
# A volley never leaves more than MAX_LIVE effects.
func test_effects_are_capped() -> void:
	var a: Array = _view()
	var view: HelmScene = a[0]
	var ctx: StationContext = a[1]
	for i: int in VfxLayer.MAX_LIVE * 3:
		_event(ctx, &"hit", StationFixture.H2, 5.0)
	assert_int(view.vfx.live()).is_equal(VfxLayer.MAX_LIVE)


func _radar(comfort: bool) -> DiscRadar:
	var ctx: StationContext = StationFixture.context("helm")
	ctx.settings.comfort = comfort
	var radar: DiscRadar = auto_free(DiscRadar.new())
	add_child(radar)
	radar.size = Vector2(300, 300)
	radar.set_picture(ctx.picture(), {}, ctx)
	_event(ctx, &"destroyed", StationFixture.H2)
	_event(ctx, &"hit", StationFixture.SHIP, 3.0)
	return radar


# FT: FT-AUD-025
# The radar rings a destroyed contact and a hit on the own ship, and drops the ring by itself.
func test_the_radar_rings_a_destroyed_contact_and_a_hit() -> void:
	var radar: DiscRadar = _radar(false)
	assert_int(radar._bursts.size()).is_equal(2)
	radar._bursts[0]["from"] = Time.get_ticks_msec() - DiscRadar.BURST_MS - 1
	radar._bursts[1]["from"] = Time.get_ticks_msec() - DiscRadar.BURST_MS - 1
	radar._process(0.0)
	assert_int(radar._bursts.size()).is_equal(0)


# FT: FT-AUD-025, FT-STN-017
# With comfort the radar shows no ring.
func test_comfort_leaves_the_radar_without_rings() -> void:
	assert_int(_radar(true)._bursts.size()).is_equal(0)
