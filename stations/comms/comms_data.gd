class_name CommsData
extends RefCounted
## Reading the COMMS block (CommsView, Section.COMMS) for Comms' board and overlay
## (FT-COM-001, FT-COM-004, FT-COM-005, FT-COM-008, FT-COM-009): the cards sorted into the
## three columns, a card's open conversation node, its market lines, and the texts. Pure
## functions of the block, so the tests need no panel.

## The columns: missions, contracts, offers with hails (§5.6).
const COLUMNS: int = 3
const COLUMN_KEYS: Array[String] = ["comms.col_missions", "comms.col_contracts", "comms.col_offers"]
## CommsView's card states (StoryTable.State).
const STATE_KEYS: Array[String] = ["open", "accepted", "declined", "done", "failed", "expired"]
## Units one buy or sell press moves, by item (default 1): fuel and ammunition come by the
## hundred and by the ten, everything else singly. PROVISIONAL.
const STEPS: Dictionary = {"propellant": 100, "ammo": 10}

static var _lines: DialogueLines = null


## The view's COMMS block, or {}.
static func block(view: NetViewState) -> Dictionary:
	return view.blocks.get(StationViews.Section.COMMS, {})


## The column a card sits in.
static func column_of(card: Dictionary) -> int:
	match int(card["kind"]):
		CardList.MISSION:
			return 0
		CardList.CONTRACT:
			return 1
	return 2


## The cards of the three columns: the live ones first (by id), then the settled ones.
static func columns(blk: Dictionary) -> Array:
	var out: Array = [[], [], []]
	var settled: Array = [[], [], []]
	for c: Dictionary in blk.get("cards", []):
		((out if CardList.is_live(c) else settled)[column_of(c)] as Array).append(c)
	for i: int in COLUMNS:
		(out[i] as Array).append_array(settled[i])
	return out


## The card row with this id, or {}.
static func card(blk: Dictionary, id: int) -> Dictionary:
	for c: Dictionary in blk.get("cards", []):
		if int(c["id"]) == id:
			return c
	return {}


## The open conversation node of a card ({"card", "line", "options"}), or {}.
static func node_of(blk: Dictionary, id: int) -> Dictionary:
	for n: Dictionary in blk.get("nodes", []):
		if int(n["card"]) == id:
			return n
	return {}


## The goods an offer card's market sells (rows of "offers" with this card).
static func offers_of(blk: Dictionary, id: int) -> Array:
	return (blk.get("offers", []) as Array).filter(
		func(o: Dictionary) -> bool: return int(o["card"]) == id
	)


## The modules an offer card's market sells, one row per slot they fit.
static func modules_of(blk: Dictionary, id: int) -> Array:
	return (blk.get("modules", []) as Array).filter(
		func(m: Dictionary) -> bool: return int(m["card"]) == id
	)


## The units of one buy or sell press for an item.
static func step_of(item: String) -> int:
	return int(STEPS.get(item.split(":")[0], 1))


## The item's name: "Parts", "Ammo (m1_cannon)", "Repair: engines".
static func item_text(item: String) -> String:
	var at: int = item.find(":")
	if at < 0:
		return TranslationServer.translate("comms.item." + item)
	var kind: String = item.substr(0, at)
	return TranslationServer.translate("comms.item." + kind) % item.substr(at + 1)


## The module's name from its key, or the key itself when it has no text.
static func module_text(key: String) -> String:
	var text: String = TranslationServer.translate("module." + key)
	return key if text == "module." + key else text


## The card's state word, translated.
static func state_text(state: int) -> String:
	return TranslationServer.translate("comms.state_" + STATE_KEYS[clampi(state, 0, 5)])


## "+4 to +12" for the reputation a card's outcome may draw, "" when its range is hidden.
static func range_text(card_row: Dictionary) -> String:
	if not bool(card_row.get("rep_vis", false)):
		return ""
	return (
		TranslationServer.translate("comms.rep_range")
		% [roundi(float(card_row["rep_lo"])), roundi(float(card_row["rep_hi"]))]
	)


## The NPC's line as text in the session language, its slots filled with the NPC's name and
## the ship's (other slots show "…"); the line id itself when the dialogue files don't have it.
static func line_text(line_id: String, npc: String, ship: String) -> String:
	if _lines == null:
		_lines = DialogueLines.load_dir()
	var data: Dictionary = _lines.line(line_id)
	if data.is_empty():
		return line_id
	var texts: Dictionary = data.get("text", {})
	var template: String = str(texts.get(TranslationServer.get_locale(), texts.get("en", line_id)))
	# Only the names are known here: a number the host fills in while speaking is "…".
	for slot: String in DialogueLines.slot_order(template):
		if slot != "npc" and slot != "ship":
			template = template.replace("{%s}" % slot, "…")
	return DialogueLines.fill(data, template, {"npc": npc, "ship": ship})
