# gdlint: disable=max-public-methods
class_name EngineeringPanel
extends StationPanel
## Engineering (T053, §5.3, layout E-A): the rotatable cutaway with subsystems coloured by
## health and heat, recent hits and repair crews (FT-ENG-001, FT-ENG-004); power pips
## per subsystem with the overcharge row, reactor cap and boost, shield power and focus
## tightness with a mirror of Helm's shield ring (FT-ENG-002, FT-ENG-003); faults, the
## repair queue and spare parts (FT-ENG-005). Docked, only the pip board shows.
##
## Reads the ENGINEERING block (ctx.view.blocks) against the ship's ShipDef from
## content/ (subsystem order, positions, limits). Hit marks come from `hit` events on the
## own ship (vector in the ship frame), through CrewState.sim_event. Sends set_pips,
## set_shield, boost, dispatch_repair and recall_repair; harden (pre-harden the selected
## subsystem) and fabricate_probe (FT-ENG-008, the probe itself is Relay's sim);
## pick_fault_cause for a fault of unknown cause (FT-ENG-006): the faults list says so,
## names the cause once Science's scan found it, and the cause-cycle intent picks.
## Nothing here shows a threat position: Engineering's view has no NEAR or PROJECTILES
## section (FT-ENG-007).

## The phone's pages, in tab order.
enum Page { POWER, SHIP, FAULTS, CREW }

const S = StationViews.Section
const KIND = SubsystemDef.Kind

## A sent pip or tightness value shows until the snapshot agrees, or for this long (ms).
const PENDING_MS: int = 1000
## Hit marks fade over this (ms) (FT-ENG-001: recent hit locations).
const HIT_MS: int = 15000
const MAX_HITS: int = 12
## A heat fault stays listed this long after its event (ms).
const FAULT_MS: int = 20000
## Heat share of the fault threshold from which a subsystem is listed as hot.
const HOT: float = 0.7
const TIGHTNESS_STEP: float = 0.5
## Controller: cursor speed (px/s) and cutaway turn rate (rad/s) at full deflection.
const CURSOR_SPEED: float = 450.0
const TURN_RATE: float = 2.0
## Below this width (px) the lists sit under the cutaway instead of in a column of
## their own (150 % UI scale, FT-STN-013).
const NARROW: float = 760.0
## Under this width (a phone, D195) the cutaway, the board and the lists stack and scroll.
const PHONE_W: float = 560.0
const CREW_LETTERS: String = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
## A phone (#28 follow-up, design 2.3, D287): a docked thumb rail of this width at the
## screen's left edge (upright a grid above the pages) with every board action, two to a row;
## the pages Power, Ship, Faults and Crew beside it; the screen's radar column stays (P28-E2).
const PHONE_RAIL_W: float = 168.0
## [intent id, string key, English] of the rail's buttons, in rows of two (design 2.3); each
## sends its intent as a key or the pad does (Claim as the common claim).
const TOUCH_ACTIONS: Array = [
	["pip_add", "eng.touch.pip_add", "Power +"],
	["pip_remove", "eng.touch.pip_remove", "Power -"],
	["shield_tighter", "eng.touch.tighter", "Tighter"],
	["shield_wider", "eng.touch.wider", "Wider"],
	["boost", "eng.boost", "Boost"],
	["harden", "eng.touch.harden", "Harden"],
	["dispatch_nearest", "eng.touch.repair", "Repair"],
	["cause_next", "eng.touch.cause", "Cause"],
	["fabricate_probe", "eng.touch.probe", "Probe"],
	["claim", "eng.touch.claim", "Claim"],
]
## The rail buttons' text size on a phone (two to a row).
const RAIL_FONT: int = 14
## Upright, the rail's buttons in a grid of this many columns.
const GRID_COLUMNS: int = 4

var ship_def: ShipDef = null
## Index in ship_def.subsystems of the subsystem pips, dispatch and the cursor act on.
var selected: int = 0
## The crew the common claim action (K, View+X) takes or releases.
var crew_pick: int = 0
## Recent hits on the own ship: {"pos": Vector3 (ship frame, m), "at_ms": int}.
var hits: Array[Dictionary] = []
## Subsystem index -> ms of its last heat fault event.
var faults: Dictionary = {}
var cutaway: EngineeringCutaway
var board: EngineeringBoard
## The phone arrangement on its side (#28 follow-up): the docked rail and the pages; hidden
## elsewhere.
var touch_layout: RailLayout = null
## Intent id -> its rail button on a phone on its side.
var touch_buttons: Dictionary = {}
## Intent id -> its button in the upright grid.
var grid_buttons: Dictionary = {}
var crew_page: CrewPage = null

