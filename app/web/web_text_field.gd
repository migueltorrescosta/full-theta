class_name WebTextField
extends Node
## Backs a LineEdit with an HTML `<input>` in browser builds (D196): Godot's own text
## field raises no on-screen keyboard in iPad Safari or Firefox, because the browser
## only shows one for an element focused inside a tap handler. The shell (window.ft in
## app/web/shell.html) keeps the field's rectangle, focuses an `<input>` laid over it
## from its own tap handler, and this node moves the rectangle and text across and takes
## the typed text back (`text_changed`, `text_submitted` as the LineEdit would emit them).
## Off the web `attach()` does nothing and the LineEdit works as it always did.

var edit: LineEdit
var field_id: String = ""
var _sent: String = ""
var _callback: JavaScriptObject


## Backs `line_edit` with an overlay input. Call once, after it is in the tree or before.
static func attach(line_edit: LineEdit) -> void:
	if not OS.has_feature("web"):
		return
	var f: WebTextField = WebTextField.new()
	f.edit = line_edit
	f.field_id = "tf%d" % line_edit.get_instance_id()
	# Godot's own keyboard would take the focus from the overlay input.
	line_edit.virtual_keyboard_enabled = false
	line_edit.add_child(f)


func _enter_tree() -> void:
	_callback = JavaScriptBridge.create_callback(_on_page_event)
	JavaScriptBridge.get_interface("ft").call("listen", field_id, _callback)


func _process(_delta: float) -> void:
	if not edit.is_visible_in_tree():
		_clear()
		return
	_register()


## What the page says happened to the field (`ft.listen`): the typed text, Enter.
func _on_page_event(args: Array) -> void:
	var parsed: Variant = JSON.parse_string(str(args[0]))
	if not parsed is Dictionary:
		return
	var d: Dictionary = parsed
	if d.has("text") and str(d["text"]) != edit.text:
		edit.text = str(d["text"])
		edit.caret_column = edit.text.length()
		edit.text_changed.emit(edit.text)
	if d.get("submitted", false):
		edit.text_submitted.emit(edit.text)
	_sent = ""


func _exit_tree() -> void:
	JavaScriptBridge.get_interface("ft").call("listen", field_id, null)
	_clear()


## The field's rectangle in canvas pixels, as the shell wants it.
func _rect() -> Rect2:
	var xf: Transform2D = (
		edit.get_viewport().get_screen_transform() * (edit.get_global_transform_with_canvas())
	)
	return xf * Rect2(Vector2.ZERO, edit.size)


func _register() -> void:
	var r: Rect2 = _rect()
	var sig: String = (
		"%d,%d,%d,%d|%s|%s"
		% [
			roundi(r.position.x),
			roundi(r.position.y),
			roundi(r.size.x),
			roundi(r.size.y),
			edit.text,
			edit.placeholder_text
		]
	)
	if sig == _sent:
		return
	_sent = sig
	var call: String = (
		"ft.setInput(%s,%d,%d,%d,%d,%s,%s,%d)"
		% [
			JSON.stringify(field_id),
			roundi(r.position.x),
			roundi(r.position.y),
			roundi(r.size.x),
			roundi(r.size.y),
			JSON.stringify(edit.text),
			JSON.stringify(edit.placeholder_text),
			edit.max_length,
		]
	)
	JavaScriptBridge.eval(call, true)


func _clear() -> void:
	if _sent != "":
		JavaScriptBridge.eval("ft.clearInput(%s)" % JSON.stringify(field_id), true)
		_sent = ""
