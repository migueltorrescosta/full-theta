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
## (StationViews.ENTRIES) has both directions.
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
## The actions' button labels: intent -> [string key, English].
const ACTIONS: Dictionary = {
	"all_stop": ["glance.stop", "Stop"],
	"boost": ["glance.boost", "Boost"],
}

var text: Label = Label.new()
var action: RailButton = RailButton.make("", RailButton.Role.DANGER)
## The partner shown and the action's intent ("" none).
var partner: String = ""
var intent: String = ""


func _init() -> void:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(Palette.color("panel"), UiTheme.OVERLAY_ALPHA)
	sb.set_corner_radius_all(UiTheme.RADIUS)
	sb.content_margin_left = UiTheme.TOUCH_GAP
	sb.content_margin_right = 4.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
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
	var t: String = "%s  %s\n%s" % [tr("station." + partner_id), parts[0], parts[1]]
	if text.text != t:
		text.text = t
	action.visible = intent != ""
	if intent != "":
		action.text = TouchText.of(ACTIONS[intent][0], ACTIONS[intent][1])


## One read-out's text from the view (a dash while its block hasn't come).
static func readout(ctx: StationContext, id: String) -> String:
	var view: NetViewState = ctx.view
	var helm: Dictionary = view.blocks.get(StationViews.Section.HELM, {})
	var eng: Dictionary = view.blocks.get(StationViews.Section.ENGINEERING, {})
	var sci: Dictionary = view.blocks.get(StationViews.Section.SCIENCE, {})
	var relay: Dictionary = view.blocks.get(StationViews.Section.RELAY, {})
	var comms: Dictionary = view.blocks.get(StationViews.Section.COMMS, {})
	match id:
		"helm.speed":
			var v: Vector3i = view.kin.get("vel", Vector3i.ZERO)
			return "%d m/s" % roundi((Vector3(v) / NetCodec.VEL_Q).length())
		"helm.mode":
			return _helm_mode(ctx, helm)
		"eng.engines":
			return _pips(ctx, eng, SubsystemDef.Kind.ENGINES, "glance.engines", "Engines ⚡%d")
		"eng.weapons":
			return _pips(ctx, eng, SubsystemDef.Kind.WEAPONS, "glance.weapons", "Weapons ⚡%d")
		"eng.sensors":
			return _pips(ctx, eng, SubsystemDef.Kind.SENSORS, "glance.sensors", "Sensors ⚡%d")
		"eng.reactor":
			var used: int = 0
			for r: Dictionary in eng.get("subsystems", []):
				used += int(r.get("pips", 0))
			var def: ShipDef = ctx.ship_def()
			var cap: int = def.power.reactor_pips if def != null and def.power != null else 0
			return _t("glance.reactor", "Reactor %d/%d") % [used, cap]
		"eng.boost":
			var ticks: int = int(eng.get("boost_ticks", 0))
			if ticks > 0:
				return _t("glance.boost_on", "Boost %d s") % ceili(float(ticks) / ChipView.HZ)
			return _t("glance.boost_ready", "Boost ready")
		"eng.faults":
			var n: int = 0
			for r: Dictionary in eng.get("subsystems", []):
				n += 1 if bool(r.get("fault", false)) else 0
			return _t("glance.faults", "Faults %d") % n
		"eng.parts":
			return _t("glance.parts", "Parts %d") % int(eng.get("spare_parts", 0))
		"eng.probe":
			var left: float = float(relay.get("fab_left", 0.0))
			if left > 0.0:
				return _t("glance.probe_build", "Probe in %d s") % ceili(left)
			return _t("glance.probe_idle", "No probe building")
		"weapons.ready", "weapons.heat":
			return _mounts(view, id == "weapons.heat")
		"weapons.target", "science.weak":
			return _selection(ctx, sci, id == "science.weak")
		"science.scan":
			return _scan(ctx, sci)
		"science.mode":
			if bool(sci.get("active", false)):
				return _t("glance.active", "Active")
			return _t("glance.passive", "Passive")
		"relay.inbox":
			return _t("glance.inbox", "Inbox %d") % ctx.crew.inbox.size()
		"relay.probes":
			var out: int = 0
			for p: Dictionary in relay.get("probes", []):
				out += 1 if bool(p.get("deployed", false)) else 0
			return _t("glance.probes", "Probes %d · out %d") % [int(relay.get("stock", 0)), out]
		"relay.route":
			if ctx.crew.routes.is_empty():
				return _t("glance.no_route", "No route")
			return _t("glance.route", "Route set")
		"comms.offers":
			var live: int = 0
			for c: Dictionary in CommsData.columns(comms)[2]:
				live += 1 if CardList.is_live(c) else 0
			return _t("glance.offers", "Offers %d") % live
		"comms.docked":
			if bool(comms.get("docked", false)):
				return _t("glance.docked", "Docked: %s") % ctx.site_name(int(comms.get("site", -1)))
			return _t("glance.undocked", "Not docked")
		"comms.credits":
			return _t("glance.credits", "%d cr") % int(comms.get("credits", 0))
	return "-"


