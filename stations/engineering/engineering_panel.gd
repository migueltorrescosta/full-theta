class_name EngineeringPanel
extends StationPanel
## Engineering (T053, §5.3, layout E-A): the rotatable cutaway with subsystems coloured by
## health and heat, recent hits and repair crews (FT-ENG-001, FT-ENG-004); power pips
## per subsystem with the overcharge row, reactor cap and boost, shield power and focus
## tightness with a mirror of Helm's shield ring (FT-ENG-002, FT-ENG-003); faults, the
## repair queue and spare parts (FT-ENG-005). Docked, only the pip board shows.
##
## Reads the ENGINEERING block (ctx.snap.blocks) against the ship's ShipDef from
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

const S = StationCatalogue.Section

## Controller: cursor speed (px/s) and cutaway turn rate (rad/s) at full deflection.
const CURSOR_SPEED: float = 450.0
const TURN_RATE: float = 2.0
## [intent id, string key, English] of the rail's buttons, in their fixed order (design 2.3):
## each label a verb and its object (C3), and each sends its intent as a key or the pad does
## (Claim as the common claim). Cause, Probe and Claim hide while they can't matter
## (EngineeringModel.shown).
const TOUCH_ACTIONS: Array = [
	["pip_add", "eng.touch.pip_add", "Add power"],
	["pip_remove", "eng.touch.pip_remove", "Cut power"],
	["shield_tighter", "eng.touch.tighter", "Focus shields"],
	["shield_wider", "eng.touch.wider", "Widen shields"],
	["boost", "eng.touch.boost", "Boost engines"],
	["harden", "eng.touch.harden", "Protect part"],
	["dispatch_nearest", "eng.touch.repair", "Repair part"],
	["cause_next", "eng.touch.cause", "Guess cause"],
	["fabricate_probe", "eng.touch.probe", "Build probe"],
	["claim", "eng.touch.claim", "Take crew"],
]

## The block readers and actions (EngineeringModel), shared with the board, cutaway and phone.
var model: EngineeringModel = null
## The phone arrangement (EngineeringPhone): its pages are built in _setup.
var phone: EngineeringPhone = null
var ship_def: ShipDef:
	get:
		return model.ship_def if model != null else null
	set(def):
		model.ship_def = def
## Index in ship_def.subsystems of the subsystem pips, dispatch and the cursor act on.
var selected: int:
	get:
		return model.selected if model != null else 0
## The phone's docked rail and pages on its side (EngineeringPhone), or null.
var touch_layout: RailLayout:
	get:
		return phone.touch_layout if phone != null else null
## Intent id -> its rail button on a phone on its side.
var touch_buttons: Dictionary:
	get:
		return phone.touch_buttons if phone != null else {}
var cutaway: EngineeringCutaway
var board: EngineeringBoard
## The tablet's docked rails (C4), or null (EngineeringTablet).
var tablet_ui: EngineeringTablet = null

## Short and narrow (150 % UI scale on a desktop), the faults list uses small text and no gaps
## between rows, so it shows its lines and not only its heading (EngineeringPhone).
var compact_lists: bool = false:
	set(value):
		if value != compact_lists:
			compact_lists = value
			_lists_text = ""
			if value:
				_lists.add_theme_constant_override("separation", 0)
			else:
				_lists.remove_theme_constant_override("separation")
			_refresh_lists()

var _row: BoxContainer
var _scroll_all: ScrollContainer
var _left: VBoxContainer
var _side: PanelContainer
## The faults box's frame: no margin in the row, a TOUCH_GAP margin from the screen's edges
## under the cutaway (narrow, 150 %), so the box never touches them.
var _side_box: MarginContainer
var _lists: VBoxContainer
var _lists_text: String = ""
var _lists_margin: MarginContainer
var _lists_scroll: ScrollContainer
## The last wheel event happened outside this panel (over the radar): its pip intent is
## the radar's zoom, not ours.
var _wheel_outside: bool = false


