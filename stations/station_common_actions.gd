class_name StationCommonActions
extends RefCounted
## The common crew actions of a StationScreen (§5.0, R13-1): select, ping, mark, claim,
## share, cycle target, request-chip answers and the live alert / focus intents, all on the
## shared selection, marks and pings in ctx.crew (FT-STN-009, FT-STN-003).

var s: StationScreen


func _init(screen: StationScreen) -> void:
	s = screen


func run(ev: Dictionary) -> bool:
	if not bool(ev.get("pressed", true)):
		return false
	var id: String = ev["id"]
	var device: String = str(ev.get("device", IntentTable.KBM))
	var handled: bool = true
	match id:
		"select":
			handled = select(device)
		"cycle_target":
			s.ctx.crew.cycle("contact", contacts_by_range())
		"select_pinged":
			handled = s.ctx.crew.select_pinged(s.ctx.now_ms())
		"ping":
			_ping(device)
		"mark":
			mark(device)
		"accept", "decline":
			handled = s.focused_panel().handle_intent(ev) or _answer_chip(id == "accept")
		"request":
			handled = s.focused_panel().has_request_chip()
			if handled:
				s.focused_panel().send_request()
		"radar_strip":
			s.radar.toggle_strip()
		"claim":
			_claim()
		"share":
			handled = not shareable().is_empty()
			for feature: StringName in shareable():
				s.ctx.intents.share(String(feature))
		"overlay":
			# The Controls hint says this key opens the page, so it has done its job (D4).
			var chip: Node = s.find_child("ControlsHint", false, false)
			if chip != null:
				chip.queue_free()
			s.help_requested.emit()
			s._update_block()
		"menu":
			# Esc first closes an open choice sheet, then what the focused panel has open on
			# top (Comms' overlay).
			if s.sheet.is_open():
				s.sheet.cancel()
			elif not s.focused_panel().close_overlay():
				s.menu_requested.emit()
				s._update_block()
		_:
			handled = _live(id)
	return handled


## The data shortcuts this screen's stations may share with their partners (D210).
func shareable() -> Array[StringName]:
	var out: Array[StringName] = []
	if s.ctx.crew.is_crew():
		out = ShareBar.features(s.stations, s.ctx.crew.toggles)
	return out


## Answers the oldest request chip sent to this screen, the focused station's first
## (FT-PAIR-013); false when none is open.
func _answer_chip(accept: bool) -> bool:
	var open: Array[Dictionary] = ChipsReader.incoming(s.ctx.snap, s.stations)
	if open.is_empty():
		return false
	var mine: Array[Dictionary] = open.filter(
		func(c: Dictionary) -> bool: return c["to"] == s.focused_station()
	)
	s.ctx.intents.answer_chip(int((mine if not mine.is_empty() else open)[0]["id"]), accept)
	return true


## Select under the pointer; false over nothing, so the click falls through to the
## panel (owner decision in #7: LMB fires in the turret).
func select(device: String) -> bool:
	if device == IntentTable.PAD and s.focused_panel().take_select():
		return true
	var item: Dictionary = item_under_cursor(device)
	if item.is_empty() or item["kind"] == "point" or item["kind"] == "card":
		return false
	s.ctx.crew.select(item["kind"], item["id"])
	return true


func _live(id: String) -> bool:
	match id:
		"alert_cycle":
			set_alert((s.ctx.crew.alert + 1) % CrewState.ALERT_LEVELS)
		"alert_red":
			set_alert(CrewState.ALERT_RED)
		"alert_yellow":
			set_alert(CrewState.ALERT_YELLOW)
		"alert_normal":
			set_alert(CrewState.ALERT_NORMAL)
		"training_next":
			return s.training.press()
		"focus_1", "focus_2":
			var n: int = s.panels.size()
			if n <= 2:
				s.focus(0 if id == "focus_1" else 1)
			else:
				s.focus((s.focus_index + (n - 1 if id == "focus_1" else 1)) % n)
		_:
			return false
	return true


## The item under the pointer (KB/M: the radar if the mouse is over it, else the focused
## panel at the mouse) or, on a controller, under the focused panel's reticle (its
## centre unless it says otherwise).
func item_under_cursor(device: String) -> Dictionary:
	var p: StationPanel = s.focused_panel()
	if device == IntentTable.PAD:
		return p.item_at(p.cursor_pos())
	return item_at_point(s.get_global_mouse_position())


## The item at a point of the viewport: the radar's if it is there, else a panel's.
func item_at_point(at: Vector2) -> Dictionary:
	if s.radar.is_visible_in_tree() and s.radar.get_global_rect().has_point(at):
		return s.radar.item_at(at - s.radar.global_position)
	for q: StationPanel in s.panels:
		if q.is_visible_in_tree() and q.get_global_rect().has_point(at):
			return q.item_at(at - q.global_position)
	return {}


## Contact ids but the own ship (snapshots list it too), nearest first (cycle target).
func contacts_by_range() -> Array:
	return s.ctx.picture().contacts_by_range().map(func(it: Dictionary) -> int: return it["id"])


## Crew only (FT-STN-008); the server refuses others too.
func set_alert(level: int) -> void:
	if s.ctx.crew.is_crew():
		s.ctx.intents.set_alert(level)


## Ping under the cursor, else the selection (FT-SPA-016).
func _ping(device: String) -> void:
	var item: Dictionary = item_under_cursor(device)
	if item.is_empty():
		item = s.ctx.crew.selection
	s.ctx.ping_item(item)


## A long-press let go in place pings what is under the finger, else the selection.
func ping_at(at: Vector2) -> void:
	var item: Dictionary = item_at_point(at)
	if item.is_empty():
		item = s.ctx.crew.selection
	if not item.is_empty():
		s.ctx.ping_item(item)


## Mark at the cursor, or on the selection (FT-SPA-013, FT-SPA-022): refused with a
## toast when the ship has 8 marks, unless the focused panel replaces one (Relay). On a
## forward view only a contact takes a mark (FT-SPA-030).
func mark(device: String) -> void:
	if s.ctx.crew.seat == StationCatalogue.VIEWER:
		return
	var item: Dictionary = item_under_cursor(device)
	if item.is_empty():
		item = s.ctx.crew.selection
	mark_item(item)


## A long-press dragged and let go marks where the finger ends (P28-Common).
func mark_at(at: Vector2) -> void:
	mark_item(item_at_point(at))


## Marks `item` ({} does nothing): the rules of the common mark.
func mark_item(item: Dictionary) -> void:
	if s.ctx.crew.seat == StationCatalogue.VIEWER or item.is_empty():
		return
	# A forward view marks only a contact (FT-SPA-030).
	if s.focused_panel().marks_attach_only() and item.get("kind", "") != "contact":
		return
	if s.ctx.crew.marks.size() >= CrewState.MAX_MARKS:
		if not s.focused_panel().replace_mark(item):
			s._on_toast("toast.marks_full", {})
		return
	s.ctx.mark_item(-1, item)


## Claim or release the focused panel's claim item.
func _claim() -> void:
	var item: String = s.focused_panel().claim_item()
	if item == "":
		return
	var holder: Dictionary = s.ctx.crew.claims.get(item, {})
	if int(holder.get("session", -1)) == s.ctx.crew.session:
		s.ctx.intents.release_claim(item)
	else:
		s.ctx.intents.claim(item)


## A panel's common action on the selection (its Crew page).
func on_panel_common(id: String) -> void:
	match id:
		"ping":
			ping_at(Vector2(-1.0, -1.0))
		"mark":
			mark_item(s.ctx.crew.selection)