var _row: BoxContainer
var _scroll_all: ScrollContainer
## The phone's pages: the box under the view-top row (its top margin follows top_reserve),
## one full-size page control each (Power scrolls the board), and upright the button grid.
var _pages_box: MarginContainer
var _page_ctl: Array[Control] = []
var _board_page: ScrollContainer
var _upright: VBoxContainer
var _grid: GridContainer
var _left: VBoxContainer
var _side: PanelContainer
var _lists: VBoxContainer
var _lists_text: String = ""
## "pips:<i>" or "tightness" -> [value sent, at ms].
var _pending: Dictionary = {}
## The last wheel event happened outside this panel (over the radar): its pip intent is
## the radar's zoom, not ours.
var _wheel_outside: bool = false


func _setup() -> void:
	ship_def = ctx.ship_def()
	_row = BoxContainer.new()
	_row.add_theme_constant_override("separation", 0)
	var scroll_all: ScrollContainer = ScrollContainer.new()
	scroll_all.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll_all.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll_all)
	_scroll_all = scroll_all
	_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_all.add_child(_row)
	_left = VBoxContainer.new()
	_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left.size_flags_stretch_ratio = 5.0
	_left.add_theme_constant_override("separation", 0)
	_row.add_child(_left)
	cutaway = EngineeringCutaway.new()
	cutaway.panel = self
	cutaway.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cutaway.size_flags_stretch_ratio = 1.4
	_left.add_child(cutaway)
	board = EngineeringBoard.new()
	board.panel = self
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_stretch_ratio = 3.0
	board.custom_minimum_size = Vector2(270, 0)
	_row.add_child(board)
	_side = PanelContainer.new()
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = Palette.color("panel")
	box.set_content_margin_all(12)
	_side.add_theme_stylebox_override("panel", box)
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side.custom_minimum_size = Vector2(210, 0)
	_row.add_child(_side)
	resized.connect(_place_lists)
	_lists = VBoxContainer.new()
	# Scrolls when the lists don't fit (they sit under the cutaway when narrow).
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_side.add_child(scroll)
	_lists.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_lists)
	ctx.crew.sim_event.connect(_on_sim_event)
	_refresh_lists()
	in_frame = true
	# The Crew page holds the share buttons (P28-Common): no Share opener on a phone.
	shows_shares = true
	_build_pages()


func _mode_changed() -> void:
	cutaway.visible = not docked
	_side.visible = not docked
	board.compact = docked
	_place_lists()


## The phone form the panel takes: PHONE_LANDSCAPE or PHONE_PORTRAIT when it shows its main
## view on a phone, else DESKTOP (a tablet, a desktop, or docked in a joint view).
func phone_form() -> LayoutMode.Form:
	if not is_inside_tree() or docked:
		return LayoutMode.Form.DESKTOP
	var f: LayoutMode.Form = LayoutMode.form_of(self)
	return f if LayoutMode.is_phone(f) else LayoutMode.Form.DESKTOP


## True when the panel takes the phone arrangement on its side.
func phone_landscape() -> bool:
	return phone_form() == LayoutMode.Form.PHONE_LANDSCAPE


func _place_lists() -> void:
	if ctx == null:
		return
	var f: LayoutMode.Form = phone_form()
	if f != LayoutMode.Form.DESKTOP:
		_to_phone(f == LayoutMode.Form.PHONE_LANDSCAPE)
		return
	_from_phone()


