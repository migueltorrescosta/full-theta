class_name PartnerGlance
extends PanelContainer
## The partner glance card of a joint view on a phone (#28 follow-up, P28-Joint, design
## 1.7): the unfocused station's two key read-outs and, where the pair needs it, one urgent
## action of that station, so a player on one panel never loses the other's emergency
## control (D95's always-live set: Helm's All stop from Weapons' focus). CARDS defines the
## card of every station as the partner in each of the 15 joint views.
##
##     var card := PartnerGlance.new()
##     card.action_pressed.connect(func(id: String) -> void: _partner_intent(id))
##     card.show_for(ctx, "helm", "weapons")   # Tactical on Weapons focus: Helm's card

## The action button was tapped: `intent` is an intent id of the partner station.
signal action_pressed(intent: String)

const WIDTH: float = 200.0
const FONT: int = 13

## "partner|focused" -> [[read-out, read-out], action intent or ""]. Every joint view
## (StationCatalogue.OTHER_SEATS) has both directions.
const CARDS: Dictionary = {
	# Drive
	"helm|engineering": [["helm.speed", "helm.mode"], "all_stop"],
	"engineering|helm": [["eng.engines", "eng.boost"], "boost"],
	# Tactical
	"helm|weapons": [["helm.speed", "helm.mode"], "all_stop"],
	"weapons|helm": [["weapons.ready", "weapons.heat"], ""],
	# Survey
	"helm|science": [["helm.speed", "helm.mode"], "all_stop"],
	"science|helm": [["science.scan", "science.mode"], ""],
	# Nav
	"helm|relay": [["helm.speed", "helm.mode"], "all_stop"],
	"relay|helm": [["relay.route", "relay.inbox"], ""],
	# Approach
	"helm|comms": [["helm.speed", "helm.mode"], "all_stop"],
	"comms|helm": [["comms.offers", "comms.docked"], ""],
	# Gunnery
	"engineering|weapons": [["eng.weapons", "eng.reactor"], ""],
	"weapons|engineering": [["weapons.ready", "weapons.heat"], ""],
	# Targeting
	"science|weapons": [["science.scan", "science.weak"], ""],
	"weapons|science": [["weapons.ready", "weapons.target"], ""],
	# Fire Control
	"relay|weapons": [["relay.inbox", "relay.probes"], ""],
	"weapons|relay": [["weapons.ready", "weapons.target"], ""],
	# Parley
	"comms|weapons": [["comms.offers", "comms.docked"], ""],
	"weapons|comms": [["weapons.ready", "weapons.target"], ""],
	# Systems
	"engineering|science": [["eng.sensors", "eng.faults"], ""],
	"science|engineering": [["science.mode", "science.scan"], ""],
	# Logistics
	"engineering|relay": [["eng.probe", "eng.faults"], ""],
	"relay|engineering": [["relay.probes", "relay.inbox"], ""],
	# Quartermaster
	"engineering|comms": [["eng.faults", "eng.parts"], ""],
	"comms|engineering": [["comms.docked", "comms.credits"], ""],
	# Sensors
	"science|relay": [["science.scan", "science.mode"], ""],
	"relay|science": [["relay.probes", "relay.inbox"], ""],
	# Intel
	"science|comms": [["science.scan", "science.mode"], ""],
	"comms|science": [["comms.offers", "comms.docked"], ""],
	# Ops
	"relay|comms": [["relay.inbox", "relay.route"], ""],
	"comms|relay": [["comms.offers", "comms.credits"], ""],
}
## The actions' button labels: intent -> string key.
const ACTIONS: Dictionary = {
	"all_stop": "glance.stop",
	"boost": "glance.boost",
}

var text: Label = Label.new()
var action: RailButton = RailButton.make("", RailButton.Role.DANGER)
## The partner shown and the action's intent ("" none).
var partner: String = ""
var intent: String = ""


func _init() -> void:
	var sb: StyleBoxFlat = UiTheme.box("panel", "line_strong", 4, 4, UiTheme.OVERLAY_ALPHA)
	sb.content_margin_left = UiTheme.TOUCH_GAP
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size.x = WIDTH
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	text.add_theme_font_size_override("font_size", FONT)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.clip_text = true
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(text)
	action.name = "Action"
	action.add_theme_font_size_override("font_size", FONT)
	action.visible = false
	action.pressed.connect(func() -> void: action_pressed.emit(intent))
	row.add_child(action)


