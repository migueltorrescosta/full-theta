class_name SciencePanel
extends StationPanel
## Science (§5.4, S-A sensor disc + card; D51; FT-SCI-001 to FT-SCI-016): the orbitable
## 3D disc radar with icons sized by detection confidence (FT-SCI-001), the contact list
## (nearest hostile first), the contact card with a confidence bar per part (ScienceCard,
## FT-SCI-002), and the controls: passive or active sensors (FT-SCI-003), Scan and Hack
## on the selected contact, the active ping, the scan-position mark for Helm
## (FT-SCI-010), the own-ship scan (FT-SCI-009) and the claim of the one active scan or
## hack (FT-NET-022). An open scan or hack replaces the radar with its minigame
## (ScanGame, HackGame; FT-SCI-004, FT-SCI-006); the server generates and checks both
## (FT-SCI-011).
##
## KB/M: click a contact or the list, right-drag orbits the radar, wheel zooms, E scan,
## H hack, [ ] choose the hack's subsystem, P active ping, Q passive / active, M drop the
## scan-position mark, I scan the own ship. In a scan: drag (or arrows, - and =) turns
## the wireframe, Enter submits, Backspace cancels. In a hack: arrows or a tap on an
## adjacent node. Controller: left stick cursor with snap to contact, right stick
## orbit, RT scan, LT hack, d-pad up ping, down scan-position mark, left / right
## subsystem, LB sensors mode, LB + d-pad down own-ship scan; in a scan the sticks turn
## the open axes, X submits, Y cancels; in a hack the stick or d-pad moves the route.
## Touch: the buttons and the minigames' tap and drag. A lone Science panel on a phone
## moves its parts into thumb rails (SciencePhone, #28).

## Scan dial rate with a key or stick at full deflection (rad/s).
const DIAL_RATE: float = 1.6
## Controller cursor speed (px/s) and the snap distance to a contact (px).
const PAD_CURSOR_PX_S: float = 420.0
const SNAP_PX: float = 70.0
## Orbit speed of the right stick (px-equivalent/s).
const PAD_ORBIT_PX_S: float = 160.0
## A stick must pass this to count as a hack move, and fall under RELEASE to re-arm.
const STICK_MOVE: float = 0.6
const STICK_RELEASE: float = 0.3
const LIST_W: float = 190.0
const CARD_W: float = 250.0
## Under this width the list, stage and card stack (a phone, a tablet upright, D195).
const NARROW_W: float = 900.0
const STACK_LIST_H: float = 110.0
const STACK_CARD_H: float = 200.0
## Detection confidence 0..1 -> blip size factor.
const BLIP_MIN: float = 0.6
const BLIP_MAX: float = 1.7
const SESSION_NONE: int = 0
const SESSION_SCAN: int = 1
const SESSION_HACK: int = 2

## The panel's own radar: made when the panel is alone, or the first time it takes the
## phone arrangement in a joint view; it shows while own_radar() (#28), else null.
var radar: DiscRadar
var scan_game: ScanGame
var hack_game: HackGame
var card_view: ScienceCard
## The phone arrangement (SciencePhone), null in the wide layout.
var phone: SciencePhone

var _list: ItemList
var _list_key: Array = []
var _stage: Control
var _bar: HFlowContainer
var _top: BoxContainer
var _status: Label
var _buttons: Dictionary = {}
var _sub_index: int = 0
var _cursor: Vector2 = Vector2(-1, -1)
var _stick_armed: bool = true
var _last_sent: int = -2
var _rows: VBoxContainer


