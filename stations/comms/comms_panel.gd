class_name CommsPanel
extends PlaceholderPanel
## Comms until #10 (D190): the placeholder's name and read-out, and under them the fixture
## mission and contract cards (`FixtureCards`, content/fixtures/comms_cards.json) that are the
## Comms half of Approach, Parley, Quartermaster, Intel and Ops. The cards are a list to read:
## nothing here sends a command, and hold fire (FT-PAIR-017) stays inert.

var cards: FixtureCards


func _setup() -> void:
	super._setup()
	cards = FixtureCards.new()
	cards.setup()
	(get_child(0) as Control).add_child(cards)