func _setup() -> void:
	model = EngineeringModel.new(ctx, ctx.ship_def())
	phone = EngineeringPhone.new(self)
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
	cutaway.model = model
	cutaway.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cutaway.size_flags_stretch_ratio = 1.4
	_left.add_child(cutaway)
	board = EngineeringBoard.new()
	board.model = model
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_stretch_ratio = 3.0
	board.custom_minimum_size = Vector2(270, 0)
	_row.add_child(board)
	_side = PanelContainer.new()
	_side.add_theme_stylebox_override("panel", UiTheme.box("panel", "line_strong", 12, 12))
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side.custom_minimum_size = Vector2(210, 0)
	_side_box = MarginContainer.new()
	_side_box.name = "SideBox"
	_side_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side_box.add_child(_side)
	_row.add_child(_side_box)
	resized.connect(phone.place_lists)
	_lists = VBoxContainer.new()
	# Scrolls when the lists don't fit (they sit under the cutaway when narrow).
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	# The margin under the scroll makes its last visible row whole at rest (_snap_lists).
	_lists_margin = MarginContainer.new()
	_lists_margin.add_child(scroll)
	_side.add_child(_lists_margin)
	_lists_scroll = scroll
	_side.resized.connect(_snap_lists.call_deferred)
	_lists.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_lists)
	ctx.crew.sim_event.connect(model.on_sim_event)
	_refresh_lists()
	in_frame = true
	# The Crew page holds the share buttons (P28-Common): no Share opener on a phone.
	shows_shares = true
	phone.build_pages()


func _ready() -> void:
	var screen: StationScreen = self.screen()
	if screen != null:
		# A tablet keeps its form in a rotation: only its rails' arrangement changes.
		screen.form_changed.connect(func(_f: LayoutMode.Form) -> void: _apply_tablet())
		screen.resized.connect(_apply_tablet)
	# (deferred: the screen is still adding its children)
	_apply_tablet.call_deferred()


func _mode_changed() -> void:
	cutaway.visible = not docked
	_side.visible = not docked
	_side_box.visible = not docked
	board.compact = docked
	phone.place_lists()
	_apply_tablet.call_deferred()


## Builds, rebuilds (a rotation) or drops the tablet's docked rails (StationPanel.sync_tablet):
## only the focused, undocked panel of a tablet, with a ship, gets them.
func _apply_tablet() -> void:
	if not is_inside_tree() or ship_def == null:
		return
	sync_tablet(
		tablet_ui.dock if tablet_ui != null else null,
		(
			focused
			and not docked
			and LayoutMode.form_of(self) == LayoutMode.Form.TABLET
			and TabletDock.fits(LayoutMode.dp_size_of(get_viewport()))
		),
		func() -> void: tablet_ui = null,
		func(portrait: bool) -> TabletDock:
			tablet_ui = EngineeringTablet.new(self, portrait)
			update_rails()
			return tablet_ui.dock
	)


## The phone form the panel takes: PHONE_LANDSCAPE or PHONE_PORTRAIT when it shows its main
## view on a phone, else DESKTOP (a tablet, a desktop, or docked in a joint view).
func phone_form() -> LayoutMode.Form:
	if not is_inside_tree() or docked:
		return LayoutMode.Form.DESKTOP
	var f: LayoutMode.Form = LayoutMode.form_of(self)
	return f if LayoutMode.is_phone(f) else LayoutMode.Form.DESKTOP


## True upright on the Ship page: the cutaway takes the width, so the screen's radar column
## hides (Q-eng-radar); the other pages keep it.
func full_screen() -> bool:
	return (
		pages != null
		and is_inside_tree()
		and LayoutMode.form_of(self) == LayoutMode.Form.PHONE_PORTRAIT
		and pages.current == Page.SHIP
	)


func _on_page(_index: int) -> void:
	rebind_tabs()


## The rail buttons' texts and states, once a frame (EngineeringRail.update).
func update_rails() -> void:
	EngineeringRail.update(self)


## The view the screen's view-top row covers on a phone: the pages.
func view_rect() -> Rect2:
	if phone.pages_box != null and phone.pages_box.is_visible_in_tree():
		return Rect2(phone.pages_box.global_position - global_position, phone.pages_box.size)
	return super()


## The Claim button's text: Take crew, or Free crew once this player holds the picked crew
## (FT-NET-023); the rail names the crew's letter under it.
func claim_text() -> String:
	var item: String = claim_item()
	if item != "" and int(ctx.crew.claims.get(item, {}).get("session", -1)) == ctx.crew.session:
		return TouchText.of("eng.touch.release_crew", "Free crew")
	return TouchText.of("eng.touch.claim", "Take crew")