func _setup() -> void:
	clip_contents = true
	var rows: VBoxContainer = VBoxContainer.new()
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.add_theme_constant_override("separation", 4)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rows)
	_rows = rows
	var top: BoxContainer = BoxContainer.new()
	_top = top
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.add_theme_constant_override("separation", 4)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(top)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(LIST_W, 0)
	_list.item_selected.connect(_on_list_selected)
	top.add_child(_list)
	_stage = Control.new()
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage.clip_contents = true
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_stage)
	if _alone():
		_make_radar()
	scan_game = ScanGame.new()
	scan_game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scan_game.visible = false
	scan_game.submitted.connect(_on_scan_submitted)
	scan_game.cancelled.connect(cancel_session)
	_stage.add_child(scan_game)
	hack_game = HackGame.new()
	hack_game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hack_game.visible = false
	hack_game.moved.connect(_on_hack_move)
	hack_game.cancelled.connect(cancel_session)
	_stage.add_child(hack_game)
	card_view = ScienceCard.new()
	card_view.custom_minimum_size = Vector2(CARD_W, 0)
	card_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL if not own_radar() else 0
	top.add_child(card_view)
	_build_bar(rows)
	resized.connect(_on_resized)
	_stack()
	ctx.crew.changed.connect(_on_crew_changed)
	# A contact picked before this panel existed (late pick, reconnect) is still the
	# server's science_select to learn.
	if selected_contact() >= 0:
		_on_crew_changed(&"selection")
	ctx.crew.sim_event.connect(_on_sim_event)
	refresh()


func _build_bar(rows: VBoxContainer) -> void:
	_bar = HFlowContainer.new()
	_bar.add_theme_constant_override("h_separation", 6)
	_bar.add_theme_constant_override("v_separation", 4)
	rows.add_child(_bar)
	for spec: Array in actions():
		var b: Button = Button.new()
		b.text = tr(spec[1]) if spec[1] != "" else ""
		b.pressed.connect(spec[2])
		b.focus_mode = Control.FOCUS_NONE
		_bar.add_child(b)
		_buttons[spec[0]] = b
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.add_theme_color_override("font_color", Palette.color("text_dim"))
	_status.clip_text = true
	_status.custom_minimum_size = Vector2(120, 0)
	_bar.add_child(_status)


## The eight actions as [key, label key, command]: the bar's buttons and a phone's rails.
func actions() -> Array[Array]:
	return [
		["mode", "sci.mode_passive", _toggle_mode],
		["scan", "sci.scan", _scan],
		["hack", "sci.hack", _hack],
		["sub", "", _cycle_subsystem.bind(1)],
		["ping", "sci.ping", _ping],
		["mark", "sci.scan_mark", _scan_mark],
		["self", "sci.self_scan", _self_scan],
		["claim", "sci.claim", _claim_scan],
	]


func _on_resized() -> void:
	_arrange()
	if phone == null:
		_stack()


## A lone panel on a phone, or the focused one of a joint view, uses the phone arrangement
## for the form (rebuilt when the phone turns); elsewhere, and docked, the wide one.
func _arrange() -> void:
	var form: LayoutMode.Form = LayoutMode.Form.DESKTOP
	if is_inside_tree():
		form = SciencePhone.form_of_panel(self)
	var want: bool = (
		(_alone() or _screen_panels() == 2) and not docked and LayoutMode.is_phone(form)
	)
	if want and radar == null:
		_make_radar()
	if want and phone != null and phone.form == form:
		return
	if not want and phone == null:
		return
	if phone != null:
		phone.release()
		phone.queue_free()
		phone = null
	if want:
		phone = SciencePhone.new()
		add_child(phone)
		phone.build(self, form)
	# The left rail's slot under the contacts, on a phone on its side (#28).
	share_slot = phone.share_slot if phone != null else null
	_rows.visible = phone == null
	if phone == null:
		_stack()
	refresh()


## The list and card show unless docked; a narrow panel gives a minigame their room.
func _show_parts() -> void:
	var playing: bool = int(block().get("session", SESSION_NONE)) != SESSION_NONE
	var show: bool = not docked and not (playing and size.x < NARROW_W)
	_list.visible = show
	card_view.visible = show