## The card of `partner` while `focused` has the focus: [[read-outs], action] ([] none).
static func card_of(partner_id: String, focused: String) -> Array:
	return CARDS.get("%s|%s" % [partner_id, focused], [])


## Shows `partner_id`'s card for a joint view focused on `focused`; hides without one.
func show_for(ctx: StationContext, partner_id: String, focused: String) -> void:
	var card: Array = card_of(partner_id, focused)
	visible = not card.is_empty()
	if card.is_empty():
		return
	partner = partner_id
	intent = card[1]
	var parts: PackedStringArray = PackedStringArray()
	for id: String in card[0]:
		parts.append(readout(ctx, id))
	var t: String = "%s  %s\n%s" % [tr(StationCatalogue.name_key(partner_id)), parts[0], parts[1]]
	if text.text != t:
		text.text = t
	action.visible = intent != ""
	if intent != "":
		action.text = tr(ACTIONS[intent])
		# A longer translation ("Impulso") widens the button instead of losing letters.
		var w: float = (
			action.get_theme_font("font").get_string_size(action.text, 0, -1, FONT).x
			+ action.get_theme_stylebox("normal").get_minimum_size().x
		)
		action.custom_minimum_size.x = maxf(UiTheme.TOUCH_PRIMARY, ceilf(w))


## One read-out's text from the view (a dash while its block hasn't come).
static func readout(ctx: StationContext, id: String) -> String:
	var snap: SnapshotState = ctx.snap
	var helm: Dictionary = snap.blocks.get(StationCatalogue.Section.HELM, {})
	var eng: Dictionary = snap.blocks.get(StationCatalogue.Section.ENGINEERING, {})
	var sci: Dictionary = snap.blocks.get(StationCatalogue.Section.SCIENCE, {})
	var relay: Dictionary = snap.blocks.get(StationCatalogue.Section.RELAY, {})
	var comms: Dictionary = snap.blocks.get(StationCatalogue.Section.COMMS, {})
	match id:
		"helm.speed":
			var v: Vector3i = snap.kin.get("vel", Vector3i.ZERO)
			return "%d m/s" % roundi((Vector3(v) / NetCodec.VEL_Q).length())
		"helm.mode":
			return _helm_mode(ctx, helm)
		"eng.engines":
			return _pips(ctx, eng, SubsystemDef.Kind.ENGINES, "glance.engines")
		"eng.weapons":
			return _pips(ctx, eng, SubsystemDef.Kind.WEAPONS, "glance.weapons")
		"eng.sensors":
			return _pips(ctx, eng, SubsystemDef.Kind.SENSORS, "glance.sensors")
		"eng.reactor":
			var used: int = 0
			for r: Dictionary in eng.get("subsystems", []):
				used += int(r.get("pips", 0))
			return TouchText.t("glance.reactor") % [used, ctx.pip_cap()]
		"eng.boost":
			var ticks: int = int(eng.get("boost_ticks", 0))
			if ticks > 0:
				return TouchText.t("glance.boost_on") % ceili(float(ticks) / ChipsReader.HZ)
			return TouchText.t("glance.boost_ready")
		"eng.faults":
			var n: int = 0
			for r: Dictionary in eng.get("subsystems", []):
				n += 1 if bool(r.get("fault", false)) else 0
			return TouchText.t("glance.faults") % n
		"eng.parts":
			return TouchText.t("glance.parts") % int(eng.get("spare_parts", 0))
		"eng.probe":
			var left: float = float(relay.get("fab_left", 0.0))
			if left > 0.0:
				return TouchText.t("glance.probe_build") % ceili(left)
			return TouchText.t("glance.probe_idle")
		"weapons.ready", "weapons.heat":
			return _mounts(snap, id == "weapons.heat")
		"weapons.target", "science.weak":
			return _selection(ctx, sci, id == "science.weak")
		"science.scan":
			return _scan(ctx, sci)
		"science.mode":
			if bool(sci.get("active", false)):
				return TouchText.t("glance.active")
			return TouchText.t("glance.passive")
		"relay.inbox":
			return TouchText.t("glance.inbox") % ctx.crew.inbox.size()
		"relay.probes":
			var out: int = 0
			for p: Dictionary in relay.get("probes", []):
				out += 1 if bool(p.get("deployed", false)) else 0
			return TouchText.t("glance.probes") % [int(relay.get("stock", 0)), out]
		"relay.route":
			if ctx.crew.routes.is_empty():
				return TouchText.t("glance.no_route")
			return TouchText.t("glance.route")
		"comms.offers":
			var live: int = 0
			for c: Dictionary in CommsData.columns(comms)[2]:
				live += 1 if CardList.is_live(c) else 0
			return TouchText.t("glance.offers") % live
		"comms.docked":
			if bool(comms.get("docked", false)):
				return TouchText.t("glance.docked") % ctx.site_name(int(comms.get("site", -1)))
			return TouchText.t("glance.undocked")
		"comms.credits":
			return TouchText.t("glance.credits") % int(comms.get("credits", 0))
	return "-"


