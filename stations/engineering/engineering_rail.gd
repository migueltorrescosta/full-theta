class_name EngineeringRail
extends RefCounted
## Engineering's rail buttons (C4): their labels, and why one can't act now
## (EngineeringModel.why_not, the rule the actions' toasts use), so a greyed button names its
## reason before the tap.

## Rail buttons that act on the picked part: their second line names it (ENG), so the rail
## says what Harden or Repair will touch; a button that can't act shows its reason there.
const ON_PART: Array[String] = ["pip_add", "pip_remove", "harden", "dispatch_nearest", "cause_next"]


## The label of rail button `id`.
static func text(id: String) -> String:
	for a: Array in EngineeringPanel.TOUCH_ACTIONS:
		if a[0] == id:
			return TouchText.of(a[1], a[2])
	return id


## The rail buttons' texts and states, once a frame.
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
			var why: String = p.model.why_not(id)
			var second: String = ""
			if why != "":
				second = p.tr("eng.reason." + why)
			elif id in ON_PART:
				second = p.model.short_name(p.selected)
			var base: String = p.claim_text() if id == "claim" else text(id)
			var label: String = base if second == "" else "%s\n%s" % [base, second]
			if b.text != label:
				b.text = label
			b.disabled = why != ""