## The phone's pages (built in _setup, so the screen binds them at once): Power (the board,
## scrolling only when the view-top row grows), Ship (the cutaway), Faults (the lists) and
## Crew. Only the page controls take part in the pages: the board, cutaway and lists move
## into them on a phone and back out elsewhere.
func _build_pages() -> void:
	_pages_box = MarginContainer.new()
	_pages_box.name = "Pages"
	_pages_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pages_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pages_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var area: Control = Control.new()
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pages_box.add_child(area)
	_board_page = ScrollContainer.new()
	_board_page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	crew_page = CrewPage.new(self)
	crew_page.name = "CrewPage"
	pages = PageHost.new()
	var titles: Array[String] = [
		tr("eng.power"),
		TouchText.of("eng.touch.ship", "Ship"),
		tr("eng.faults"),
		TouchText.of("page.crew", "Crew"),
	]
	for i: int in titles.size():
		var page: Control = crew_page if i == Page.CREW else Control.new()
		if i == Page.POWER:
			page = _board_page
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if page != crew_page and page != _board_page:
			page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		area.add_child(page)
		_page_ctl.append(page)
		pages.add_page(titles[i], [page])


## The pages are built before the phone arrangement takes them: free them with the panel if
## it never did (a desktop).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _pages_box != null and _pages_box.get_parent() == null:
		_pages_box.free()


## The rail on its side (rows of two) and the upright grid, each a full set of the buttons.
func _build_rails() -> void:
	touch_layout = RailLayout.new()
	touch_layout.name = "TouchLayout"
	touch_layout.docked = true
	# 8 px from the top bar and from the rail (UiTheme.TOUCH_GAP between targets).
	touch_layout.offset_top = UiTheme.TOUCH_GAP
	add_child(touch_layout)
	var rail: TouchRail = touch_layout.rail(SIDE_LEFT)
	rail.custom_minimum_size.x = PHONE_RAIL_W
	var row: Array = []
	for a: Array in TOUCH_ACTIONS:
		var b: RailButton = _rail_button(a)
		touch_buttons[a[0]] = b
		row.append(b)
		if row.size() == 2:
			rail.add_row(row)
			row = []
	_upright = VBoxContainer.new()
	_upright.name = "Upright"
	_upright.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_upright.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	_upright.offset_top = UiTheme.TOUCH_GAP
	_upright.visible = false
	add_child(_upright)
	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", UiTheme.TOUCH_GAP)
	_grid.add_theme_constant_override("v_separation", UiTheme.TOUCH_GAP)
	_upright.add_child(_grid)
	for a: Array in TOUCH_ACTIONS:
		var b: RailButton = _rail_button(a)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid_buttons[a[0]] = b
		_grid.add_child(b)


func _rail_button(a: Array) -> RailButton:
	var b: RailButton = RailButton.make(TouchText.of(a[1], a[2]))
	b.name = "Touch_" + str(a[0])
	# Two to a 168 px rail: the longest label fits at 14 px.
	b.add_theme_font_size_override("font_size", RAIL_FONT)
	b.pressed.connect(press_touch.bind(str(a[0])))
	return b


## Moves the board, cutaway and lists onto the pages, beside the rail on its side or under
## the grid upright.
func _to_phone(sideways: bool) -> void:
	if touch_layout == null:
		_build_rails()
	_scroll_all.visible = false
	touch_layout.visible = sideways
	_upright.visible = not sideways
	var home: Control = touch_layout if sideways else _upright
	if _pages_box.get_parent() != home:
		if _pages_box.get_parent() != null:
			_pages_box.get_parent().remove_child(_pages_box)
		if sideways:
			touch_layout.set_content(_pages_box)
		else:
			_upright.add_child(_pages_box)
	_pages_box.add_theme_constant_override("margin_left", UiTheme.TOUCH_GAP if sideways else 0)
	for pair: Array in [
		[board, _board_page], [cutaway, _page_ctl[Page.SHIP]], [_side, _page_ctl[Page.FAULTS]]
	]:
		var c: Control = pair[0]
		var page: Control = pair[1]
		if c.get_parent() != page:
			c.get_parent().remove_child(c)
			page.add_child(c)
		c.visible = true
		if page != _board_page:
			c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.custom_minimum_size = Vector2(0.0, EngineeringBoard.PHONE_H)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cutaway.custom_minimum_size = Vector2.ZERO
	_side.custom_minimum_size = Vector2.ZERO
	_fit_pages()