static func _t(key: String, fallback: String) -> String:
	return TouchText.of(key, fallback)


static func _helm_mode(ctx: StationContext, helm: Dictionary) -> String:
	var target: String = ctx.view.callsign(int(helm.get("target_ship", -1)))
	if bool(helm.get("all_stop", false)):
		return _t("glance.all_stop", "All stop")
	if int(helm.get("docked_site", -1)) >= 0:
		return _t("glance.docked", "Docked: %s") % ctx.site_name(int(helm["docked_site"]))
	if int(helm.get("jump_left", 0)) > 0:
		return _t("glance.jump", "Jump in %d s") % ceili(float(helm["jump_left"]) / ChipView.HZ)
	if bool(helm.get("approach", false)):
		return _t("glance.approach", "Approach %s") % target
	if bool(helm.get("face", false)):
		return _t("glance.face", "Face %s") % target
	var setpoint: int = roundi(float(helm.get("throttle_setpoint", 0.0)))
	return _t("glance.setpoint", "Set %d m/s") % setpoint


static func _pips(
	ctx: StationContext, eng: Dictionary, kind: SubsystemDef.Kind, key: String, fallback: String
) -> String:
	var def: ShipDef = ctx.ship_def()
	var rows: Array = eng.get("subsystems", [])
	var n: int = 0
	if def != null and rows.size() == def.subsystems.size():
		for i: int in rows.size():
			if def.subsystems[i].kind == kind:
				n += int(rows[i].get("pips", 0))
	return _t(key, fallback) % n


## Mounts ready to fire ("2/3 ready"), or the hottest mount's heat.
static func _mounts(view: NetViewState, heat: bool) -> String:
	var rows: Array = view.blocks.get(StationViews.Section.MOUNTS, {}).get("mounts", [])
	var ready: int = 0
	var hottest: float = 0.0
	for m: Dictionary in rows:
		hottest = maxf(hottest, float(m.get("heat", 0.0)))
		var loaded: bool = int(m.get("ammo", 0)) != 0
		if float(m.get("cooldown", 0.0)) <= 0.0 and not bool(m.get("locked", false)) and loaded:
			ready += 1
	if heat:
		return _t("glance.heat", "Heat %d %%") % roundi(100.0 * hottest)
	return _t("glance.ready", "%d/%d ready") % [ready, rows.size()]


## The selection's callsign, or how many of its weak points Science knows.
static func _selection(ctx: StationContext, sci: Dictionary, weak: bool) -> String:
	var sel: Dictionary = ctx.crew.selection
	if sel.get("kind", "") != "contact":
		return tr_none()
	var id: int = int(sel["id"])
	if not weak:
		return _t("glance.target", "Target %s") % ctx.view.callsign(id)
	for c: Dictionary in sci.get("cards", []):
		if int(c["contact"]) == id:
			var mask: int = int(c.get("weak_mask", 0))
			var n: int = 0
			while mask != 0:
				n += mask & 1
				mask >>= 1
			return _t("glance.weak", "Weak points %d") % n
	return _t("glance.weak", "Weak points %d") % 0


## Science's session, else the selected contact's scan.
static func _scan(ctx: StationContext, sci: Dictionary) -> String:
	var session: int = int(sci.get("session", 0))
	var target: String = ctx.view.callsign(int(sci.get("session_target", -1)))
	if session == 1 or session == 3:
		return _t("glance.scanning", "Scanning %s") % target
	if session == 2:
		return _t("glance.hacking", "Hacking %s") % target
	var sel: Dictionary = ctx.crew.selection
	if sel.get("kind", "") != "contact":
		return tr_none()
	for c: Dictionary in sci.get("cards", []):
		if int(c["contact"]) == int(sel["id"]):
			return (
				_t("glance.scan", "Scan %s %d %%")
				% [ctx.view.callsign(int(sel["id"])), roundi(100.0 * float(c.get("scan", 0.0)))]
			)
	return _t("glance.scan", "Scan %s %d %%") % [ctx.view.callsign(int(sel["id"])), 0]


static func tr_none() -> String:
	return _t("glance.nothing", "Nothing selected")
