# gdlint: disable=max-public-methods
class_name StationPanel
extends Control
## Base of every station panel (FT-JNT-001). A StationScreen holds one panel for a
## single station, two for a joint view (six for the dev entry); one is focused at a
## time and only it receives its station's intents, apart from the intents live on the
## device (IntentTable.target). The focused panel shows its main view (cockpit, turret,
## cutaway, map) in the screen's main area; the others show their compact docked view.
##
## Subclass it in stations/<station>/, register the script in StationRegistry, and
## override the virtuals below. Read state through `ctx` (StationContext): ctx.view and
## ctx.interp for the snapshot, ctx.crew for selection, marks, pings, claims; send with
## ctx.intents. Never name sim/ (FT-ARC-011).
##
## On a phone (#28 follow-up, design "Shared frame") a panel may set `pages` (PageHost): the
## screen shows its tabs in the top bar or the bottom tab bar. A panel that sets `in_frame`
## gets the view-top row (selection chip, request chips, partner glance, ping toast) over
## `top_reserve` px at the top of `view_rect()`; `sheet` is the screen's ChoiceSheet for
## one-level choices.

## The panel asks the screen for a common action on the selection: "ping", "mark" (a Crew
## page's buttons, CrewPage).
signal common_requested(id: String)

## The station this panel serves (IntentTable group).
var station: String = ""
var ctx: StationContext = null
var focused: bool = false
var docked: bool = false
## True while the panel shows the screen's share buttons itself (Relay's phone drawer):
## the screen then shows no Share opener of its own (#28).
var shows_shares: bool = false
## Where the screen's Share opener goes on a phone on its side while the radar column is
## hidden (#28): a container in the panel's rails, or null for the bottom of the view.
var share_slot: Container = null
## Height (px) at the bottom of the panel that the screen's joint switch and Share opener
## cover on a phone on its side (#28); a hand-drawn view keeps its read-outs above it.
var bottom_reserve: float = 0.0
## The panel's pages on a phone (null: one page, no tabs).
var pages: PageHost = null
## Height (px) at the top of view_rect() that the screen's view-top row covers on a phone; a
## hand-drawn view keeps its read-outs under it.
var top_reserve: float = 0.0
## The screen's choice sheet (set by the screen before setup; null in bare tests).
var sheet: ChoiceSheet = null
## The panel is laid out for the phone frame (#28 follow-up): it keeps its read-outs under
## `top_reserve` and every tap target out of the bottom gesture band (RailLayout's rails do;
## a tappable range label at the view's foot doesn't). On a phone the screen then shows the
## view-top row and long-press over it, and on its side lets its view draw into the band
## (P28-Band). Panels not yet in the frame keep the chip strip and stop above the band.
var in_frame: bool = false
## Station extras for the phone's selection sheet after Ping, Mark here and Clear (Science's
## Scan and Hack, Relay's Route and Send): [[label, Callable], ...].
var selection_extras: Array = []

var _chip_menu: ChipMenu = null


## Called once by the screen before the panel enters the tree.
func setup(context: StationContext, station_id: String) -> void:
	ctx = context
	station = station_id
	_setup()


## Focus and dock state; the screen calls it on every focus change.
func set_mode(is_focused: bool, is_docked: bool) -> void:
	focused = is_focused
	docked = is_docked
	_mode_changed()
	queue_redraw()


# --- Virtuals. ---


## Build children here (ctx and station are set).
func _setup() -> void:
	pass


## Focus or dock state changed: switch between the main and the compact view.
func _mode_changed() -> void:
	pass


## A station intent event (InputMatcher's dictionary) routed to this panel; return true
## when handled. Axis intents are polled instead: ctx.matcher.axis(id).
func handle_intent(_event: Dictionary) -> bool:
	return false


## The item under the cursor or reticle for select / ping / mark (§5.0: in cockpit and
## turret views "under the cursor" means under the reticle): {"kind", "id"} or
## {"kind": "point", "site", "pos"}; {} for nothing. `screen_pos` is in this panel's
## coordinates.
func item_at(_screen_pos: Vector2) -> Dictionary:
	return {}


## Esc (the common menu) first closes what the panel has open on top of its view (Comms'
## overlay): true when it closed something, else the menu opens.
func close_overlay() -> bool:
	return false


