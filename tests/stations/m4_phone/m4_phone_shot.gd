## The M4 shot (tests/visual/m4_shot.gd) with what the phone checks of #28's follow-up need:
## `lang` (the language, I18n.LANGUAGES), `ships` (the fleet's size, up to 6), the views
## "outcome" and "debrief" (Helm with the outcome card of a won run, on its Outcome or
## Debrief tab), "pause" (the host's own ship paused, with a host pause) and "menu_web"
## (the web main menu), and the simulated insets drawn in translucent red as
## station_shot.gd does; `fullscreen` forces the Full screen button.
extends "res://tests/visual/m4_shot.gd"

const StationShot: GDScript = preload("res://tests/visual/station_shot.gd")
const NAMES: Array = [StationFixture.SHIP_NAME, "Heron", "Osprey", "Merlin", "Swift", "Ibis"]

var lang: String = "en"
var ships: int = 4
## FullscreenButton.forced for the shot (1 shown, 0 hidden).
var fullscreen: int = 0


func _ready() -> void:
	FullscreenButton.forced = fullscreen
	match view:
		"outcome", "debrief", "pause", "menu_web":
			LayoutMode.forced = -1
			SafeArea.simulate(insets)
			I18n.apply(lang)
			LayoutMode.apply(get_tree().root)
			set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_ctx = StationFixture.context("helm", "user://l5_m4_phone_shot.cfg")
			CommsFixture.install(_ctx)
			_own_view()
		_:
			super()
	if not insets.is_empty():
		var shade: Control = StationShot.InsetShade.new()
		shade.set("insets", insets)
		add_child(shade)


func _own_view() -> void:
	match view:
		"menu_web":
			var m: MainMenu = MainMenu.new()
			m.web = true
			m.settings = ClientSettings.new("user://l5_m4_phone_menu.cfg")
			m.settings.player_name = "Ana"
			m.token_path = "user://l5_menu_none.token"
			m.pid_path = "user://l5_menu_none.pid"
			add_child(m)
		"pause":
			_ctx.crew.host = true
			_event("pause", {"host": true})
			_event("pause", {"ship": 0, "uncovered": ["science", "comms"]})
			_event("abandon_votes", {"ship": 0, "voters": ["Bo"], "sessions": [9], "needed": 2})
			_station()
			var o: PauseOverlay = PauseOverlay.new()
			_centred(o)
			o.setup(_ctx)
		_:
			_ctx.crew.host = true
			_station()
			var card: OutcomeCard = OutcomeCard.new()
			_centred(card)
			card.setup(_ctx)
			_event("run_over", {"ship": 0, "outcome": "win", "time_s": 412.0, "hull": 0.58})
			_event("run_votes", {"ship": 0, "voters": ["Bo"], "needed": 2})
			_event("debrief", debrief_record())
			if view == "debrief":
				card.pages.select(1)


## Four ships' worth of fleet, or `ships` of NAMES (teams alternate).
func _fleet(mode: String, started: bool) -> void:
	I18n.apply(lang)
	var names: Array = NAMES.slice(0, clampi(ships, 1, NAMES.size()))
	var teams: Array = []
	for i: int in names.size():
		teams.append([0, 1, 0, 1, 0, 1][i])
	StationFixture.fleet(_ctx, mode, names, teams, started)


## A debrief long enough to scroll.
static func debrief_record() -> Dictionary:
	var decisions: Array = []
	for i: int in 8:
		(
			decisions
			. append(
				{
					"tick": 1800 * (i + 1),
					"kind": "RAIDER_WAVE",
					"reason_key": "director.reason.raider_wave",
					"reason_args": {"wave": i + 1, "count": 2},
				}
			)
		)
	return {
		"ship": 0,
		"result": "win",
		"run_s": 412.0,
		"encounters":
		[
			{"scenario": "enemy_wave", "s": 140.0, "result": "won"},
			{"scenario": "rescue", "s": 300.0, "fled": true},
			{"scenario": "debris_leg", "s": 410.0, "result": "won"},
		],
		"losses": 0,
		"fled": 1,
		"decisions": decisions,
		"first_use": {"helm": {"face": 12.0, "jump": -1.0}, "weapons": {"fire": 31.0}},
		"coop": [{"stations": ["helm", "weapons"], "events": 4}],
	}


func _exit_tree() -> void:
	super()
	FullscreenButton.forced = -1