static func _helm_mode(ctx: StationContext, helm: Dictionary) -> String:
	var target: String = ctx.snap.callsign(int(helm.get("sel_contact", -1)))
	if bool(helm.get("all_stop", false)):
		return TouchText.t("glance.all_stop")
	if int(helm.get("docked_site", -1)) >= 0:
		return TouchText.t("glance.docked") % ctx.site_name(int(helm["docked_site"]))
	if int(helm.get("jump_left", 0)) > 0:
		return TouchText.t("glance.jump") % ceili(float(helm["jump_left"]) / ChipsReader.HZ)
	if bool(helm.get("approach", false)):
		return TouchText.t("glance.approach") % target
	if bool(helm.get("face", false)):
		return TouchText.t("glance.face") % target
	var setpoint: int = roundi(float(helm.get("throttle_setpoint", 0.0)))
	return TouchText.t("glance.setpoint") % setpoint


static func _pips(
	ctx: StationContext, eng: Dictionary, kind: SubsystemDef.Kind, key: String
) -> String:
	var def: ShipDef = ctx.ship_def()
	var rows: Array = eng.get("subsystems", [])
	var n: int = 0
	if def != null and rows.size() == def.subsystems.size():
		for i: int in rows.size():
			if def.subsystems[i].kind == kind:
				n += int(rows[i].get("pips", 0))
	return TouchText.t(key) % n


## Mounts ready to fire ("2/3 ready"), or the hottest mount's heat.
static func _mounts(snap: SnapshotState, heat: bool) -> String:
	var rows: Array = snap.blocks.get(StationCatalogue.Section.MOUNTS, {}).get("mounts", [])
	var ready: int = 0
	var hottest: float = 0.0
	for m: Dictionary in rows:
		hottest = maxf(hottest, float(m.get("heat", 0.0)))
		var loaded: bool = int(m.get("ammo", 0)) != 0
		if float(m.get("cooldown", 0.0)) <= 0.0 and not bool(m.get("locked", false)) and loaded:
			ready += 1
	if heat:
		return TouchText.t("glance.heat") % roundi(100.0 * hottest)
	return TouchText.t("glance.ready") % [ready, rows.size()]


## The selection's callsign, or how many of its weak points Science knows.
static func _selection(ctx: StationContext, sci: Dictionary, weak: bool) -> String:
	var sel: Dictionary = ctx.crew.selection
	if sel.get("kind", "") != "contact":
		return tr_none()
	var id: int = int(sel["id"])
	if not weak:
		return TouchText.t("glance.target") % ctx.snap.callsign(id)
	for c: Dictionary in sci.get("cards", []):
		if int(c["contact"]) == id:
			var mask: int = int(c.get("weak_mask", 0))
			var n: int = 0
			while mask != 0:
				n += mask & 1
				mask >>= 1
			return TouchText.t("glance.weak") % n
	return TouchText.t("glance.weak") % 0


## Science's minigame, else the selected contact's scan.
static func _scan(ctx: StationContext, sci: Dictionary) -> String:
	var minigame: int = int(sci.get("minigame", 0))
	var target: String = ctx.snap.callsign(int(sci.get("minigame_contact", -1)))
	if minigame == 1 or minigame == 3:
		return TouchText.t("glance.scanning") % target
	if minigame == 2:
		return TouchText.t("glance.hacking") % target
	var sel: Dictionary = ctx.crew.selection
	if sel.get("kind", "") != "contact":
		return tr_none()
	for c: Dictionary in sci.get("cards", []):
		if int(c["contact"]) == int(sel["id"]):
			return (
				TouchText.t("glance.scan")
				% [ctx.snap.callsign(int(sel["id"])), roundi(100.0 * float(c.get("scan", 0.0)))]
			)
	return TouchText.t("glance.scan") % [ctx.snap.callsign(int(sel["id"])), 0]


static func tr_none() -> String:
	return TouchText.t("glance.nothing")
