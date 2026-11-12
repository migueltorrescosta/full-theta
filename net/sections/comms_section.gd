class_name CommsSection
extends SnapshotSection
## Section.COMMS: Comms' card board for one ship (FT-COM-001, FT-COM-004, FT-COM-005,
## FT-COM-008, FT-COM-009, D87), built from STORY, the economy and the module table. Like a
## block it is sent whole when any field changed, else omitted from the delta.
## It carries no Engineering data beyond the hull band (FT-PAIR-010, D68): Comms' only view
## of condition is the same at every difficulty, and nothing here names a subsystem, a
## spare part count or a heat. The claimer of each conversation comes from the ship's claims
## (`npc:<card>` items, the main thread's OwnershipSection data), so a claim change is a
## change here too; the science icon on options comes from the verify_chip toggle (P14) and
## the mission mark icon on cards from the mission_icon toggle (P15).

## Sim events only Comms gets: cards, replies, trades, modules and reputation.
const EVENTS: Array[StringName] = [
	&"card_posted",
	&"card_state",
	&"card_refused",
	&"hail_refused",
	&"reply",
	&"reply_refused",
	&"trade_done",
	&"trade_refused",
	&"module_fitted",
	&"module_sold",
	&"rep_changed",
]

## Rows a list may hold (a row count is one byte).
const MAX_CARDS: int = 48
const MAX_ROWS: int = 128
## Settled cards kept on the board besides the live ones (the newest).
const KEEP_SETTLED: int = 8

## The ship's claims as last posted, item -> [session id, name] (SnapshotWriter sets it
## before update()).
var claims: Dictionary = {}
var filter: ShortcutFilter = null


func _init(section_kind: int, owner_id: int, shortcut_filter: ShortcutFilter = null) -> void:
	super(section_kind, owner_id)
	filter = shortcut_filter


func update(world: SimWorld) -> PackedByteArray:
	var bytes: PackedByteArray = NetBlock.encode(
		StationCatalogue.BLOCKS[StationCatalogue.Section.COMMS], block(world, owner, filter, claims)
	)
	return _changed(bytes)


## The COMMS block of a ship. `by_filter` decides the science icon (null: shown);
## `ship_claims` is the ship's claims, item -> [session id, name] (OwnershipSection data).
static func block(
	world: SimWorld, ship: int, by_filter: ShortcutFilter = null, ship_claims: Dictionary = {}
) -> Dictionary:
	var out: Dictionary = {
		"docked": false,
		"site": -1,
		"credits": world.economy.credits[ship],
		"hull_band": _hull_band(world, ship),
		"rep": [],
		"cards": [],
		"nodes": [],
		"offers": [],
		"modules": [],
		"fitted": [],
	}
	var site: int = Story.docked_site(world, ship)
	out["docked"] = site >= 0
	out["site"] = site
	var faction: int = world.faction_of(ship)
	for other: int in world.reputation.others_of(faction):
		(out["rep"] as Array).append(
			{"faction": other, "value": world.reputation.value_of(faction, other)}
		)
	var verify: bool = by_filter == null or by_filter.grants(ShortcutFilter.VERIFY_CHIP)
	var icon: bool = by_filter == null or by_filter.grants(ShortcutFilter.MISSION_ICON)  # (P15)
	for card: int in _board(world, ship):
		(out["cards"] as Array).append(_card_row(world, card, ship_claims, icon))
		if world.story.node[card] != StoryTable.NO_TEXT and Story.is_live(world, card):
			(out["nodes"] as Array).append(_node_row(world, ship, card, verify))
		if world.story.kind[card] == StoryTable.Kind.OFFER and Story.is_live(world, card):
			_offer_rows(world, ship, card, out)
	for r: int in world.modules.rows_of(ship):
		var ix: int = world.modules.module_ix[r]
		(
			(out["fitted"] as Array)
			. append(
				{
					"slot": r - world.modules.row_of(ship),
					"type": world.modules.slot_type[r],
					"module": world.module_defs[ix].id if ix >= 0 else &"",
				}
			)
		)
	return out


## The cards on the ship's board: its live ones, then the newest settled ones, by id.
static func _board(world: SimWorld, ship: int) -> Array[int]:
	var live: Array[int] = []
	var settled: Array[int] = []
	for card: int in world.story.size():
		if not Story.visible_to(world, card, ship):
			continue
		if Story.is_live(world, card):
			live.append(card)
		else:
			settled.append(card)
	var out: Array[int] = []
	out.assign(settled.slice(maxi(0, settled.size() - KEEP_SETTLED)))
	out.append_array(live.slice(maxi(0, live.size() - (MAX_CARDS - out.size()))))
	out.sort()
	return out