## A pressed on a controller, the common select, offered to the focused panel first: a panel
## with a focus of its own (Comms' card board) takes it and returns true.
func take_select() -> bool:
	return false


## Where a controller's "under the cursor" points on this panel (its coordinates): the
## reticle at the centre unless the panel moves a cursor (Relay's map).
func cursor_pos() -> Vector2:
	return size / 2.0


## The part of the panel its view shows through, in its coordinates: the free part of a
## RailLayout in the panel (between overlay rails, or a docked layout's view), else the whole
## panel. The screen puts its view-top row at the top of it.
func view_rect() -> Rect2:
	var layout: RailLayout = _rail_layout(self, 3)
	if layout != null:
		return layout.content_rect_in(self)
	return Rect2(Vector2.ZERO, size)


## True when the panel draws its own radar and wants the whole screen when it is alone
## (the main screen's wide radar, §5.8): the screen hides its side column.
func full_screen() -> bool:
	return false


## The ship has 8 marks and the common mark action wants `item` (as item_at returns):
## a panel that may replace one (Relay, FT-SPA-022) does it and returns true; false
## shows the "marks full" toast.
func replace_mark(_item: Dictionary) -> bool:
	return false


## True when the panel's main view looks forward (Helm's cockpit, the turret): a mark
## there attaches to the tapped contact and a tap that hits none places no mark
## (FT-SPA-030).
func marks_attach_only() -> bool:
	return false


## True when the panel has request chips to send (B / View+Y sends one, §5.0, §7.4).
func has_request_chip() -> bool:
	return not request_chips().is_empty()


## The panel's request-chip handler (B, View+Y): one chip is sent at once, several open a
## numbered list (B, then 1-2, FT-STN-010). FT-JNT-005: a request to a station on this same
## screen (ctx.crew.stations()) runs as the direct action instead of a chip (Boost in a
## Helm+Engineering view overcharges at once). A chip is player-initiated only (FT-PAIR-012):
## nothing here sends one on its own.
func send_request() -> void:
	var chips: Array[ChipDef] = request_chips()
	if _chip_menu != null and _chip_menu.visible:
		_chip_menu.close()
	elif chips.size() == 1:
		send_chip(chips[0])
	elif chips.size() > 1:
		if _chip_menu == null:
			_chip_menu = ChipMenu.new()
			_chip_menu.chosen.connect(func(i: int) -> void: send_chip(request_chips()[i]))
			add_child(_chip_menu)
		var labels: PackedStringArray = PackedStringArray()
		for c: ChipDef in chips:
			labels.append(chip_label(c))
		_chip_menu.open(tr("chip.menu"), labels)


## The chips this station can send now, from the data list (content/chips/chips.tres): the
## ones from this station, to a station on this screen (direct action) or, while the
## session's chips toggle is on (Hard turns them off, FT-PAIR-009), to another.
func request_chips() -> Array[ChipDef]:
	var out: Array[ChipDef] = []
	if ctx == null:
		return out
	for c: ChipDef in NetChips.def().chips:
		if String(c.from_station) != station:
			continue
		if _on_screen(c) or ctx.crew.toggles.on(ViewFilter.CHIPS):
			out.append(c)
	return out


## The argument a chip carries from this panel: the mount index of "bring mount N to bear"
## (Weapons overrides), a contact id, or -1.
func chip_arg(_chip: ChipDef) -> int:
	return -1


## The chip's text for this panel's menu.
func chip_label(chip: ChipDef) -> String:
	return ChipView.label({"chip": String(chip.id), "arg": chip_arg(chip)})


## Sends a chip, or runs it as a direct action when the receiving station is on this screen.
func send_chip(chip: ChipDef) -> void:
	if _on_screen(chip):
		_direct(chip)
	else:
		ctx.intents.send_chip(String(chip.id), chip_arg(chip))


## The claim item the common claim action (K, View+X) takes or releases on this panel
## (e.g. "flight", "mount:2"); "" when it has none.
func claim_item() -> String:
	return ""


## Whether mouse motion steers this panel (the mouse stick behind "MouseX"/"MouseY")
## while it has focus; Helm says no while the pointer is free.
func mouse_steers() -> bool:
	return true