## Puts the board, cutaway and lists back in the desktop and tablet arrangement.
func _from_phone() -> void:
	if touch_layout != null and (touch_layout.visible or _upright.visible):
		touch_layout.visible = false
		_upright.visible = false
		_scroll_all.visible = true
		for c: Control in [cutaway, board, _side]:
			c.get_parent().remove_child(c)
			c.visible = true
			c.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_left.add_child(cutaway)
		_left.move_child(cutaway, 0)
		_row.add_child(board)
		_row.move_child(board, _left.get_index() + 1)
		_row.add_child(_side)
		cutaway.visible = not docked
		_side.visible = not docked
	var narrow: bool = size.x < NARROW
	var phone: bool = size.x < PHONE_W
	_row.vertical = phone
	cutaway.custom_minimum_size.y = 260.0 if phone else 0.0
	board.custom_minimum_size = Vector2(0, 460) if phone else Vector2(270, 0)
	_side.custom_minimum_size = Vector2(0, 220) if phone else Vector2(210, 0)
	var parent: Control = _left if narrow else _row
	_side.size_flags_stretch_ratio = 1.0 if narrow else 2.2
	if _side.get_parent() != parent:
		_side.get_parent().remove_child(_side)
		parent.add_child(_side)


## The pages start under the view-top row (top_reserve) and end above the gesture band.
func _fit_pages() -> void:
	if _pages_box == null or not _pages_box.is_inside_tree():
		return
	var tap: Rect2 = SafeArea.to_local(self, SafeArea.tap_rect(self))
	var band: float = maxf(size.y - tap.end.y, 0.0)
	var top: int = roundi(top_reserve)
	var bottom: int = roundi(band)
	if _pages_box.get_theme_constant("margin_top") != top:
		_pages_box.add_theme_constant_override("margin_top", top)
	if _pages_box.get_theme_constant("margin_bottom") != bottom:
		_pages_box.add_theme_constant_override("margin_bottom", bottom)
	for b: Dictionary in [touch_buttons, grid_buttons]:
		for id: String in b:
			(b[id] as RailButton).disabled = ship_def == null
	var claim: String = claim_text()
	for b: Dictionary in [touch_buttons, grid_buttons]:
		if b.has("claim") and (b["claim"] as RailButton).text != claim:
			(b["claim"] as RailButton).text = claim
			(b["claim"] as RailButton).disabled = crew_count() == 0


## The view the screen's view-top row covers on a phone: the pages.
func view_rect() -> Rect2:
	if _pages_box != null and _pages_box.is_visible_in_tree():
		return Rect2(_pages_box.global_position - global_position, _pages_box.size)
	return super()


## The Claim button's text: the crew it takes or releases (FT-NET-023).
func claim_text() -> String:
	if crew_count() == 0:
		return TouchText.of("eng.touch.claim", "Claim")
	var letter: String = crew_letter(crew_pick)
	var item: String = "%s:%d" % [StationViews.CLAIM_CREW, crew_pick]
	if int(ctx.crew.claims.get(item, {}).get("session", -1)) == ctx.crew.session:
		return TouchText.of("eng.touch.release_crew", "Release %s") % letter
	return TouchText.of("eng.touch.claim_crew", "Claim %s") % letter


## A rail button's intent, sent as the keyboard or the pad sends it; Claim as the common
## claim (K, View+X) does.
func press_touch(id: String) -> bool:
	if id == "claim":
		return claim_crew()
	return handle_intent({"id": id, "pressed": true, "device": "touch"})


## Takes or releases the claim on the picked crew, as the common claim does on this panel.
func claim_crew() -> bool:
	var item: String = claim_item()
	if item == "":
		return false
	if int(ctx.crew.claims.get(item, {}).get("session", -1)) == ctx.crew.session:
		ctx.intents.release_claim(item)
	else:
		ctx.intents.claim(item)
	return true


func _process(delta: float) -> void:
	var now: int = ctx.now_ms()
	while not hits.is_empty() and now - int(hits[0]["at_ms"]) > HIT_MS:
		hits.pop_front()
	if focused:
		_poll_pad(delta)
	if _pages_box.is_visible_in_tree():
		_fit_pages()
	_refresh_lists()
	cutaway.queue_redraw()
	board.queue_redraw()


