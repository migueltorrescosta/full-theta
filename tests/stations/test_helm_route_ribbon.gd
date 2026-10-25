extends HelmSuite
## Relay's route as a ribbon on Helm's HUD (FT-RLY-005, FT-PAIR-007, P4): drawn through the
## waypoints in view, nothing for waypoints behind or at another site, nothing when the
## server sent no route (the routes toggle is off, FT-PAIR-008).


func _route(points: Array) -> void:
	var ctx: StationContext = _ctx()
	var wire: Array = []
	for p: Dictionary in points:
		wire.append({"site": p["site"], "x": p["pos"].x, "y": p["pos"].y, "z": p["pos"].z})
	ctx.crew.handle_event(
		{"type": "routes", "payload": {"ship": 0, "routes": [wire]}}, StationFixture.NOW_MS
	)


func _ahead(metres: float, side: float = 0.0) -> Vector3:
	var ctx: StationContext = _ctx()
	return ctx.interp.own_position() + ctx.interp.own_rotation() * Vector3(side, 0.0, -metres)


# FT: FT-RLY-005, FT-PAIR-007
func test_the_route_is_a_ribbon_through_the_waypoints_in_view() -> void:
	assert_array(_panel.hud.route_points()).is_empty()
	var site: int = _ctx().site()
	_route(
		[
			{"site": site, "pos": _ahead(800.0)},
			{"site": site, "pos": _ahead(2000.0, 300.0)},
			{"site": site, "pos": _ahead(-900.0)},
			{"site": site + 1, "pos": _ahead(1500.0)},
		]
	)
	_frame()
	var routes: Array = _panel.hud.route_points()
	assert_int(routes.size()).is_equal(1)
	var points: Array = routes[0]
	assert_int(points.size()).is_equal(4)
	assert_bool(points[0] is Vector2).is_true()
	assert_bool(points[1] is Vector2).is_true()
	# The second waypoint is further and to one side of the first.
	assert_float((points[1] as Vector2).distance_to(_panel.hud.size / 2.0)).is_greater(0.0)
	# Behind the ship, and at another site: no screen point.
	assert_object(points[2]).is_null()
	assert_object(points[3]).is_null()
	# Cleared: nothing to draw.
	_ctx().crew.handle_event(
		{"type": "routes", "payload": {"ship": 0, "routes": [[]]}}, StationFixture.NOW_MS
	)
	assert_int((_panel.hud.route_points()[0] as Array).size()).is_equal(0)
	# Docked: no camera, no ribbon.
	_panel.set_mode(false, true)
	assert_array(_panel.hud.route_points()).is_empty()