## A narrow panel stacks the list above the stage and the card below it (the bar wraps by
## itself); a wide one puts them side by side.
func _stack() -> void:
	var narrow: bool = size.x < NARROW_W
	_top.vertical = narrow
	_list.custom_minimum_size = Vector2(0, STACK_LIST_H) if narrow else Vector2(LIST_W, 0)
	card_view.custom_minimum_size = Vector2(0, STACK_CARD_H) if narrow else Vector2(CARD_W, 0)
	card_view.size_flags_horizontal = (Control.SIZE_EXPAND_FILL if not own_radar() or narrow else 0)
	_show_parts()


func _mode_changed() -> void:
	_arrange()
	_show_parts()
	_bar.visible = not docked
	if radar != null:
		radar.chips = not docked


## A lone Science panel draws its own big radar and takes the whole screen; in a joint
## view the screen's one disc radar is the Science radar (orbitable while this panel has
## the focus, with `blip_scale`) and the main area holds the list, card and minigames.
func full_screen() -> bool:
	return own_radar()


## True while the panel shows its own radar: alone on the screen, or focused in a joint
## view on a phone on its side (the screen then shows it alone, #28). Upright a joint view
## keeps the screen's radar.
func own_radar() -> bool:
	if _alone():
		return true
	return (
		_screen_panels() == 2
		and not docked
		and is_inside_tree()
		and SciencePhone.form_of_panel(self) == LayoutMode.Form.PHONE_LANDSCAPE
	)


func blip_scale() -> Dictionary:
	return _blip_scale(block())


func _make_radar() -> void:
	radar = DiscRadar.new()
	radar.orbitable = true
	radar.chips = not docked
	radar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.add_child(radar)
	_stage.move_child(radar, 0)


## How many panels the station screen holding this panel has (1 when none): the dev
## seat's catalogue entry names no stations, so the screen is the one to ask.
func _screen_panels() -> int:
	var n: Node = get_parent()
	while n != null and not n is StationScreen:
		n = n.get_parent()
	return (n as StationScreen).panels.size() if n != null else 1


func _alone() -> bool:
	return ctx.crew.stations().size() <= 1


func radar_orbitable() -> bool:
	return not own_radar()


func claim_item() -> String:
	return StationViews.CLAIM_SCAN


func _process(delta: float) -> void:
	if focused:
		_poll_axes(delta)
	refresh()


# --- Reading. ---


func block() -> Dictionary:
	return ctx.view.blocks.get(StationViews.Section.SCIENCE, {})


## The section's card row of a contact, or {}.
func card_of(contact: int) -> Dictionary:
	for c: Dictionary in block().get("cards", []):
		if int(c["contact"]) == contact:
			return c
	return {}


## The selected contact's id, or -1 (marks and nothing select no contact).
func selected_contact() -> int:
	var s: Dictionary = ctx.crew.selection
	return int(s["id"]) if s.get("kind", "") == "contact" else -1


## The hackable subsystem ids of the selected contact (its class once revealed), or [].
func subsystems() -> Array[StringName]:
	var out: Array[StringName] = []
	var def: ShipDef = ScienceLookup.ship_class(int(card_of(selected_contact()).get("class_id", 0)))
	if def != null:
		for s: SubsystemDef in def.subsystems:
			out.append(s.id)
	return out


## Pushes the current section into the widgets (every frame; tests call it directly).
func refresh() -> void:
	var b: Dictionary = block()
	var session: int = int(b.get("session", SESSION_NONE))
	var own: bool = own_radar()
	if radar != null:
		radar.set_picture(ctx.picture(), ctx.crew.selection)
		radar.blip_scale = _blip_scale(b)
		radar.visible = own and session == SESSION_NONE
	_show_parts()
	_stage.visible = own or session != SESSION_NONE
	scan_game.visible = session == SESSION_SCAN
	hack_game.visible = session == SESSION_HACK
	var age: float = maxf(0.0, float(ctx.view.tick - int(b.get("session_start", 0))) / 60.0)
	if session == SESSION_SCAN:
		scan_game.load_block(b)
		scan_game.title = tr("sci.scan_title") % ctx.view.callsign(int(b.get("session_target", -1)))
		scan_game.noise_text = (
			"%s %d%%" % [tr("sci.noise"), roundi(float(b["session_noise"]) * 100.0)]
		)
		scan_game.elapsed_s = age
	elif session == SESSION_HACK:
		hack_game.load_block(b)
		hack_game.title = tr("sci.hack_title") % ctx.view.callsign(int(b.get("session_target", -1)))
		hack_game.target_text = _goal_text(b)
		hack_game.elapsed_s = age
	var sel: int = selected_contact()
	card_view.set_card(ctx.view.callsign(sel) if sel >= 0 else "", card_of(sel), _hacks_on(sel))
	_refresh_list()
	_refresh_buttons(b, session)
	if phone != null:
		phone.update(session)


