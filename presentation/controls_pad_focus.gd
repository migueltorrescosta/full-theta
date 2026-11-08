class_name PadFocus
extends Node
## Gamepad navigation for the menu, the lobby and the Training picker (D4, R25-5): Godot's
## d-pad moves focus between controls only once one has focus, and nothing in those screens
## grabs it. PadFocus, a child of a screen, gives the first focusable control focus on the
## first pad button or stick push while the screen shows and nothing in it has focus; that
## input is used up, so the first press only shows where the focus is. In a session the
## stations read the pad through InputMatcher and need none of this.
##
##     PadFocus.attach(self)

## Stick push (0..1) that counts as the pad being used.
const PUSH: float = 0.5

## The screen whose controls take the focus.
var root: Control


## Adds a PadFocus for `screen`.
static func attach(screen: Control) -> PadFocus:
	var f: PadFocus = PadFocus.new()
	f.name = "PadFocus"
	f.root = screen
	screen.add_child(f)
	return f


## The first visible, enabled control under `node` that takes focus, in tree order; null if none.
static func first_focusable(node: Node) -> Control:
	var c: Control = node as Control
	if c != null:
		if not c.visible:
			return null
		if (
			c.focus_mode == Control.FOCUS_ALL
			and not (c is BaseButton and (c as BaseButton).disabled)
		):
			return c
	for child: Node in node.get_children():
		var found: Control = first_focusable(child)
		if found != null:
			return found
	return null


## True for a pad button press or a stick or trigger pushed past PUSH.
static func is_pad_input(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	return (
		event is InputEventJoypadMotion
		and absf((event as InputEventJoypadMotion).axis_value) >= PUSH
	)


## Gives the first control focus if the screen shows and none of its controls has it.
## Returns true when it did.
func grab() -> bool:
	if root == null or not root.is_visible_in_tree():
		return false
	var owner: Control = root.get_viewport().gui_get_focus_owner()
	if owner != null and root.is_ancestor_of(owner) and owner.is_visible_in_tree():
		return false
	var first: Control = first_focusable(root)
	if first == null:
		return false
	first.grab_focus()
	return true


func _input(event: InputEvent) -> void:
	if is_pad_input(event) and grab():
		get_viewport().set_input_as_handled()
