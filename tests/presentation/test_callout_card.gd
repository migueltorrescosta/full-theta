extends GdUnitTestSuite
## D369: the callout card is in the game, a view of the Controls page, in the game's language;
## docs/callout-card.md is its source, so the English card says what the document says.
# FT: FT-STN-012

const DOC: String = "res://docs/callout-card.md"


func before() -> void:
	I18n.apply("en")


func after() -> void:
	I18n.apply("en")


## The document's texts in order: paragraphs, headings, table cells and list items, without
## the title, comments, the print line and the table heads.
static func _doc_texts() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var lines: PackedStringArray = FileAccess.get_file_as_string(DOC).split("\n")
	for i: int in lines.size():
		var line: String = lines[i].strip_edges()
		if line == "" or line.begins_with("# ") or line.begins_with("<!--"):
			continue
		if line.begins_with("Print this page"):
			continue
		if line.begins_with("|"):
			var next: String = lines[i + 1] if i + 1 < lines.size() else ""
			if line.begins_with("|---") or next.begins_with("|---"):
				continue
			for cell: String in line.trim_prefix("|").trim_suffix("|").split("|"):
				out.append(_plain(cell))
			continue
		out.append(_plain(line.trim_prefix("## ").trim_prefix("> ").trim_prefix("- ")))
	return out


## Text without markup or quotes: the game quotes what the document sets as code.
static func _plain(text: String) -> String:
	for mark: String in ["**", "`", '"', "• "]:
		text = text.replace(mark, "")
	return text.strip_edges()


# FT: FT-STN-012
func test_the_english_card_says_what_the_document_says() -> void:
	var card: CalloutCard = auto_free(CalloutCard.new())
	var shown: PackedStringArray = PackedStringArray()
	for t: String in card.texts:
		shown.append(_plain(t))
	assert_array(Array(shown)).is_equal(Array(_doc_texts()))


# FT: FT-STN-012
# Translated: the Portuguese card names the stations and the callout words as the game does.
func test_the_card_follows_the_language() -> void:
	I18n.apply("pt_PT")
	var card: CalloutCard = auto_free(CalloutCard.new())
	assert_bool(card.texts.has("Leme")).is_true()
	assert_bool(card.texts.has("Engenharia e Leme")).is_true()
	var heights: String = ", ".join([tr("callout.level"), tr("callout.high"), tr("callout.low")])
	assert_bool(card.texts.has(heights)).is_true()
	I18n.apply("en")
	add_child(card)
	card.notification(NOTIFICATION_TRANSLATION_CHANGED)
	assert_bool(card.texts.has("Helm")).is_true()


# FT: FT-STN-012
# The Controls page shows it as a view, on a phone too, and has no web link any more.
func test_the_controls_page_shows_the_card_on_every_device() -> void:
	var pane: ControlsPane = auto_free(ControlsPane.new())
	add_child(pane)
	pane.build(Bindings.new(), ["helm"], IntentTable.KBM)
	var button: Button = pane._buttons.get_node(ControlsPane.VIEW_CARD)
	assert_str(button.text).is_equal("Callout card")
	assert_object(pane.card).is_null()
	button.pressed.emit()
	assert_str(pane.view).is_equal(ControlsPane.VIEW_CARD)
	assert_bool(pane.card.visible).is_true()
	assert_bool(pane.list.visible).is_false()
	assert_bool(button.button_pressed).is_true()
	pane.show_view(ControlsPane.VIEW_LIST)
	assert_bool(pane.card.visible).is_false()
	# A phone shows only the list, and the card.
	pane._phone = true
	pane.show_view(ControlsPane.VIEW_CARD)
	assert_bool(pane.card.visible).is_true()
	assert_bool(pane.touch.visible).is_false()
	pane.show_view(ControlsPane.VIEW_KBM)
	assert_str(pane.view).is_equal(ControlsPane.VIEW_LIST)
	assert_object(pane.get_node_or_null("CalloutCard")).is_null()
	assert_str(tr("controls.callout_card_url")).is_equal("controls.callout_card_url")