## Wheel over the board's columns picks that subsystem first; wheel outside the panel
## (the radar) doesn't change pips. Runs before the screen feeds the matcher.
func _input(event: InputEvent) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return
	_wheel_outside = not get_global_rect().has_point(mb.global_position)
	if not _wheel_outside and board.is_visible_in_tree():
		var i: int = board.column_at(mb.global_position - board.global_position)
		if i >= 0:
			select(i)


func handle_intent(ev: Dictionary) -> bool:
	if not bool(ev.get("pressed", true)) or ship_def == null:
		return false
	var id: String = ev["id"]
	var kbm: bool = str(ev.get("device", IntentTable.KBM)) == IntentTable.KBM
	if id.begins_with("subsystem_") and id.trim_prefix("subsystem_").is_valid_int():
		return select(id.trim_prefix("subsystem_").to_int() - 1)
	match id:
		"subsystem_prev", "subsystem_next":
			var n: int = count()
			return n > 0 and select(posmod(selected + (1 if id == "subsystem_next" else -1), n))
		"pip_add", "pip_remove":
			if kbm and _wheel_outside:
				_wheel_outside = false
				return false
			set_pips(selected, pips_of(selected) + (1 if id == "pip_add" else -1))
		"shield_tighter", "shield_wider":
			var step: float = TIGHTNESS_STEP if id == "shield_tighter" else -TIGHTNESS_STEP
			set_tightness(tightness() + step)
		"boost":
			boost()
		"dispatch_nearest":
			dispatch_nearest()
		"harden":
			harden(selected)
		"fabricate_probe":
			fabricate_probe()
		"cause_next":
			cycle_cause(selected)
		_:
			return false
	return true


func claim_item() -> String:
	return "%s:%d" % [StationViews.CLAIM_CREW, crew_pick] if crew_count() > 0 else ""


# --- Reading the ENGINEERING block. ---


func block() -> Dictionary:
	return ctx.view.blocks.get(S.ENGINEERING, {})


## The block row of subsystem i ({} before the first snapshot).
func row(i: int) -> Dictionary:
	var rows: Array = block().get("subsystems", [])
	return rows[i] if i >= 0 and i < rows.size() else {}


func count() -> int:
	return ship_def.subsystems.size() if ship_def != null else 0


func health_frac(i: int) -> float:
	var r: Dictionary = row(i)
	return clampf(float(r.get("health", 0.0)) / ship_def.subsystems[i].health_max, 0.0, 1.0)


## Heat as a share of the fault threshold (1 = faults).
func heat_frac(i: int) -> float:
	return float(row(i).get("heat", 0.0)) / ship_def.subsystems[i].fault_heat_threshold


## The pips set on subsystem i (a value just sent shows until the snapshot agrees).
func pips_of(i: int) -> int:
	return int(_pending_value("pips:%d" % i, int(row(i).get("pips", 0))))


func pips_used() -> int:
	var total: int = 0
	for i: int in count():
		total += pips_of(i)
	return total


func boosting() -> bool:
	return int(block().get("boost_ticks", 0)) > 0


func is_boosted(i: int) -> bool:
	return boosting() and ship_def.subsystems[i].kind in [KIND.ENGINES, KIND.THRUSTERS]


func tightness() -> float:
	return float(_pending_value("tightness", float(block().get("shield_tightness", 0.0))))


func shield_frac() -> float:
	var full: float = ship_def.shields.max_strength if ship_def.shields != null else 0.0
	return clampf(float(block().get("shield_strength", 0.0)) / full, 0.0, 1.0) if full > 0 else 0.0


func spare_parts() -> int:
	return int(block().get("spare_parts", 0))


func crew_count() -> int:
	return ship_def.repair_crews if ship_def != null else 0


## The subsystem crew c works on, or -1 when idle.
func crew_job(c: int) -> int:
	for i: int in count():
		if int(row(i).get("crews", 0)) & (1 << c):
			return i
	return -1


## Whether another player holds crew c's claim (FT-NET-023).
func crew_taken(c: int) -> bool:
	var holder: Variant = ctx.view.ownership.get("claims", {}).get("crew:%d" % c)
	return holder is Array and int(holder[0]) != ctx.crew.session


## Short subsystem name ("ENG") and full name, from its kind.
func short_name(i: int) -> String:
	return tr("eng.short." + _kind_key(i))


func full_name(i: int) -> String:
	return tr("eng.name." + _kind_key(i))


