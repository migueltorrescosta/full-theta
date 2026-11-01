class_name RelayTouchHelp
extends Control
## The touch picture of Relay's phone pages for the menu's Controls tab (#28 follow-up,
## P28-Help, D292), drawn like Science's (ScienceTouchHelp.draw_pages): the rails as
## RelayPhone lays them out on a phone on its side, every control numbered, then a legend.

const LEFT_X: float = 47.0
const RIGHT_X: float = 629.0
const RAIL_W: float = 168.0


## [{"title", "items": [[Rect2, name, what it does], ...]}] per page.
static func pages() -> Array:
	var left: Callable = func(row: int) -> Rect2:
		return Rect2(LEFT_X, 64.0 + 56.0 * row, RAIL_W, 48.0)
	var right: Callable = func(row: int) -> Rect2:
		return Rect2(RIGHT_X, 64.0 + 56.0 * row, RAIL_W, 48.0)
	var view: Rect2 = Rect2(223.0, 120.0, 398.0, 230.0)
	var gestures: String = TouchText.of(
		"help.relay_map", "Drag: mark, 2nd finger: depth, pinch, twist"
	)
	return [
		{
			"title": TouchText.of("page.map", "Map"),
			"items":
			[
				[
					left.call(0),
					_t("relay.launch"),
					TouchText.of("help.relay_launch", "Launch; hold to claim")
				],
				[left.call(1), _t("relay.hazard"), _t("intent.hazard_add")],
				[left.call(2), _t("intent.route"), _t("intent.route")],
				[left.call(3), _t("relay.lanes_off"), _t("intent.flag_lanes")],
				[right.call(0), _t("relay.accept"), _t("relay.inbox")],
				[right.call(1), _t("relay.decline"), _t("relay.inbox")],
				[right.call(2), TouchText.of("relay.send_to", "Send ▸"), _t("intent.mark_send")],
				[right.call(3), TouchText.of("relay.centre", "Centre"), _t("intent.map_centre")],
				[view, TouchText.of("page.map", "Map"), gestures],
			],
		},
		{
			"title": _t("relay.marks"),
			"items":
			[
				[Rect2(LEFT_X, 64.0, RAIL_W, 230.0), _t("relay.marks"), _t("intent.select")],
				[right.call(0), TouchText.of("relay.rename", "Rename"), _t("intent.mark_rename")],
				[right.call(1), TouchText.of("relay.delete", "Delete"), _t("intent.mark_delete")],
				[right.call(2), TouchText.of("relay.attach", "Attach"), _t("intent.mark_attach")],
			],
		},
		{
			"title": _t("relay.log"),
			"items":
			[
				[Rect2(LEFT_X, 64.0, 300.0, 280.0), _t("relay.log"), _t("relay.inbox")],
				[
					Rect2(RIGHT_X, 64.0, RAIL_W, 272.0),
					_t("view.forward") + " …",
					_t("intent.main_view_1")
				],
			],
		},
	]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w: float = ScienceTouchHelp.PHONE.x * ScienceTouchHelp.SCALE
	custom_minimum_size = Vector2(w, ScienceTouchHelp.height_for(pages()))


func _draw() -> void:
	ScienceTouchHelp.draw_pages(self, pages())


static func _t(key: String) -> String:
	return String(TranslationServer.translate(key))
