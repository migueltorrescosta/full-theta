class_name BindingText
extends RefCounted
## Human text of a binding for the overlay, tooltips and Settings: "Alt+A", "hold RB",
## "Shift+Middle click", "View+X", "B, 2", "S / W", "Mouse". Keys of mouse buttons and
## gestures go through I18n ("input.<name>"); key and pad button names show as written.
## An axis's "-" (inverted) isn't shown: the overlay names the input, not its sign.

## Binding tokens with a translated word: token -> "input.<name>".
const WORDS: Dictionary = {
	"LMB": "input.lmb",
	"RMB": "input.rmb",
	"MMB": "input.mmb",
	"WheelUp": "input.wheel_up",
	"WheelDown": "input.wheel_down",
	"MouseX": "input.mouse",
	"MouseY": "input.mouse",
	"LS": "input.ls",
	"RS": "input.rs",
	"LS_X": "input.ls_x",
	"LS_Y": "input.ls_y",
	"RS_X": "input.rs_x",
	"RS_Y": "input.rs_y",
}


static func describe(binding: String) -> String:
	var b: String = binding.strip_edges()
	if b.begins_with("long "):
		return _tr("input.hold") % describe(b.substr(5))
	if "," in b and b.length() > 1:
		return ", ".join(Array(b.split(",")).map(func(s: String) -> String: return describe(s)))
	var parts: PackedStringArray = b.split("+")
	var out: PackedStringArray = []
	for p: String in parts:
		out.append(" / ".join(Array(p.split("/")).map(_word)))
	return "+".join(out)


## The subtitle text with each `{binding:<intent>}` marker (DialogueLines.fill) replaced by
## the player's current binding of that intent on `device` ("Alt+A", "hold RB"); "-" for an
## intent with no binding there. A rebind shows at once because bindings are read here.
static func fill_markers(text: String, bindings: Bindings, device: String) -> String:
	if not "{binding:" in text:
		return text
	var re: RegEx = RegEx.create_from_string("\\{binding:([a-z][a-z0-9_]*)\\}")
	var out: String = ""
	var at: int = 0
	for m: RegExMatch in re.search_all(text):
		out += text.substr(at, m.get_start() - at)
		var list: PackedStringArray = bindings.bindings(m.get_string(1), device)
		out += describe_all(list) if not list.is_empty() else "-"
		at = m.get_end()
	return out + text.substr(at)


## Every binding of `id` on `device`, joined: "T / RB".
static func describe_all(list: PackedStringArray) -> String:
	return " / ".join(Array(list).map(func(b: String) -> String: return describe(b)))


static func _word(token: String) -> String:
	var t: String = token.strip_edges().trim_prefix("-")
	return _tr(WORDS[t]) if WORDS.has(t) else t


static func _tr(key: String) -> String:
	return str(TranslationServer.translate(key))