## The touch picture of the phone pages (P28-Help, TouchHelpPicture), in the 844x390 frame:
## the rail (first page only), the view-top row and each page's view.
static func touch_help() -> Array:
	var rail: Array = []
	# The rail's buttons two to a row in its 4 px padding; the view beside it, 8 px on.
	var button_width: float = (EngineeringPhone.PHONE_RAIL_WIDTH - 8.0 - UiTheme.TOUCH_GAP) / 2.0
	var view_x: float = 47.0 + EngineeringPhone.PHONE_RAIL_WIDTH + UiTheme.TOUCH_GAP
	var what: Array = [
		["pip_add", "One more pip on the picked part"],
		["pip_remove", "One pip less"],
		["tighter", "Focus the shields on a narrower arc"],
		["wider", "Spread the shields over a wider arc"],
		["boost", "Overcharge the engines for a while"],
		["harden", "Protect the picked part from hits (costs parts)"],
		["repair", "Send the nearest crew to the picked part"],
		["cause", "Guess the cause of the picked part's fault"],
		["probe", "Build a probe for Relay"],
		["claim", "Take or free a crew"],
	]
	for i: int in TOUCH_ACTIONS.size():
		var a: Array = TOUCH_ACTIONS[i]
		var r: Rect2 = Rect2(
			51.0 + (i % 2) * (button_width + UiTheme.TOUCH_GAP),
			76.0 + floori(i / 2.0) * 56.0,
			button_width,
			48.0
		)
		(
			rail
			. append(
				[
					r,
					TouchText.of(a[1], a[2]),
					TouchText.of("help.eng." + str(what[i][0]), str(what[i][1])),
				]
			)
		)
	var view: Rect2 = Rect2(view_x, 124.0, 609.0 - view_x, 236.0)
	var chip: Array = [
		Rect2(view.get_center().x - 144.0, 64.0, 288.0, 48.0),
		TouchText.of("help.chip", "Target"),
		TouchText.of("help.chip_what", "‹ › change the target; tap it to ping or mark"),
	]
	var power: Array = rail.duplicate()
	power.append(chip)
	(
		power
		. append(
			[
				view,
				TranslationServer.translate("eng.power"),
				TouchText.of("help.eng.columns", "Tap a column to pick that part"),
			]
		)
	)
	return [
		{"page": TranslationServer.translate("eng.power"), "boxes": power},
		{
			"page": TouchText.of("eng.touch.ship", "Ship"),
			"boxes":
			[
				[
					view,
					TouchText.of("eng.touch.ship", "Ship"),
					TouchText.of(
						"help.eng.cutaway",
						"Drag a crew onto a part to fix it. Drag empty space to turn."
					),
				]
			],
		},
		{
			"page": TranslationServer.translate("eng.faults"),
			"boxes":
			[
				[
					view,
					TranslationServer.translate("eng.faults"),
					TouchText.of("help.eng.faults", "Faults, repairs and parts")
				]
			],
		},
	]


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
	model.expire_hits()
	if focused:
		_poll_pad(delta)
	# A hidden panel (a station not shown on this phone) redraws and refreshes nothing: its
	# next shown frame does (R20-5; Godot draws no hidden item, this skips the rest).
	if not is_visible_in_tree():
		return
	if phone.pages_box.is_visible_in_tree():
		phone.fit_pages()
	elif tablet_ui != null:
		update_rails()
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
			model.select(i)


func handle_intent(ev: Dictionary) -> bool:
	if not bool(ev.get("pressed", true)) or ship_def == null:
		return false
	var id: String = ev["id"]
	var kbm: bool = str(ev.get("device", IntentTable.KBM)) == IntentTable.KBM
	if id.begins_with("subsystem_") and id.trim_prefix("subsystem_").is_valid_int():
		return model.select(id.trim_prefix("subsystem_").to_int() - 1)
	match id:
		"subsystem_prev", "subsystem_next":
			var n: int = model.count()
			return (
				n > 0
				and model.select(posmod(model.selected + (1 if id == "subsystem_next" else -1), n))
			)
		"pip_add", "pip_remove":
			if kbm and _wheel_outside:
				_wheel_outside = false
				return false
			model.set_pips(
				model.selected, model.pips_of(model.selected) + (1 if id == "pip_add" else -1)
			)
		"shield_tighter", "shield_wider":
			var step: float = (
				EngineeringModel.TIGHTNESS_STEP
				if id == "shield_tighter"
				else -EngineeringModel.TIGHTNESS_STEP
			)
			model.set_tightness(model.tightness() + step)
		"boost":
			model.boost()
		"dispatch_nearest":
			model.dispatch_nearest()
		"harden":
			model.harden(model.selected)
		"fabricate_probe":
			model.fabricate_probe()
		"cause_next":
			model.cycle_cause(model.selected)
		_:
			return false
	return true


