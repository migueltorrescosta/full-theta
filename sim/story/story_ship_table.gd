class_name StoryShipTable
extends SimTable
## Each ship's story state (#10, D86): where STORY last saw it docked, so a dock is an
## arrival only once (StoryRules._watch_docks), and the market OFFER card its dock posted,
## which lapses when it undocks. One row per ship, in id order, so a ship's row is its id.

## The site the ship was docked at when STORY last looked, or -1.
var seen_dock: PackedInt32Array = PackedInt32Array()
## The ship's dock market card, or -1.
var dock_offer: PackedInt32Array = PackedInt32Array()


func add_ship(ship_id: int, faction: int, _def: ShipDef) -> void:
	add_key(ship_id, faction)
	seen_dock.append(-1)
	dock_offer.append(-1)


func columns() -> Array:
	return super() + [["seen_dock", seen_dock], ["dock_offer", dock_offer]]


## Story state outlives a ship reset, like the cards.
func reset_ship(_ship_id: int, _def: ShipDef) -> void:
	pass