func _blip_scale(b: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for c: Dictionary in b.get("cards", []):
		var conf: float = maxf(float(c["detect"]), float(c["scan"]))
		out[int(c["contact"])] = lerpf(BLIP_MIN, BLIP_MAX, clampf(conf, 0.0, 1.0))
	return out


func _hacks_on(contact: int) -> Array:
	return block().get("hacks", []).filter(
		func(h: Dictionary) -> bool: return int(h["target"]) == contact
	)


func _goal_text(b: Dictionary) -> String:
	var target: int = int(b.get("session_target", -1))
	var def: ShipDef = ScienceLookup.ship_class(int(card_of(target).get("class_id", 0)))
	var i: int = int(b.get("hack_sub", -1))
	if def != null and i >= 0 and i < def.subsystems.size():
		return String(def.subsystems[i].id)
	return "?"


func _refresh_list() -> void:
	var items: Array[Dictionary] = []
	for it: Dictionary in ctx.picture().items:
		if it["kind"] == "contact":
			items.append(it)
	items.sort_custom(_before)
	var key: Array = [items.map(func(i: Dictionary) -> int: return i["id"]), ctx.crew.selection]
	var texts: Array = items.map(_list_text)
	key.append(texts)
	if key == _list_key:
		return
	_list_key = key
	_list.clear()
	for i: int in items.size():
		_list.add_item(texts[i])
		_list.set_item_metadata(i, items[i]["id"])
		_list.set_item_custom_fg_color(i, Palette.allegiance_color(items[i]["allegiance"]))
		if ctx.crew.selection == {"kind": "contact", "id": items[i]["id"]}:
			_list.select(i)


func _before(a: Dictionary, b: Dictionary) -> bool:
	var order: String = "HUNF"
	var ra: int = order.find(a["allegiance"])
	var rb: int = order.find(b["allegiance"])
	if ra != rb:
		return ra < rb
	return (a["local"] as Vector3).length() < (b["local"] as Vector3).length()


func _list_text(it: Dictionary) -> String:
	var card: Dictionary = card_of(it["id"])
	var def: ShipDef = ScienceLookup.ship_class(int(card.get("class_id", 0)))
	var klass: String = def.display_name if def != null else "?"
	return "%s %s %.1f km" % [it["label"], klass, (it["local"] as Vector3).length() / 1000.0]


func _refresh_buttons(b: Dictionary, session: int) -> void:
	var open: bool = session != SESSION_NONE
	var holder: String = ctx.crew.claimer(StationViews.CLAIM_SCAN)
	var mine: bool = holder == ctx.settings.player_name
	(_buttons["mode"] as Button).text = tr(
		"sci.mode_active" if b.get("active", false) else "sci.mode_passive"
	)
	(_buttons["scan"] as Button).disabled = open or selected_contact() < 0
	(_buttons["hack"] as Button).disabled = open or not _can_hack()
	(_buttons["sub"] as Button).text = _sub_text()
	(_buttons["sub"] as Button).disabled = open or subsystems().is_empty()
	(_buttons["self"] as Button).disabled = open
	(_buttons["claim"] as Button).text = (
		tr("sci.release")
		if mine
		else (tr("sci.claimed_by") % holder if holder != "" else tr("sci.claim"))
	)
	if not open and _status.text == "":
		_status.text = tr("sci.hint")


func _can_hack() -> bool:
	return selected_contact() >= 0 and bool(card_of(selected_contact()).get("hack", false))


func _sub_text() -> String:
	var subs: Array[StringName] = subsystems()
	return String(subs[_sub_index % subs.size()]) if not subs.is_empty() else "-"


# --- Commands (buttons, keys and the controller all end up here). ---


func _toggle_mode() -> void:
	ctx.intents.command(
		{"kind": "science_sensor_mode", "active": not bool(block().get("active", false))}
	)


func _scan() -> void:
	var c: int = selected_contact()
	if c >= 0 and block().get("session", 0) == SESSION_NONE:
		_status.text = ""
		ctx.intents.command({"kind": "science_scan", "contact": c})


func _hack() -> void:
	var subs: Array[StringName] = subsystems()
	var c: int = selected_contact()
	if c < 0 or subs.is_empty() or block().get("session", 0) != SESSION_NONE:
		return
	_status.text = ""
	ctx.intents.command(
		{
			"kind": "science_hack",
			"contact": c,
			"subsystem_id": String(subs[_sub_index % subs.size()])
		}
	)


func _cycle_subsystem(step: int) -> void:
	var n: int = subsystems().size()
	if n > 0:
		_sub_index = posmod(_sub_index + step, n)


func _ping() -> void:
	ctx.intents.command({"kind": "science_ping"})


## FT-SCI-010: the scan-position mark for the selected contact (Helm sees where to fly).
func _scan_mark() -> void:
	var c: int = selected_contact()
	if c >= 0:
		ctx.intents.command({"kind": "science_scan_mark", "contact": c})


func _self_scan() -> void:
	ctx.intents.command({"kind": "science_self_scan"})


func _claim_scan() -> void:
	var holder: Dictionary = ctx.crew.claims.get(StationViews.CLAIM_SCAN, {})
	if int(holder.get("session", -1)) == ctx.crew.session:
		ctx.intents.release_claim(StationViews.CLAIM_SCAN)
	else:
		ctx.intents.claim(StationViews.CLAIM_SCAN)


func cancel_session() -> void:
	if block().get("session", 0) != SESSION_NONE:
		ctx.intents.command({"kind": "science_cancel"})


func _on_scan_submitted(angles: Vector3) -> void:
	ctx.intents.command(
		{"kind": "science_scan_submit", "ax": angles.x, "ay": angles.y, "az": angles.z}
	)


func _on_hack_move(n: int) -> void:
	ctx.intents.command({"kind": "science_hack_move", "node": n})


# --- Events and selection. ---


func _on_crew_changed(what: StringName) -> void:
	if what != &"selection":
		return
	var c: int = selected_contact()
	if c != _last_sent:
		_last_sent = c
		_sub_index = 0
		ctx.intents.command({"kind": "science_select", "contact": c})


func _on_list_selected(i: int) -> void:
	ctx.crew.select("contact", int(_list.get_item_metadata(i)))


func _on_sim_event(kind: StringName, p: Dictionary) -> void:
	match kind:
		&"scan_done":
			var v: Vector3 = p.get("vector", Vector3.ZERO)
			var key: String = (
				"sci.scan_locked" if str(p.get("tag", "")) == "locked" else "sci.scan_result"
			)
			_status.text = tr(key) % [roundi(float(p["value"]) * 100.0), roundi(v.x * 100.0)]
		&"hack_done":
			_status.text = tr("sci.hack_done") % roundi(float(p["value"]))
		&"hack_traced":
			_status.text = tr("sci.hack_traced")
		&"scan_failed", &"hack_failed":
			_status.text = tr("sci.failed_" + str(p.get("tag", "cancelled")))
		&"science_refused":
			_status.text = tr("sci.refused_" + str(p.get("tag", "")))
		&"self_scan_done":
			_status.text = tr("sci.self_scan_done")
		&"scan_mark":
			_status.text = tr("sci.mark_placed")


# --- Input. ---


func handle_intent(ev: Dictionary) -> bool:
	if not bool(ev.get("pressed", true)):
		return false
	var session: int = int(block().get("session", SESSION_NONE))
	var id: String = str(ev["id"])
	if session == SESSION_SCAN and id == "accept":
		scan_game.submit()
		return true
	if session != SESSION_NONE and id == "decline":
		cancel_session()
		return true
	if session == SESSION_HACK:
		var dir: int = _hack_dir(id)
		if dir != 0:
			hack_game.step(dir)
			return true
	match id:
		"sci_scan":
			_scan()
		"sci_hack":
			_hack()
		"sci_ping":
			_ping()
		"sci_mode":
			_toggle_mode()
		"sci_scan_mark":
			_scan_mark()
		"sci_self_scan":
			_self_scan()
		"sci_sub_prev":
			_cycle_subsystem(-1)
		"sci_sub_next":
			_cycle_subsystem(1)
		_:
			return false
	return true


## The hack direction a press means: the arrows, and on the controller the d-pad
## intents that are ping, scan-position mark and subsystem cycling outside a hack.
func _hack_dir(id: String) -> int:
	match id:
		"sci_right", "sci_sub_next":
			return HackGame.RIGHT
		"sci_left", "sci_sub_prev":
			return HackGame.LEFT
		"sci_down", "sci_scan_mark":
			return HackGame.DOWN
		"sci_up", "sci_ping":
			return HackGame.UP
	return 0


## The contact under the pointer or reticle (panel coordinates); none during a minigame.
func item_at(screen_pos: Vector2) -> Dictionary:
	if radar == null or not radar.visible:
		return {}
	var global: Vector2 = get_global_transform() * screen_pos
	var reach: float = SNAP_PX if screen_pos.distance_to(cursor_pos()) < 1.0 else DiscRadar.HIT_PX
	return radar.item_at(radar.get_global_transform().affine_inverse() * global, reach)


func cursor_pos() -> Vector2:
	if _cursor.x < 0.0:
		return size / 2.0
	return _cursor


## Keys and sticks. In a scan the dial axes turn the open axes; in a hack the left stick
## moves the route (the keyboard has the arrow presses); otherwise the left stick moves
## the controller cursor (it snaps to the nearest contact) and the right stick orbits.
func _poll_axes(delta: float) -> void:
	var m: InputMatcher = ctx.matcher
	var lx: float = m.axis("sci_dial_1")
	var ly: float = m.axis("sci_dial_2")
	var rx: float = m.axis("sci_dial_3")
	var session: int = int(block().get("session", SESSION_NONE))
	if session == SESSION_SCAN:
		scan_game.turn(0, lx * DIAL_RATE * delta)
		scan_game.turn(1, ly * DIAL_RATE * delta)
		scan_game.turn(2, rx * DIAL_RATE * delta)
	elif session == SESSION_HACK:
		if m.device == IntentTable.PAD:
			_stick_move(lx, ly)
	elif m.device == IntentTable.PAD and own_radar() and radar != null:
		_cursor = (cursor_pos() + Vector2(lx, ly) * PAD_CURSOR_PX_S * delta).clamp(
			Vector2.ZERO, size
		)
		var spin: Vector2 = Vector2(rx, m.axis("sci_orbit_y")) * PAD_ORBIT_PX_S * delta
		radar.yaw_deg += spin.x * DiscRadar.ORBIT_DEG_PER_PX
		radar.tilt_deg = clampf(
			radar.tilt_deg + spin.y * DiscRadar.ORBIT_DEG_PER_PX,
			DiscRadar.TILT_MIN,
			DiscRadar.TILT_MAX
		)


## A deflected stick is one hack move, then it must return before the next.
func _stick_move(x: float, y: float) -> void:
	var mag: float = maxf(absf(x), absf(y))
	if mag < STICK_RELEASE:
		_stick_armed = true
	elif _stick_armed and mag > STICK_MOVE:
		_stick_armed = false
		if absf(x) > absf(y):
			hack_game.step(HackGame.RIGHT if x > 0.0 else HackGame.LEFT)
		else:
			hack_game.step(HackGame.DOWN if y > 0.0 else HackGame.UP)
