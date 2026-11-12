class_name CalloutCard
extends VBoxContainer
## The callout card in the game (D369, FT-STN-012): docs/callout-card.md, the crew's spoken
## words, as a view of the Controls page (ControlsPane.VIEW_CARD) in the game's style and
## language, so a LAN game needs no web link. Its text is the `card.*` strings of
## content/i18n/strings.json, with the stations named by their `station.*` strings;
## tests/presentation/test_callout_card.gd keeps the English equal to the document. Laid out
## like ControlsList: dim section headings, two-column rows with the words in the accent
## colour.

## The card in order. A part is [kind, keys...]: "p" a paragraph, "h" a heading, "row" a word
## and its meaning, "say" a station and its words, "pair" two stations and their words, "habit"
## a habit.
const PARTS: Array[Array] = [
	["p", "card.say"],
	["example", "card.example"],
	["p", "card.verbal"],
	["h", "card.names"],
	["row", "card.name_1.word", "card.name_1.means"],
	["row", "card.name_2.word", "card.name_2.means"],
	["row", "card.name_3.word", "card.name_3.means"],
	["row", "card.name_4.word", "card.name_4.means"],
	["row", "card.name_5.word", "card.name_5.means"],
	["row", "card.name_6.word", "card.name_6.means"],
	["p", "card.names_tip"],
	["h", "card.stations"],
	["row", "station.helm", "card.say_helm"],
	["row", "station.weapons", "card.say_weapons"],
	["row", "card.shields", "card.say_shields"],
	["row", "station.science", "card.say_science"],
	["row", "station.relay", "card.say_relay"],
	["row", "station.engineering", "card.say_engineering"],
	["row", "station.comms", "card.say_comms"],
	["row", "seat.captain", "card.say_captain"],
	["h", "card.pairs"],
	["p", "card.pairs_tip"],
	["pair", "engineering", "helm", "card.pair_1"],
	["pair", "helm", "weapons", "card.pair_2"],
	["pair", "helm", "science", "card.pair_3"],
	["pair", "helm", "relay", "card.pair_4"],
	["pair", "helm", "comms", "card.pair_5"],
	["pair", "weapons", "science", "card.pair_6"],
	["pair", "weapons", "relay", "card.pair_7"],
	["pair", "weapons", "comms", "card.pair_8"],
	["pair", "engineering", "science", "card.pair_9"],
	["pair", "engineering", "relay", "card.pair_10"],
	["pair", "engineering", "comms", "card.pair_11"],
	["pair", "science", "relay", "card.pair_12"],
	["pair", "science", "comms", "card.pair_13"],
	["pair", "relay", "comms", "card.pair_14"],
	["h", "card.habits"],
	["habit", "card.habit_1"],
	["habit", "card.habit_2"],
	["habit", "card.habit_3"],
	["habit", "card.habit_4"],
]

## Every text shown, in order (a row is its word, then its meaning), for tests.
var texts: PackedStringArray = PackedStringArray()
## The parts live in here: a notification may not change the children of its own node.
var _body: VBoxContainer = VBoxContainer.new()


func _init() -> void:
	_body.add_theme_constant_override("separation", 6)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_body)
	_build()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_build()


func _build() -> void:
	texts.clear()
	for c: Node in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var grid: GridContainer = null
	for part: Array in PARTS:
		var kind: String = part[0]
		if kind not in ["row", "pair"]:
			grid = null
		match kind:
			"h":
				_body.add_child(_text(tr(part[1]), "text_dim"))
			"p", "example":
				_body.add_child(_text(tr(part[1]), "accent" if kind == "example" else "text"))
			"habit":
				_body.add_child(_text("• " + tr(part[1]), "text"))
			_:
				if grid == null:
					grid = GridContainer.new()
					grid.columns = 2
					grid.add_theme_constant_override("h_separation", 24)
					ListLines.attach(grid)
					_body.add_child(grid)
				var who: String = tr(part[1])
				if kind == "pair":
					who = tr("card.pair") % [tr("station." + part[1]), tr("station." + part[2])]
				grid.add_child(_text(who, "accent"))
				grid.add_child(_text(tr(part[-1]), "text"))


## A label in palette role `role` that wraps in its column instead of widening the page, its
## text recorded in `texts`.
func _text(text: String, role: String) -> Label:
	texts.append(text)
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Palette.color(role))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l
