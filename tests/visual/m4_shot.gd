## Multi-ship and PvP screens for the L5 harness (#11): builds tests/stations/station_fixture.gd's
## context with a fleet of four ships and shows one `view`, set from shots.json:
## - "lobby": the multi-ship lobby in TEAMS (the host's, several ships and teams);
## - "mode": the same lobby with the host's Mode dialog open;
## - "scoreboard": the scoreboard of a last-ship-standing session, the player's ship out;
## - "relaunch": the holdout scoreboard with the relaunch prompt;
## - "handover": the viewer of a friendly ship with the handover notice;
## - "forfeit": Helm in a race with a crewmate's give-up vote;
## - "takeover": Helm of Osprey over its ally Kestrel's pause, offering Kestrel's stations.
## - "outcome", "debrief": Helm with the outcome card of a won run, on its Outcome or Debrief
##   tab (a phone's two tabs, #28);
## - "pause": the host's own ship paused under a host pause;
## - "menu_web": the web main menu.
## `insets` simulates a phone's safe-area insets [left, top, right, bottom] in device-
## independent px (#28), drawn in translucent red; `lang` the language (I18n.LANGUAGES),
## `ships` the fleet's size (up to 6), `fullscreen` FullscreenButton.forced (-1 as found).
extends Control

const StationShot: GDScript = preload("res://tests/visual/station_shot.gd")
const NAMES: Array = [StationFixture.SHIP_NAME, "Heron", "Osprey", "Merlin", "Swift", "Ibis"]

var view: String = "lobby"
var insets: Array = []
var lang: String = "en"
var ships: int = 4
var fullscreen: int = -1

var _ctx: StationContext


func _ready() -> void:
	FullscreenButton.forced = fullscreen
	LayoutMode.forced = -1
	SafeArea.simulate(insets)
	I18n.apply(lang)
	LayoutMode.apply(get_tree().root)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var entry: String = {"handover": "viewer", "lobby": "systems", "mode": "systems"}.get(
		view, "helm"
	)
	_ctx = StationFixture.context(entry, "user://l5_m4_shot.cfg")
	CommsFixture.install(_ctx)
	match view:
		"lobby", "mode":
			_lobby()
		"scoreboard", "relaunch":
			_scoreboard()
		"handover":
			_fleet("teams", true)
			_event("picked", {"ship": 1, "entry": "viewer"})
			_event("eliminated", FleetMessages.eliminated(0, "destroyed", 0))
			_event("handover", FleetMessages.handover(0, 1))
			_station()
			var n: HandoverNotice = HandoverNotice.new()
			n.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
			n.grow_horizontal = Control.GROW_DIRECTION_BOTH
			n.position.y += 64
			add_child(n)
			n.setup(_ctx)
		"forfeit":
			_fleet("race", true)
			_event("abandon_votes", {"ship": 0, "voters": ["Bo"], "sessions": [9], "needed": 2})
			_station()
			var p: VotePrompt = VotePrompt.new()
			add_child(p)
			p.setup(_ctx, VotePrompt.Kind.FORFEIT)
		"takeover":
			_fleet("teams", true)
			_event("picked", {"ship": 2, "entry": "helm"})
			_event("pause", {"ship": 0, "uncovered": ["science", "comms"]})
			_station()
			var o: PauseOverlay = PauseOverlay.new()
			_centred(o)
			o.setup(_ctx)
		"outcome", "debrief", "pause", "menu_web":
			_own_view()
	if not insets.is_empty():
		var shade: Control = StationShot.InsetShade.new()
		shade.set("insets", insets)
		add_child(shade)


func _exit_tree() -> void:
	LayoutMode.forced = -1
	SafeArea.simulate([])
	FullscreenButton.forced = -1


## `ships` of NAMES, teams alternating: Kestrel and Osprey on team A, Heron and Merlin on B.
func _fleet(mode: String, started: bool) -> void:
	var names: Array = NAMES.slice(0, clampi(ships, 1, NAMES.size()))
	var teams: Array = []
	for i: int in names.size():
		teams.append(i % 2)
	StationFixture.fleet(_ctx, mode, names, teams, started)


func _event(type: String, p: Dictionary) -> void:
	_ctx.crew.handle_event({"type": type, "payload": p}, StationFixture.NOW_MS)


func _lobby() -> void:
	_ctx.crew.host = true
	_ctx.crew.lobby[0]["started"] = false
	_ctx.crew.lobby[0]["ready"] = false
	_ctx.crew.lobby[0]["crew"] = 2
	_ctx.crew.lobby[0]["uncovered"] = ["relay", "comms"]
	_ctx.crew.lobby[0]["seats"] = [
		{"entry": "helm", "name": "Ana"},
		{"entry": "weapons", "name": "Bo"},
		{"entry": "systems", "name": "Cy"},
	]
	_fleet("teams", false)
	var l: LobbyScreen = LobbyScreen.new()
	l.setup(_ctx)
	add_child(l)
	if view == "mode":
		l.find_child("ModeButton", true, false).pressed.emit()


func _scoreboard() -> void:
	var holdout: bool = view == "relaunch"
	_fleet("holdout" if holdout else "last_standing", true)
	_event("eliminated", FleetMessages.eliminated(0, "destroyed", 2 if holdout else 0))
	_event("handover", FleetMessages.handover(0, FleetMessages.TO_SCOREBOARD))
	var rows: Array = [
		FleetMessages.scoreboard_row(0, StationFixture.SHIP_NAME, 0, "destroyed", 2, 312.0, 1),
		FleetMessages.scoreboard_row(1, "Heron", 1, "in_play", 4, 540.0, 3),
		FleetMessages.scoreboard_row(2, "Osprey", 0, "in_play", 3, 540.0, 0),
		FleetMessages.scoreboard_row(3, "Merlin", 1, "destroyed", 1, 201.0, 0),
	]
	_event("scoreboard", FleetMessages.scoreboard(rows))
	var s: ScoreboardScreen = ScoreboardScreen.new()
	s.setup(_ctx)
	add_child(s)
	if holdout:
		_event("relaunch_votes", FleetMessages.relaunch_votes(0, ["Bo"], 2))
		var p: VotePrompt = VotePrompt.new()
		add_child(p)
		p.setup(_ctx, VotePrompt.Kind.RELAUNCH)


## The station screen of the pick, as the client shell shows it.
func _station() -> void:
	var s: StationScreen = StationScreen.new()
	s.setup(_ctx)
	add_child(s)


func _centred(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(c)


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
