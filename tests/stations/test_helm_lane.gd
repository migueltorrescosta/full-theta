extends HelmSuite
## Comms' approach lane on Helm's HUD (P5, FT-PAIR-001, FT-PAIR-007): a ring and a countdown at
## the site while the window is ahead, green inside it, red after; nothing when the server sent
## no lane (the lanes toggle is off or Comms hasn't shared it, FT-PAIR-008).


func _lane(open_s: float, close_s: float, at: Vector3) -> void:
	(
		_ctx()
		. crew
		. handle_event(
			{
				"type": "lanes",
				"payload":
				{
					"ship": 0,
					"lanes":
					[
						{
							"card": 0,
							"x": at.x,
							"y": at.y,
							"z": at.z,
							"open_s": open_s,
							"close_s": close_s,
							"by": "comms",
						}
					],
				},
			},
			StationFixture.NOW_MS
		)
	)


func _ahead(metres: float) -> Vector3:
	var ctx: StationContext = _ctx()
	return ctx.interp.own_position() + ctx.interp.own_rotation() * Vector3(0.0, 0.0, -metres)


# FT: FT-PAIR-001, FT-PAIR-007
# The lane shows amber with the seconds until it opens, then green with the seconds until it
# closes, then red; a lane behind the ship, or none sent, shows nothing.
func test_the_lane_counts_down_through_its_window() -> void:
	assert_array(_panel.hud.lane_marks()).is_empty()
	_lane(10.0, 40.0, _ahead(3000.0))
	_frame()
	var marks: Array[Dictionary] = _panel.hud.lane_marks()
	assert_int(marks.size()).is_equal(1)
	assert_str(marks[0]["state"]).is_equal("wait")
	assert_float(marks[0]["left_s"]).is_equal_approx(10.0, 0.01)
	assert_bool(marks[0]["pos"] is Vector2).is_true()
	_lane(-5.0, 25.0, _ahead(3000.0))
	assert_str(_panel.hud.lane_marks()[0]["state"]).is_equal("open")
	assert_float(_panel.hud.lane_marks()[0]["left_s"]).is_equal_approx(25.0, 0.01)
	_lane(-40.0, -10.0, _ahead(3000.0))
	assert_str(_panel.hud.lane_marks()[0]["state"]).is_equal("late")
	_lane(10.0, 40.0, _ahead(-3000.0))
	assert_array(_panel.hud.lane_marks()).is_empty()
	_ctx().crew.handle_event(
		{"type": "lanes", "payload": {"ship": 0, "lanes": []}}, StationFixture.NOW_MS
	)
	assert_array(_panel.hud.lane_marks()).is_empty()
