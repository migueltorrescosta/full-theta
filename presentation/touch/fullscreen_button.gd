class_name FullscreenButton
extends RailButton
## "Full screen" (#28): on Android and iPad browsers it asks for fullscreen and, where the
## browser allows (Android), locks landscape. Never shown on an iPhone, whose Safari can't,
## nor off the web or once fullscreen. A browser only allows fullscreen inside the tap's
## own handler, which Godot's events arrive after, so the page acts on the tap itself:
## this button registers its rectangle with the shell (TouchPage.set_action), the way
## WebTextField does for text fields.

const TEXT_KEY: String = "touch.fullscreen"
const TEXT: String = "Full screen"
## How often it asks the page whether fullscreen is still offered, in frames.
const POLL_FRAMES: int = 30

## Tests and L5 shots: 1 shows the button, 0 hides it, -1 asks the page.
static var forced: int = -1

var _id: String = ""
var _sent: Rect2 = Rect2()
var _offered: bool = false
var _frames: int = 0


func _init() -> void:
	super()
	text = TouchText.of(TEXT_KEY, TEXT)
	_id = "fs%d" % get_instance_id()
	visible = false


func _ready() -> void:
	_refresh()


## Whether the button is offered here.
static func offered() -> bool:
	if forced >= 0:
		return forced == 1
	return TouchPage.fullscreen_offered()


func _process(_delta: float) -> void:
	_frames += 1
	if _frames >= POLL_FRAMES:
		_frames = 0
		_refresh()
	if not is_visible_in_tree():
		_clear()
		return
	var xf: Transform2D = get_viewport().get_screen_transform() * get_global_transform_with_canvas()
	var r: Rect2 = xf * Rect2(Vector2.ZERO, size)
	if r != _sent:
		_sent = r
		TouchPage.set_action(_id, r, "fullscreen")


func _refresh() -> void:
	_offered = offered()
	visible = _offered


func _exit_tree() -> void:
	super()
	_clear()


func _clear() -> void:
	if _sent != Rect2():
		TouchPage.clear_action(_id)
		_sent = Rect2()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		text = TouchText.of(TEXT_KEY, TEXT)
