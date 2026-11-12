class_name EngineeringRail
extends RefCounted
## Engineering's rail buttons (C4, C3): their labels, which show (EngineeringModel.shown: the
## rare actions hide while they can't matter, the others keep their fixed order), and why a
## shown one can't act now (EngineeringModel.why_not, the rule the actions' toasts use), so a
## greyed button names its reason before the tap.

## Rail buttons that act on the picked part: their second line names it (ENG), so the rail
## says what Protect part or Repair part will touch; a button that can't act shows its reason
## there.
const ON_PART: Array[String] = ["pip_add", "pip_remove", "harden", "dispatch_nearest", "cause_next"]
## The text sizes a rail tries, largest first, until every widest line fits (12 px is the
## smallest UI text, D316).
const FONT_SIZES: Array[int] = [14, 13, 12]


## The label of rail button `id`.
static func text(id: String) -> String:
	for a: Array in EngineeringPanel.TOUCH_ACTIONS:
		if a[0] == id:
			return TouchText.of(a[1], a[2])
	return id


## The rail buttons' texts, states and visibility, once a frame.
static func update(p: EngineeringPanel) -> void:
	var sets: Array[Dictionary] = [p.phone.touch_buttons, p.phone.grid_buttons]
	if p.tablet_ui != null:
		sets.append(p.tablet_ui.buttons)
	for buttons: Dictionary in sets:
		for id: String in buttons:
			var b: RailButton = buttons[id]
			if p.ship_def == null:
				b.disabled = true
				continue
			# A rare action also shows while its own lesson step asks for it, so the lesson
			# never names a hidden button (StationPanel.lesson_wants).
			var show: bool = p.model.shown(id) or p.lesson_wants(id)
			if b.visible != show:
				b.visible = show
			if not show:
				continue
			var why: String = p.model.why_not(id)
			var second: String = ""
			if why != "":
				second = p.tr("eng.reason." + why)
			elif id in ON_PART:
				second = p.model.short_name(p.selected)
			elif id == "claim":
				second = EngineeringModel.crew_letter(p.model.crew_pick)
			var base: String = p.claim_text() if id == "claim" else text(id)
			var label: String = base if second == "" else "%s\n%s" % [base, second]
			if b.text != label:
				b.text = label
			b.disabled = why != ""
		fit(buttons.values())


## Gives a rail's buttons one text size: the largest of FONT_SIZES at which every shown
## button's widest line fits it, so a longer language never cuts a label; only when a text
## or a width changed.
static func fit(buttons: Array) -> void:
	var key: Array = []
	for b: RailButton in buttons:
		if b.visible:
			key.append_array([b.text, b.size.x])
	if buttons.is_empty() or (buttons[0] as RailButton).get_meta("fit", []) == key:
		return
	(buttons[0] as RailButton).set_meta("fit", key)
	var size: int = FONT_SIZES[0]
	for b: RailButton in buttons:
		if b.visible and b.size.x > 0.0:
			size = mini(size, _fitting(b))
	for b: RailButton in buttons:
		if b.get_theme_font_size("font_size") != size:
			b.add_theme_font_size_override("font_size", size)


## The largest of FONT_SIZES at which `b`'s widest line fits it.
static func _fitting(b: RailButton) -> int:
	var font: Font = b.get_theme_font("font")
	var room: float = b.size.x - b.get_theme_stylebox("normal").get_minimum_size().x
	for fs: int in FONT_SIZES:
		var widest: float = 0.0
		for line: String in b.text.split("\n"):
			widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		if widest <= room:
			return fs
	return FONT_SIZES[-1]
