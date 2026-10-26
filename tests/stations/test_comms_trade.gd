extends GdUnitTestSuite
## Trading in the offer card's overlay (§5.6, FT-COM-004, FT-COM-009, FT-MIS-036): the goods
## and repairs with prices, buying and selling by key, tap and controller, the module line
## that shows the module a full slot gives up in the same trade and what it pays, the module
## sale, and the result of each trade or refusal as a line under the rows.

const SETTINGS: String = "user://test_comms_trade.cfg"


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen() -> StationScreen:
	var ctx: StationContext = StationFixture.context("comms", SETTINGS)
	CommsFixture.install(ctx)
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	add_child(s)
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = Vector2(1280, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	var panel: CommsPanel = s.panels[0] as CommsPanel
	panel.open_card(CommsFixture.OFFER)
	return s


func _ev(id: String, device: String = "kbm") -> Dictionary:
	return {
		"id": id,
		"group": "comms",
		"target": "comms",
		"kind": IntentTable.row(id)["kind"],
		"pressed": true,
		"value": 1.0,
		"device": device,
	}


func _commands(s: StationScreen, kind: String) -> Array:
	var out: Array = []
	for c: Array in StationFixture.sent(s.ctx).of("command"):
		if c[1][0]["kind"] == kind:
			out.append(c[1][0])
	return out


## The index of the overlay row of `kind` whose field `key` is `value`.
func _row(panel: CommsPanel, kind: String, key: String, value: Variant) -> int:
	var rows: Array[Dictionary] = panel.overlay.rows()
	for i: int in rows.size():
		if rows[i]["kind"] == kind and str(rows[i].get(key, "")) == str(value):
			return i
	return -1


# FT: FT-COM-004
# An offer card's overlay lists what the market sells with the price, what a sale pays and
# the stock, and a repair with its price; buying and selling by key send one step of the
# item (fuel by the hundred) and Space-less: a repair is bought once and has no sale.
func test_goods_are_bought_and_sold_by_key() -> void:
	var s: StationScreen = await _screen()
	var panel: CommsPanel = s.panels[0] as CommsPanel
	var parts: int = _row(panel, "buy", "item", "parts")
	assert_int(parts).is_greater_equal(0)
	assert_str(panel.overlay.row_text(panel.overlay.rows()[parts])).is_equal(
		"Parts: buy 25  sell 12  stock 20"
	)
	var fuel: int = _row(panel, "buy", "item", "propellant")
	assert_str(panel.overlay.row_text(panel.overlay.rows()[fuel])).contains("x100 per press")
	panel.overlay.focus = parts
	s.dispatch(_ev("comms_buy"))
	s.dispatch(_ev("comms_sell"))
	var trades: Array = _commands(s, "comms_trade")
	assert_array(trades).has_size(2)
	assert_dict(trades[0]).is_equal(
		{"kind": "comms_trade", "card": CommsFixture.OFFER, "item": "parts", "qty": 1, "buy": true}
	)
	assert_bool(trades[1]["buy"]).is_false()
	panel.overlay.focus = fuel
	s.dispatch(_ev("comms_buy"))
	assert_int(_commands(s, "comms_trade")[2]["qty"]).is_equal(100)
	panel.overlay.focus = _row(panel, "buy", "item", "repair:engines")
	s.dispatch(_ev("comms_sell"))
	assert_array(_commands(s, "comms_trade")).has_size(3)
	s.dispatch(_ev("comms_buy"))
	assert_int(_commands(s, "comms_trade")[3]["qty"]).is_equal(1)
	assert_str(_commands(s, "comms_trade")[3]["item"]).is_equal("repair:engines")


# FT: FT-MIS-036, FT-COM-009
# The module's buy line names the module the full slot gives up and what the market pays for
# it, and the net cost; buying sends the module and the slot, and the fitted module has a
# sell line with its price.
func test_the_module_line_shows_the_trade_in() -> void:
	var s: StationScreen = await _screen()
	var panel: CommsPanel = s.panels[0] as CommsPanel
	var at: int = _row(panel, "module", "module", "hx2_afterburner")
	assert_int(at).is_greater_equal(0)
	assert_str(panel.overlay.row_text(panel.overlay.rows()[at])).is_equal(
		"Module HX-2 Afterburner, slot 1: 900  swaps out BX-3 Reactor for 450, net 450"
	)
	panel.overlay.focus = at
	s.dispatch(_ev("comms_buy"))
	(
		assert_dict(_commands(s, "comms_buy_module")[0])
		. is_equal(
			{
				"kind": "comms_buy_module",
				"card": CommsFixture.OFFER,
				"module_key": "hx2_afterburner",
				"slot": 0,
			}
		)
	)
	var sell: int = _row(panel, "sell_module", "slot", 0)
	assert_int(sell).is_greater_equal(0)
	assert_str(panel.overlay.row_text(panel.overlay.rows()[sell])).is_equal(
		"Sell BX-3 Reactor (slot 1)  for 450"
	)
	# The empty slot has nothing to sell.
	assert_int(_row(panel, "sell_module", "slot", 1)).is_equal(-1)
	panel.overlay.focus = sell
	s.dispatch(_ev("comms_sell"))
	assert_dict(_commands(s, "comms_sell_module")[0]).is_equal(
		{"kind": "comms_sell_module", "card": CommsFixture.OFFER, "slot": 0}
	)
	# E on a sale line and X on a purchase line do nothing.
	s.dispatch(_ev("comms_buy"))
	panel.overlay.focus = at
	s.dispatch(_ev("comms_sell"))
	assert_array(_commands(s, "comms_sell_module")).has_size(1)
	assert_array(_commands(s, "comms_buy_module")).has_size(1)


# FT: FT-COM-004
# A tap on a line does it, and a controller's A or RT does the focused one; a market with no
# docked offers gives no trade lines.
func test_tap_and_pad_do_the_lines() -> void:
	var s: StationScreen = await _screen()
	var panel: CommsPanel = s.panels[0] as CommsPanel
	panel.overlay.size = Vector2(1000, 700)
	panel.overlay.show_card(CommsData.block(s.ctx.view), CommsFixture.OFFER)
	var at: int = _row(panel, "buy", "item", "parts")
	for pressed: bool in [true, false]:
		var e: InputEventMouseButton = InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = panel.overlay._rects[at].get_center()
		panel.overlay._gui_input(e)
	assert_str(_commands(s, "comms_trade")[0]["item"]).is_equal("parts")
	panel.overlay.focus = _row(panel, "module", "module", "hx2_afterburner")
	(
		assert_bool(
			s.dispatch(
				{
					"id": "select",
					"group": "common",
					"target": "screen",
					"kind": "press",
					"pressed": true,
					"value": 1.0,
					"device": "pad"
				}
			)
		)
		. is_true()
	)
	assert_array(_commands(s, "comms_buy_module")).has_size(1)
	s.dispatch(_ev("comms_buy", "pad"))
	assert_array(_commands(s, "comms_buy_module")).has_size(2)
	var blk: Dictionary = CommsFixture.block()
	blk["offers"] = []
	blk["modules"] = []
	CommsFixture.install(s.ctx, blk)
	panel.refresh(true)
	assert_int(_row(panel, "buy", "item", "parts")).is_equal(-1)
	assert_int(_row(panel, "module", "module", "hx2_afterburner")).is_equal(-1)
	assert_int(_row(panel, "sell_module", "slot", 0)).is_equal(-1)


# FT: FT-COM-004, FT-COM-009
# A trade, a module sale and a refusal each leave a line under the rows.
func test_results_are_shown() -> void:
	var s: StationScreen = await _screen()
	var panel: CommsPanel = s.panels[0] as CommsPanel
	s.ctx.crew.sim_event.emit(&"trade_refused", {"tag": "no_credits"})
	assert_str(panel.overlay.status).is_equal("Not enough credits.")
	s.ctx.crew.sim_event.emit(&"trade_done", {"tag": "parts", "value": -25.0})
	assert_str(panel.overlay.status).is_equal("Done: Parts, 25 credits.")
	s.ctx.crew.sim_event.emit(&"module_sold", {"tag": "bx3_reactor", "value": 450.0})
	assert_str(panel.overlay.status).is_equal("Sold BX-3 Reactor for 450.")
	s.ctx.crew.sim_event.emit(&"card_refused", {"tag": "not_docked"})
	assert_str(panel.overlay.status).is_equal("Dock first.")
	s.ctx.crew.sim_event.emit(&"hail_refused", {"tag": "nonsense"})
	assert_str(panel.overlay.status).is_equal("Refused.")


# FT: FT-COM-001, FT-DAT-004
# The NPC's line shows as text in the session language: the NPC's name filled in, the numbers
# the host speaks left as "…", and an id the dialogue files lack as itself.
func test_the_npc_line_is_text() -> void:
	var line: String = CommsData.line_text("npc.hail_patrol", "Vega", "Kestrel")
	assert_str(line).is_equal("Kestrel, this is Vega of the patrol. Hold your course.")
	(
		assert_str(CommsData.line_text("npc.trade_offer", "Kappa", "Kestrel"))
		. contains("…")
		. not_contains("{")
	)
	assert_str(CommsData.line_text("npc.no_such_line", "Kappa", "Kestrel")).is_equal(
		"npc.no_such_line"
	)
	I18n.apply("it")
	assert_str(CommsData.line_text("npc.hail_patrol", "Vega", "Kestrel")).starts_with(
		"Kestrel, qui Vega"
	)
	I18n.apply("en")