static func crew_letter(c: int) -> String:
	return CREW_LETTERS[c % CREW_LETTERS.length()]


# --- Actions (each checks what the sim would refuse and says why). ---


func select(i: int) -> bool:
	if i < 0 or i >= count():
		return false
	selected = i
	return true


## Sets subsystem i's pips (FT-ENG-002): within 0..max per subsystem and the reactor cap,
## overcharge included; the reactor supplies pips and takes none (D117).
func set_pips(i: int, n: int) -> bool:
	if i < 0 or i >= count():
		return false
	var sd: SubsystemDef = ship_def.subsystems[i]
	if sd.kind == KIND.REACTOR:
		_toast("toast.eng_reactor")
		return false
	var p: int = clampi(n, 0, ship_def.power.max_pips_per_subsystem)
	var now: int = pips_of(i)
	if p == now:
		return false
	if pips_used() - now + p > ship_def.power.reactor_pips:
		_toast("toast.eng_cap")
		return false
	ctx.intents.command({"kind": "set_pips", "subsystem_kind": int(sd.kind), "pips": p})
	_pending["pips:%d" % i] = [p, ctx.now_ms()]
	return true


## Focus tightness in TIGHTNESS_STEP steps over the ship's range (FT-ENG-003, D118).
func set_tightness(t: float) -> bool:
	var def: ShieldDef = ship_def.shields
	var v: float = clampf(snappedf(t, TIGHTNESS_STEP), def.tightness_min, def.tightness_max)
	if is_equal_approx(v, tightness()):
		return false
	ctx.intents.command({"kind": "set_shield", "power": -1, "tightness": v})
	_pending["tightness"] = [v, ctx.now_ms()]
	return true


func boost() -> bool:
	if boosting():
		_toast("toast.eng_boosting")
		return false
	ctx.intents.command({"kind": "boost"})
	return true


## Sends crew c to subsystem i (FT-ENG-004, D115).
func dispatch(c: int, i: int) -> bool:
	if c < 0 or c >= crew_count() or i < 0 or i >= count() or crew_job(c) == i:
		return false
	var sd: SubsystemDef = ship_def.subsystems[i]
	if health_frac(i) >= 1.0:
		_toast("toast.eng_whole")
		return false
	if spare_parts() < sd.parts_per_repair:
		_toast("toast.eng_no_parts")
		return false
	crew_pick = c
	ctx.intents.command({"kind": "dispatch_repair", "crew": c, "subsystem_id": String(sd.id)})
	return true


func recall(c: int) -> bool:
	if crew_job(c) < 0:
		return false
	crew_pick = c
	ctx.intents.command({"kind": "recall_repair", "crew": c})
	return true


## Controller B: an idle crew to the selected subsystem, else the first crew working
## elsewhere; crews another player holds are skipped.
func dispatch_nearest() -> bool:
	var other: int = -1
	for c: int in crew_count():
		if crew_taken(c) or crew_job(c) == selected:
			continue
		if crew_job(c) < 0:
			return dispatch(c, selected)
		if other < 0:
			other = c
	if other < 0:
		_toast("toast.eng_no_crew")
		return false
	return dispatch(other, selected)


## Pre-hardens subsystem i (FT-ENG-008): the sim takes its parts and refuses a repeat.
func harden(i: int) -> bool:
	if i < 0 or i >= count():
		return false
	if hardened_ticks(i) > 0:
		_toast("toast.eng_hardened")
		return false
	if spare_parts() < ship_def.subsystems[i].harden_parts:
		_toast("toast.eng_no_parts")
		return false
	ctx.intents.command({"kind": "harden", "subsystem_id": String(ship_def.subsystems[i].id)})
	return true


## Asks for a probe fabricated from spare parts (FT-ENG-008, P11): the command is Relay's
## sim (`fabricate_probe`), which takes the parts and adds the probe.
func fabricate_probe() -> bool:
	ctx.intents.command({"kind": "fabricate_probe"})
	return true


## Ticks of hardening left on subsystem i (the block row).
func hardened_ticks(i: int) -> int:
	return int(row(i).get("hardened", 0))


## Whether subsystem i has a fault of unknown cause (FT-SIM-025).
func has_fault(i: int) -> bool:
	return bool(row(i).get("fault", false))