func claim_item() -> String:
	return (
		"%s:%d" % [StationCatalogue.CLAIM_CREW, model.crew_pick] if model.crew_count() > 0 else ""
	)


func _refresh_lists() -> void:
	if ship_def == null:
		return
	var lines: Array = [[tr("eng.faults"), "accent"]]
	var f: Array = model.fault_lines()
	if pages != null:
		pages.set_badge(Page.FAULTS, not f.is_empty())
	lines.append_array(
		(
			f.map(
				func(l: Array) -> Array: return [EngineeringModel.severity_glyph(l[1]) + l[0], l[1]]
			)
			if not f.is_empty()
			else [[tr("eng.no_faults"), "ok"]]
		)
	)
	for i: int in model.count():
		if model.hardened_ticks(i) > 0:
			lines.append(
				[
					(
						tr("eng.hardened")
						% [model.full_name(i), ceili(model.hardened_ticks(i) / CrewState.TICK_RATE)]
					),
					"accent"
				]
			)
	var hazard: float = model.hazard_eta()
	if hazard >= 0.0:
		lines.append([tr("eng.hazard_eta") % ceili(hazard), "warn"])
	lines.append(["", "text"])
	lines.append([tr("eng.repairs"), "accent"])
	lines.append_array(model.queue_lines())
	lines.append(["", "text"])
	lines.append(
		[
			tr("eng.parts") % model.spare_parts(),
			"accent" if model.spare_parts() > 0 else "danger_text"
		]
	)
	# Relay's probe in the making, from the RELAY block (FT-ENG-008).
	var fab: float = float(ctx.snap.blocks.get(S.RELAY, {}).get("fab_left", 0.0))
	if fab > 0.0:
		lines.append([tr("relay.fab") % ceili(fab), "accent"])
	var text: String = str(lines) + str(compact_lists)
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
		if compact_lists:
			l.add_theme_font_size_override("font_size", UiTheme.SMALL_SIZE + 1)
		_lists.add_child(l)
	_snap_lists.call_deferred()


## Sizes the faults list's view to whole rows: with more lines than fit, the room below the
## last whole row becomes a margin, so no row is cut at rest (D319).
func _snap_lists() -> void:
	if _lists_margin == null or not is_inside_tree():
		return
	var room: float = (
		_lists_scroll.size.y + float(_lists_margin.get_theme_constant("margin_bottom"))
	)
	var content: float = _lists.get_combined_minimum_size().y
	var keep: float = 0.0
	if content > room:
		var sep: float = float(_lists.get_theme_constant("separation"))
		var y: float = 0.0
		for row: Node in _lists.get_children():
			var h: float = (row as Control).get_combined_minimum_size().y
			if y + h > room:
				break
			y += h + sep
			keep = y - sep
		keep = room - keep if keep > 0.0 else 0.0
	if int(keep) != _lists_margin.get_theme_constant("margin_bottom"):
		_lists_margin.add_theme_constant_override("margin_bottom", int(keep))


# --- Input. ---


## Left stick moves the cutaway cursor, snapping to the nearest subsystem; right stick
## turns the cutaway (§5.3 controller).
func _poll_pad(delta: float) -> void:
	var move: Vector2 = Vector2(ctx.matcher.axis("eng_cursor_x"), ctx.matcher.axis("eng_cursor_y"))
	var spin: Vector2 = Vector2(ctx.matcher.axis("cutaway_yaw"), ctx.matcher.axis("cutaway_pitch"))
	if spin != Vector2.ZERO:
		cutaway.rotate_by(spin * TURN_RATE * delta)
		cutaway.learned()
	if move != Vector2.ZERO and not docked:
		var i: int = cutaway.move_cursor(move * CURSOR_SPEED * delta)
		if i >= 0:
			model.select(i)
