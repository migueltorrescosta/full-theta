class_name SoundToggle
extends Button
## The sound on/off toggle in the top bar (D200, FT-AUD-017): mutes and unmutes the
## Master bus for the rest of the session. In a browser the first tap anywhere unlocks
## the audio context (the shell does it, app/web/shell.html); until then a sound that is
## switched on shows "Tap for sound", so a player who hears nothing sees why.

## How often the label looks at the browser's audio state (s).
const WEB_POLL_S: float = 0.5

var _since_poll: float = 0.0


func _init() -> void:
	toggle_mode = true
	flat = true
	focus_mode = Control.FOCUS_NONE
	button_pressed = not AudioServer.is_bus_mute(0)
	toggled.connect(_on_toggled)
	_refresh()


func _process(delta: float) -> void:
	if not OS.has_feature("web"):
		set_process(false)
		return
	_since_poll += delta
	if _since_poll >= WEB_POLL_S:
		_since_poll = 0.0
		_refresh()


## Whether sound is on (the Master bus isn't muted).
func is_on() -> bool:
	return not AudioServer.is_bus_mute(0)


func _on_toggled(on: bool) -> void:
	AudioServer.set_bus_mute(0, not on)
	_refresh()


func _refresh() -> void:
	var key: String = "topbar.sound_off"
	if button_pressed:
		key = "topbar.sound_on"
		if OS.has_feature("web") and _audio_state() == "suspended":
			key = "topbar.sound_tap"
	text = tr(key)


func _audio_state() -> String:
	return str(JavaScriptBridge.eval("window.ft ? window.ft.audioState() : ''", true))


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		_refresh()