## Index plus 1 in the subsystem's fault_causes of the cause Science's scan found (0:
## not found yet).
func known_cause(i: int) -> int:
	return int(row(i).get("fault_cause", 0))


## Index plus 1 of the cause Engineering picked (0: none), as sent, until the snapshot
## agrees.
func picked_cause(i: int) -> int:
	return int(_pending_value("cause:%d" % i, int(row(i).get("fault_pick", 0))))


## Picks the next cause in the subsystem's list for its fault (FT-ENG-006).
func cycle_cause(i: int) -> bool:
	if i < 0 or i >= count():
		return false
	var causes: Array[StringName] = ship_def.subsystems[i].fault_causes
	if not has_fault(i) or causes.is_empty():
		_toast("toast.eng_no_fault")
		return false
	var next: int = picked_cause(i) % causes.size() + 1
	ctx.intents.command(
		{
			"kind": "pick_fault_cause",
			"subsystem_id": String(ship_def.subsystems[i].id),
			"cause": String(causes[next - 1])
		}
	)
	_pending["cause:%d" % i] = [next, ctx.now_ms()]
	return true


## A cause's name: its strings entry `eng.cause.<id>`, else the id as words.
func cause_name(i: int, index_plus_one: int) -> String:
	var id: String = String(ship_def.subsystems[i].fault_causes[index_plus_one - 1])
	var text: String = tr("eng.cause." + id)
	return text if text != "eng.cause." + id else id.replace("_", " ")


# --- Faults, queue, parts (FT-ENG-005). ---


## Seconds until the ship meets a hazard, or -1 when the countdown toggle is off for this
## view or none is coming (P11): the soonest forecast of the sim hazards the faction
## knows (the RELAY block, D208).
func hazard_eta() -> float:
	if not ctx.crew.filter().grants(ViewFilter.HAZARD_COUNTDOWNS):
		return -1.0
	return HazardEta.forecast(
		ctx.view.blocks.get(StationViews.Section.RELAY, {}).get("hazards", [])
	)


## [text, palette role] lines of the faults list, worst first.
func fault_lines() -> Array:
	var out: Array = []
	var now: int = ctx.now_ms()
	var order: Array = range(count())
	order.sort_custom(func(a: int, b: int) -> bool: return health_frac(a) < health_frac(b))
	for i: int in order:
		var h: float = health_frac(i)
		if h <= 0.0:
			out.append([tr("eng.fault_down") % full_name(i), "danger"])
		elif faults.has(i) and now - int(faults[i]) < FAULT_MS:
			out.append([tr("eng.fault_heat") % [full_name(i), roundi(h * 100)], "danger"])
		elif has_fault(i):
			out.append(_fault_line(i, h))
		elif h < 1.0:
			out.append([tr("eng.fault_damaged") % [full_name(i), roundi(h * 100)], "warn"])
		elif heat_frac(i) >= HOT:
			out.append([tr("eng.fault_hot") % full_name(i), "warn"])
	return out


## The faults-list line of a subsystem with a fault of unknown cause: the cause is
## unknown until Science's scan found it (FT-SIM-025); Engineering's pick is shown.
func _fault_line(i: int, h: float) -> Array:
	var name: String = full_name(i)
	var pick: int = picked_cause(i)
	var known: int = known_cause(i)
	var pct: int = roundi(h * 100)
	if known > 0:
		if pick == known:
			return [tr("eng.fault_right") % [name, pct, cause_name(i, known)], "warn"]
		return [tr("eng.fault_diagnosed") % [name, pct, cause_name(i, known)], "danger"]
	if pick > 0:
		return [tr("eng.fault_guess") % [name, pct, cause_name(i, pick)], "warn"]
	return [tr("eng.fault_unknown") % [name, pct], "danger"]


