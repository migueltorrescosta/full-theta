class_name IntentEvent
extends RefCounted
## One intent event: what InputMatcher makes of a key, button, stick or touch control, and
## what StationScreen.dispatch and StationPanel.handle_intent take. It stays inside the
## client (never sent over the net). The defaults are what a hand-built event means: a
## press on the keyboard and mouse.

## The IntentTable row id.
var id: String = ""
## IntentTable.row(id)["group"]; "" when the event is built by hand.
var group: String = ""
## Who handles it (IntentTable.target): a station, "screen" or "captain"; "" when the event
## is built by hand and goes straight to a panel.
var target: String = ""
## IntentTable.PRESS, HOLD or AXIS of the row; "" when the event is built by hand.
var kind: String = ""
## Press: true. Hold: the new held state, toggle-aware.
var pressed: bool = true
## 1.0 or 0.0.
var value: float = 1.0
## IntentTable.KBM, PAD or TOUCH.
var device: String = IntentTable.KBM


## An event for `id` (the usual hand-built one: tests, touch buttons, the partner glance).
static func of(
	p_id: String, p_pressed: bool = true, p_device: String = IntentTable.KBM, p_target: String = ""
) -> IntentEvent:
	var e: IntentEvent = IntentEvent.new()
	e.id = p_id
	e.pressed = p_pressed
	e.value = 1.0 if p_pressed else 0.0
	e.device = p_device
	e.target = p_target
	return e


## The event the matcher makes for `id` on `device`: group and kind from the IntentTable row,
## target from the focused station among `stations`.
static func routed(
	p_id: String, p_device: String, p_pressed: bool, focused: String, stations: Array
) -> IntentEvent:
	var r: Dictionary = IntentTable.row(p_id)
	var e: IntentEvent = of(
		p_id, p_pressed, p_device, IntentTable.target(p_id, p_device, focused, stations)
	)
	e.group = r["group"]
	e.kind = r["kind"]
	return e