## Whether the disc radar should be orbitable on this panel's screen (FT-SPA-011:
## Science and Relay yes, Helm and Weapons insets fixed).
func radar_orbitable() -> bool:
	return station in ["science", "relay"]


## Contact id -> blip size factor for the screen's disc radar while this panel is
## focused (Science's detection confidence, FT-SCI-001); {} draws every blip alike.
func blip_scale() -> Dictionary:
	return {}


## The first visible RailLayout under `node`, `depth` levels down at most.
static func _rail_layout(node: Node, depth: int) -> RailLayout:
	for c: Node in node.get_children():
		if c is RailLayout and (c as RailLayout).is_visible_in_tree():
			return c
		if depth > 1:
			var found: RailLayout = _rail_layout(c, depth - 1)
			if found != null:
				return found
	return null


## Whether the chip's receiving station is on this screen too (a joint view).
func _on_screen(chip: ChipDef) -> bool:
	return ctx.crew.stations().has(String(chip.to_station))


## FT-JNT-005: the commands a request between a joint view's own stations stands for. Each
## chip is one command of the receiving station, run with the sender's own data: Boost and
## fabricate a probe need none; power is one more pip (the reactor cap and the per-
## subsystem maximum still apply, so the player takes power from something else); bring to
## bear turns the requested mount's rest direction onto the selected contact; the scan mark
## places Science's mark.
## Hold fire (Comms to Weapons) in Parley, which holds both, has no direct action: the toast
## says so.
func _direct(chip: ChipDef) -> void:
	match chip.id:
		&"boost":
			ctx.intents.command({"kind": "boost"})
		&"fabricate_probe":
			ctx.intents.command({"kind": "fabricate_probe"})
		&"power":
			_more_pips(SubsystemDef.Kind.WEAPONS)
		&"sensor_power":
			_more_pips(SubsystemDef.Kind.SENSORS)
		&"bring_to_bear":
			_bring_to_bear(chip_arg(chip))
		&"scan_mark":
			_scan_mark()
		_:
			ctx.crew.toast.emit("toast.chip_same_screen", {})


## One more pip on the ship's first subsystem of `kind`, from the ENGINEERING block of the
## view (a joint view with Engineering has it).
func _more_pips(kind: SubsystemDef.Kind) -> void:
	var def: ShipDef = ctx.ship_def()
	var rows: Array = ctx.view.blocks.get(StationViews.Section.ENGINEERING, {}).get(
		"subsystems", []
	)
	if def == null or def.power == null or rows.size() != def.subsystems.size():
		return
	var at: int = -1
	var used: int = 0
	for i: int in rows.size():
		used += int(rows[i].get("pips", 0))
		if at < 0 and def.subsystems[i].kind == kind:
			at = i
	if at < 0:
		return
	var pips: int = int(rows[at].get("pips", 0)) + 1
	if pips > def.power.max_pips_per_subsystem:
		ctx.crew.toast.emit("toast.chip_pips_max", {})
	elif used + 1 > def.power.reactor_pips:
		ctx.crew.toast.emit("toast.eng_cap", {})
	else:
		ctx.intents.command({"kind": "set_pips", "subsystem_kind": int(kind), "pips": pips})


## Turns the rest direction of the requested mount (-1: the bow) onto the selected contact
## (Helm's Align with the mount, FT-JNT-005).
func _bring_to_bear(mount_index: int) -> void:
	var sel: Dictionary = ctx.crew.selection
	if sel.get("kind", "") != "contact":
		ctx.crew.toast.emit("toast.select_first", {})
		return
	ctx.intents.command(
		{
			"kind": "helm_select_target",
			"target_ship": int(sel["id"]),
			"point": false,
			"x": 0.0,
			"y": 0.0,
			"z": 0.0
		}
	)
	ctx.intents.command({"kind": "helm_align", "mount_index": mount_index})


## Science's scan-position mark for the selected contact (Helm sees where to fly).
func _scan_mark() -> void:
	var sel: Dictionary = ctx.crew.selection
	if sel.get("kind", "") != "contact":
		ctx.crew.toast.emit("toast.select_first", {})
		return
	ctx.intents.command({"kind": "science_scan_mark", "contact": int(sel["id"])})
