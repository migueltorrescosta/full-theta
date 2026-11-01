class_name TouchIntents
extends RefCounted
## Wires on-screen touch controls (presentation/touch/, #28) to intents, so a tap or a drag
## does exactly what the station's key or stick does (FT-STN-005, FT §5.1 touch). The
## controls name intents of IntentTable; InputMatcher.touch_press, touch_hold and
## touch_axis turn them into the same intent events and axis values, and `sink` dispatches
## the events (StationScreen.dispatch). Nothing here knows a station.
##
##     var touch := TouchIntents.new(ctx.matcher, screen.dispatch)
##     touch.button(RailButton.make("All stop"), "all_stop")      # press intent: a tap
##     touch.button(RailButton.make("Approach"), "approach")      # hold intent: held down
##     touch.stick(turn_stick, "helm_yaw", "helm_pitch")          # x and y axes
##     touch.axis("helm_surge", 0.4)                              # any computed value
##
## A panel polls its axes and holds as before (ctx.matcher.axis, is_held); release_all on
## the matcher (focus loss, the menu) lets go of them too.

var matcher: InputMatcher
## Called with each intent event (Dictionary) a control completes.
var sink: Callable


func _init(p_matcher: InputMatcher, p_sink: Callable) -> void:
	matcher = p_matcher
	sink = p_sink


## Makes `b` fire intent `id`: a tap for a press intent, held down for a hold intent (a
## RailButton becomes a `hold` button). Returns `b`.
func button(b: BaseButton, id: String) -> BaseButton:
	if IntentTable.row(id).get("kind", "") == IntentTable.HOLD and b is RailButton:
		(b as RailButton).hold = true
		(b as RailButton).held.connect(func(down: bool) -> void: hold(id, down))
	else:
		b.pressed.connect(func() -> void: press(id))
	return b


## Makes `s` drive the axis intents `x_id` and `y_id` ("" for none) with its x and y
## (+y down, as a pad stick), each times its sign. Returns `s`.
func stick(
	s: VirtualStick, x_id: String, y_id: String, x_sign: float = 1.0, y_sign: float = 1.0
) -> VirtualStick:
	s.moved.connect(
		func(v: Vector2) -> void:
			if x_id != "":
				axis(x_id, v.x * x_sign)
			if y_id != "":
				axis(y_id, v.y * y_sign)
	)
	return s


## Fires intent `id` once, as a tap.
func press(id: String) -> void:
	_send(matcher.touch_press(id))


## Holds or lets go of intent `id`.
func hold(id: String, down: bool) -> void:
	_send(matcher.touch_hold(id, down))


## Sets the touch value of the axis intent `id` (-1..1).
func axis(id: String, value: float) -> void:
	matcher.touch_axis(id, value)


func _send(events: Array[Dictionary]) -> void:
	for ev: Dictionary in events:
		sink.call(ev)
