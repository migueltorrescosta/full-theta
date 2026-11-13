class_name CommsRows
extends RefCounted
## The actionable lines of a comms card, one small class per kind: its text, the command
## it sends, and which of the Buy and Sell keys it answers.


## A line of the overlay. `kind` names the subclass for callers that only filter by it.
class Row:
	extends RefCounted
	var kind: String = ""

	func text() -> String:
		return ""

	## The intent that Enter, a click or the Buy key sends for card `card`; {} for none.
	func command(_card: int, _buy: bool = true) -> Dictionary:
		return {}

	func can_buy() -> bool:
		return false

	func can_sell() -> bool:
		return false

	## The intent that the Buy (`buy`) or Sell key sends; {} when the line has no such step.
	func trade(card: int, buy: bool) -> Dictionary:
		return command(card, buy) if (can_buy() if buy else can_sell()) else {}


## A reply to the NPC, numbered `n`; a refused one (`enabled` false) only shows a note.
class Reply:
	extends Row
	var id: String
	var n: int
	var label: String
	var enabled: bool
	var verify: bool

	func _init(o: Dictionary, number: int) -> void:
		kind = "reply"
		id = o["id"]
		n = number
		label = o["text"]
		enabled = o["enabled"]
		verify = o["verify"]

	func text() -> String:
		var t: String = "%d  %s" % [n, TranslationServer.translate(label)]
		return t + ("  " + TranslationServer.translate("comms.verify")) if verify else t

	func command(card: int, _buy: bool = true) -> Dictionary:
		return {"kind": "comms_reply", "card": card, "option": id}


## A good for sale (and perhaps bought back), or a repair.
class Buy:
	extends Row
	var item: String
	var price: int
	var sell: int
	var stock: int

	func _init(o: Dictionary) -> void:
		kind = "buy"
		item = str(o["item"])
		price = int(o["price"])
		sell = int(o["sell"])
		stock = int(o["stock"])

	func text() -> String:
		var t: String = (
			TranslationServer.translate("comms.buy_line") % [CommsData.item_text(item), price]
		)
		if sell > 0:
			t += "  " + TranslationServer.translate("comms.sell_at") % sell
		if stock >= 0:
			t += "  " + TranslationServer.translate("comms.stock") % stock
		var step: int = CommsData.step_of(item)
		if step > 1:
			t += "  " + TranslationServer.translate("comms.per_press") % step
		return t

	func command(card: int, buy: bool = true) -> Dictionary:
		return {
			"kind": "comms_trade",
			"card": card,
			"item": item,
			"qty": CommsData.step_of(item) if not item.begins_with("repair:") else 1,
			"buy": buy,
		}

	func can_buy() -> bool:
		return true

	func can_sell() -> bool:
		return sell > 0


## A module for sale in `slot`, swapping out the `old` one for its trade-in.
class Module:
	extends Row
	var module: String
	var label: String
	var slot: int
	var price: int
	var old: String
	var trade_in: int

	func _init(m: Dictionary) -> void:
		kind = "module"
		module = str(m["module"])
		label = str(m["name"])
		slot = int(m["slot"])
		price = int(m["price"])
		old = str(m["old"])
		trade_in = int(m["trade_in"])

	func text() -> String:
		var t: String = (
			TranslationServer.translate("comms.module_line")
			% [TranslationServer.translate(label), slot + 1, price]
		)
		if old != "":
			t += (
				"  "
				+ (
					TranslationServer.translate("comms.module_swap")
					% [CommsData.module_text(old), trade_in, price - trade_in]
				)
			)
		return t

	func command(card: int, _buy: bool = true) -> Dictionary:
		return {"kind": "comms_buy_module", "card": card, "module_key": module, "slot": slot}

	func can_buy() -> bool:
		return true


## A fitted module the market buys back, for `pay`.
class SellModule:
	extends Row
	var slot: int
	var module: String
	var pay: int

	func _init(f: Dictionary, paid: int) -> void:
		kind = "sell_module"
		slot = int(f["slot"])
		module = str(f["module"])
		pay = paid

	func text() -> String:
		var t: String = (
			TranslationServer.translate("comms.sell_module") % [CommsData.module_text(module), slot + 1]
		)
		if pay > 0:
			t += "  " + TranslationServer.translate("comms.sells_for") % pay
		return t

	func command(card: int, _buy: bool = true) -> Dictionary:
		return {"kind": "comms_sell_module", "card": card, "slot": slot}

	func can_sell() -> bool:
		return true
