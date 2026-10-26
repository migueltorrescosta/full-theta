class_name CommsFixture
extends RefCounted
## A COMMS block (CommsView's schema) for the station tests, and a screen showing it: a
## rescue mission about H2, an escort contract, Kappa's trade offer (docked at site 0, the
## session in conversation, a module swap on offer), and an unanswered hail from U3.

const MISSION: int = 0
const CONTRACT: int = 1
const OFFER: int = 2
const HAIL: int = 3
const SITE: int = 0


static func card(id: int, kind: int, title: String, extra: Dictionary = {}) -> Dictionary:
	var row: Dictionary = {
		"id": id,
		"kind": kind,
		"state": 0,
		"npc": "",
		"title": title,
		"detail": "",
		"expires": -1.0,
		"reward": 0,
		"rep_vis": false,
		"rep_lo": 0.0,
		"rep_hi": 0.0,
		"target": -1,
		"claimer": -1,
		"conv": false,
		"open": false,
		"requires_docked": false,
		"site": -1,
	}
	row.merge(extra, true)
	return row


static func block() -> Dictionary:
	return {
		"docked": true,
		"site": SITE,
		"credits": 1200,
		"hull_band": 0,
		"rep": [{"faction": 1, "value": 12.0}, {"faction": 2, "value": -2.0}],
		"cards":
		[
			card(
				MISSION,
				MISSION,
				"card.rescue.title",
				{
					"detail": "card.rescue.detail",
					"expires": 570.0,
					"reward": 250,
					"rep_vis": true,
					"rep_lo": 4.0,
					"rep_hi": 12.0,
					"target": StationFixture.H2,
				}
			),
			card(CONTRACT, CONTRACT, "card.escort.title", {"reward": 400}),
			card(
				OFFER,
				OFFER,
				"comms.card.offer",
				{"npc": "Kappa", "conv": true, "open": true, "site": SITE}
			),
			card(
				HAIL,
				HAIL,
				"comms.card.hail",
				{"npc": "Trader", "conv": true, "target": StationFixture.U3}
			),
		],
		"nodes":
		[
			{
				"card": OFFER,
				"line": "npc.trade_offer",
				"options":
				[
					{"id": "o5", "text": "comms.opt.back", "enabled": true, "verify": false},
					{"id": "o3", "text": "comms.opt.call_bluff", "enabled": true, "verify": true},
					{"id": "o4", "text": "comms.opt.close", "enabled": true, "verify": false},
				],
			}
		],
		"offers":
		[
			{"card": OFFER, "item": "parts", "price": 25, "sell": 12, "stock": 20},
			{"card": OFFER, "item": "propellant", "price": 2, "sell": 1, "stock": 5000},
			{"card": OFFER, "item": "repair:engines", "price": 300, "sell": 0, "stock": 1},
		],
		"modules":
		[
			{
				"card": OFFER,
				"module": "hx2_afterburner",
				"name": "module.hx2_afterburner",
				"slot": 0,
				"price": 900,
				"old": "bx3_reactor",
				"trade_in": 450,
			}
		],
		"fitted":
		[
			{"slot": 0, "type": "reactor", "module": "bx3_reactor"},
			{"slot": 1, "type": "sensor", "module": ""},
		],
	}


## Puts the block, site 0's name and the context's claim of the hail on `ctx`.
static func install(ctx: StationContext, blk: Dictionary = block()) -> void:
	ctx.view.blocks[StationViews.Section.COMMS] = blk
	ctx.crew.sites = [{"site": SITE, "name": "Kappa"}]