## The repair queue: damaged subsystems, most damaged first, with their crews.
func queue_lines() -> Array:
	var out: Array = []
	var order: Array = range(count()).filter(func(i: int) -> bool: return health_frac(i) < 1.0)
	order.sort_custom(func(a: int, b: int) -> bool: return health_frac(a) < health_frac(b))
	for i: int in order:
		var crews: PackedStringArray = []
		for c: int in crew_count():
			if crew_job(c) == i:
				crews.append(crew_letter(c))
		var who: String = ", ".join(crews) if not crews.is_empty() else tr("eng.waiting")
		out.append(
			[
				(
					"%d. %s %d%%  %s"
					% [out.size() + 1, short_name(i), roundi(health_frac(i) * 100), who]
				),
				"text"
			]
		)
	for c: int in crew_count():
		var j: int = crew_job(c)
		var text: String = tr("eng.crew") % crew_letter(c)
		text += ": " + (short_name(j) if j >= 0 else tr("eng.idle"))
		var holder: String = ctx.view.claimer("crew:%d" % c)
		if holder != "":
			text += " (%s)" % holder
		out.append([text, "text_dim"])
	return out


func _refresh_lists() -> void:
	if ship_def == null:
		return
	var lines: Array = [[tr("eng.faults"), "accent"]]
	var f: Array = fault_lines()
	lines.append_array(f if not f.is_empty() else [[tr("eng.no_faults"), "ok"]])
	for i: int in count():
		if hardened_ticks(i) > 0:
			lines.append(
				[tr("eng.hardened") % [full_name(i), ceili(hardened_ticks(i) / 60.0)], "accent"]
			)
	var hazard: float = hazard_eta()
	if hazard >= 0.0:
		lines.append([tr("eng.hazard_eta") % ceili(hazard), "warn"])
	lines.append(["", "text"])
	lines.append([tr("eng.repairs"), "accent"])
	lines.append_array(queue_lines())
	lines.append(["", "text"])
	lines.append([tr("eng.parts") % spare_parts(), "accent" if spare_parts() > 0 else "danger"])
	# Relay's probe in the making, from the RELAY block (FT-ENG-008).
	var fab: float = float(ctx.view.blocks.get(S.RELAY, {}).get("fab_left", 0.0))
	if fab > 0.0:
		lines.append([tr("relay.fab") % ceili(fab), "accent"])
	var text: String = str(lines)
	if text == _lists_text:
		return
	_lists_text = text
	for c: Node in _lists.get_children():
		_lists.remove_child(c)
		c.queue_free()
	for line: Array in lines:
		var l: Label = Label.new()
		l.text = line[0]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override("font_color", Palette.color(line[1]))
		_lists.add_child(l)


# --- Events and input. ---


func _on_sim_event(kind: StringName, p: Dictionary) -> void:
	if int(p.get("ship", -1)) != ctx.crew.ship or ship_def == null:
		return
	match String(kind):
		"hit":
			var v: Variant = p.get("vector")
			if v is Vector3:
				hits.append({"pos": v, "at_ms": ctx.now_ms()})
				if hits.size() > MAX_HITS:
					hits.pop_front()
		"fault":
			var i: int = _index_of(StringName(str(p.get("tag", ""))))
			if i >= 0:
				faults[i] = ctx.now_ms()


## Left stick moves the cutaway cursor, snapping to the nearest subsystem; right stick
## turns the cutaway (§5.3 controller).
func _poll_pad(delta: float) -> void:
	var move: Vector2 = Vector2(ctx.matcher.axis("eng_cursor_x"), ctx.matcher.axis("eng_cursor_y"))
	var spin: Vector2 = Vector2(ctx.matcher.axis("cutaway_yaw"), ctx.matcher.axis("cutaway_pitch"))
	if spin != Vector2.ZERO:
		cutaway.rotate_by(spin * TURN_RATE * delta)
	if move != Vector2.ZERO and not docked:
		var i: int = cutaway.move_cursor(move * CURSOR_SPEED * delta)
		if i >= 0:
			select(i)


func _pending_value(key: String, actual: Variant) -> Variant:
	if not _pending.has(key):
		return actual
	var p: Array = _pending[key]
	var agrees: bool = is_equal_approx(float(p[0]), float(actual))
	if agrees or ctx.now_ms() - int(p[1]) > PENDING_MS:
		_pending.erase(key)
		return actual
	return p[0]


func _toast(key: String) -> void:
	ctx.crew.toast.emit(key, {})


func _kind_key(i: int) -> String:
	return str(KIND.find_key(ship_def.subsystems[i].kind)).to_lower()


func _index_of(id: StringName) -> int:
	for i: int in count():
		if ship_def.subsystems[i].id == id:
			return i
	return -1