static func _hull_band(world: SimWorld, ship: int) -> int:
	var hull: float = world.damage.health[world.damage.hull_row(ship)]
	return HealthBand.band_of(hull / world.defs[ship].hull_max, DataToggles.def().band_edges)


static func _card_row(
	world: SimWorld, card: int, ship_claims: Dictionary, icon: bool
) -> Dictionary:
	var t: StoryTable = world.story
	var range: Array[float] = Reputation.visible_range(world, t.rep_interaction[card])
	var left: float = -1.0
	if t.expires_tick[card] >= 0:
		left = maxf(0.0, float(t.expires_tick[card] - world.tick) / SimWorld.HZ)
	var item: String = "%s:%d" % [StationCatalogue.CLAIM_NPC, card]
	return {
		"id": card,
		"kind": t.kind[card],
		"state": t.state[card],
		"npc": t.npc[card],
		"title": t.title[card],
		"detail": t.detail[card],
		"expires": left,
		"reward": t.reward[card],
		"rep_vis": not range.is_empty(),
		"rep_lo": range[0] if not range.is_empty() else 0.0,
		"rep_hi": range[1] if not range.is_empty() else 0.0,
		"subject": t.subject[card],
		"claimer": ship_claims[item][0] if ship_claims.has(item) else -1,
		"conv": t.conversation[card] != &"",
		"open": t.node[card] != StoryTable.NO_TEXT,
		"requires_docked": t.requires_docked[card] == 1,
		"site": t.site[card],
		"marked": icon and StoryRules.is_marked(world, card),  # the mission icon (P15)
	}


## The open node of a card's conversation: the NPC's line id and the replies.
static func _node_row(world: SimWorld, ship: int, card: int, verify: bool) -> Dictionary:
	var options: Array = []
	for o: Dictionary in Story.options(world, card, ship):
		options.append(
			{
				"id": o["id"],
				"text": o["text"],
				"enabled": o["enabled"],
				"verify": o["verify"] and verify
			}
		)
	return {"card": card, "line": Story.node_of(world, card).get("line", ""), "options": options}


## The goods, repairs and modules an offer card's market sells, when the ship is docked at
## its site: price, what a sale pays, the cap; and for each module the slots it fits, its
## price and the trade-in the module now in the slot would fetch (FT-MIS-036).
static func _offer_rows(world: SimWorld, ship: int, card: int, out: Dictionary) -> void:
	var why: Array[StringName] = []
	var m: MarketDef = Trade.market(world, ship, card, why)
	if m == null:
		return
	var offers: Array = out["offers"]
	var items: Array = m.prices.keys()
	items.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for item: StringName in items:
		if Economy.is_item(world, ship, item) and offers.size() < MAX_ROWS:
			(
				offers
				. append(
					{
						"card": card,
						"item": item,
						"price": m.prices[item],
						"sell": Trade.sale_price(m, m.prices[item]),
						"stock": m.stock.get(item, -1),
					}
				)
			)
	var repairs: Array = m.repairs.keys()
	repairs.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	for sub: StringName in repairs:
		if world.damage.find_subsystem(ship, sub) >= 0 and offers.size() < MAX_ROWS:
			(
				offers
				. append(
					{
						"card": card,
						"item": StringName(Trade.REPAIR_PREFIX + sub),
						"price": m.repairs[sub],
						"sell": 0,
						"stock": 1,
					}
				)
			)
	var modules: Array = out["modules"]
	for key: StringName in m.modules:
		var ix: int = ModuleSystem.index_of(world, key)
		if ix < 0:
			continue
		var module: ModuleDef = world.module_defs[ix]
		for r: int in world.modules.rows_of(ship):
			if world.modules.slot_type[r] != module.slot_type or modules.size() >= MAX_ROWS:
				continue
			var slot: int = r - world.modules.row_of(ship)
			var old: ModuleDef = ModuleSystem.fitted(world, ship, slot)
			(
				modules
				. append(
					{
						"card": card,
						"module": key,
						"name": module.name_key,
						"slot": slot,
						"price": module.price,
						"old": old.id if old != null else &"",
						"trade_in": Trade.sale_price(m, old.price) if old != null else 0,
					}
				)
			)


## The claimable items of Comms: one per open conversation of the ship's board, `npc:<card>`.
static func npc_items(world: SimWorld, ship: int) -> Array[String]:
	var out: Array[String] = []
	for card: int in world.story.size():
		if (
			Story.visible_to(world, card, ship)
			and Story.is_live(world, card)
			and world.story.conversation[card] != &""
		):
			out.append("%s:%d" % [StationCatalogue.CLAIM_NPC, card])
	return out
