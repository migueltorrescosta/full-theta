class_name DebriefCard
extends PanelContainer
## The end-of-run debrief (FT-MIS-006, FT-MIS-010, FT-MIS-038, FT-PAIR-013, D35), opened
## from the OutcomeCard: the encounters with ship losses and fled encounters told apart, the
## director's decisions with their reasons, when each station first used each core action,
## and the cooperative events per pair. The record is RunDebrief.for_ship, sent with
## `run_over`; text() turns it into the lines shown, in the session language.

const MIN_SIZE: Vector2 = Vector2(720.0, 420.0)
## Director decisions shown at most; the session log holds all of them.
const MAX_DECISIONS: int = 24

var ctx: StationContext

var _body: Label


func setup(context: StationContext) -> void:
	ctx = context
	custom_minimum_size = MIN_SIZE
	var col: VBoxContainer = VBoxContainer.new()
	add_child(col)
	var title: Label = Label.new()
	title.theme_type_variation = "TitleLabel"
	title.text = _t("debrief.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_body = Label.new()
	_body.name = "Body"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	ctx.crew.changed.connect(_on_crew_changed)
	refresh()


## Whether the debrief of the own ship has arrived.
func available() -> bool:
	return not ctx.crew.debrief.get(ctx.crew.ship, {}).is_empty()


func refresh() -> void:
	_body.text = "\n".join(text(ctx.crew.debrief.get(ctx.crew.ship, {})))


## The debrief record as lines of text in the current language.
static func text(d: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if d.is_empty():
		return out
	out.append(
		(
			_t("debrief.run")
			% [_t("debrief.result.%s" % d.get("result", "open")), clock(float(d.get("run_s", 0.0)))]
		)
	)
	out.append("")
	out.append(_t("debrief.encounters"))
	var rows: Array = d.get("encounters", [])
	for i: int in rows.size():
		out.append(_encounter_line(i + 1, rows[i]))
	out.append(_t("debrief.losses") % [int(d.get("losses", 0)), rows.size(), int(d.get("fled", 0))])
	out.append("")
	out.append(_t("debrief.director"))
	var decisions: Array = d.get("decisions", [])
	for i: int in mini(decisions.size(), MAX_DECISIONS):
		out.append(_decision_line(decisions[i]))
	if decisions.size() > MAX_DECISIONS:
		out.append(_t("debrief.more") % (decisions.size() - MAX_DECISIONS))
	out.append("")
	out.append(_t("debrief.first_use"))
	var first: Dictionary = d.get("first_use", {})
	for station: String in first:
		out.append(_first_use_line(station, first[station]))
	var coop: Array = d.get("coop", [])
	if not coop.is_empty():
		out.append("")
		out.append(_t("debrief.pairs"))
		for row: Dictionary in coop:
			out.append(_pair_line(row))
	return out


## "m:ss" of a time in seconds.
static func clock(seconds: float) -> String:
	var s: int = int(seconds)
	return "%d:%02d" % [s / 60, s % 60]


static func _encounter_line(n: int, row: Dictionary) -> String:
	var how: String = "ended"
	if row.get("lost", false):
		how = "lost"
	elif row.get("fled", false):
		how = "fled"
	else:
		how = str(row.get("result", "won"))
	var site: String = (
		_t(str(row.get("site_name_key", ""))) if row.get("site_name_key", "") != "" else "-"
	)
	return (
		"%d. %s, %s: %s, %s"
		% [
			n,
			_t("debrief.scenario.%s" % row.get("scenario", "")),
			site,
			_t("debrief.res.%s" % how),
			clock(float(row.get("s", 0.0))),
		]
	)


static func _decision_line(d: Dictionary) -> String:
	var args: Dictionary = (d.get("reason_args", {}) as Dictionary).duplicate()
	if args.has("site"):
		args["site"] = _t("site.%s" % args["site"])
	var reason: String = _t(str(d.get("reason_key", ""))).format(args)
	var what: String = _t("debrief.kind.%s" % d.get("kind", "SKIP"))
	if str(d.get("scenario_id", "")) != "":
		what += " " + _t("debrief.scenario.%s" % d["scenario_id"])
	return "%s  %s: %s" % [clock(float(d.get("tick", 0)) / SimWorld.HZ), what, reason]


static func _first_use_line(station: String, actions: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for action: String in actions:
		var s: float = float(actions[action])
		parts.append("%s %s" % [_t("debrief.core.%s" % action), "-" if s < 0.0 else clock(s)])
	return "%s: %s" % [_t("debrief.station.%s" % station), ", ".join(parts)]


static func _pair_line(row: Dictionary) -> String:
	var names: PackedStringArray = PackedStringArray()
	for station: String in row.get("stations", []):
		names.append(_t("debrief.station.%s" % station))
	return _t("debrief.pair") % [" + ".join(names), int(row.get("events", 0))]


static func _t(key: String) -> String:
	return TranslationServer.translate(key)


func _on_crew_changed(what: StringName) -> void:
	if what == &"debrief" or what == &"reset" or what == &"picked":
		refresh()
