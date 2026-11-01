extends GdUnitTestSuite
## Weapons' reachability on a phone (#28 follow-up, D287, design 2.2): from the resting
## state (the Fire page, no sheet open, U3 selected) the test taps every tap target, and after
## a tap that changes the page or opens a sheet every target of that state, and records what
## each tap sent. Every action of the design's table must be reached within its taps (combat
## actions at 1, everything within 2), on its side and upright.
# FT: FT-STN-005

const SETTINGS: String = "user://test_weapons_reach.cfg"
const LANDSCAPE: Array = [47, 0, 47, 21]
const PORTRAIT: Array = [0, 47, 0, 34]
## The design's table (2.2, with 2.0's common actions): [action, what one tap sends (all of
## it), where, taps]. "intent:x" is a touch control's intent (the key's), "select" a changed
## selection, "menu" the menu opening, the rest the client's sends.
const TABLE: Array = [
	["Fire (hold)", ["intent:fire"], "Fire page, FIRE (persistent)", 1],
	["Fire all (hold)", ["intent:fire_all"], "Fire page", 1],
	["Next mount", ["intent:mount_next"], "Fire page, mount card", 1],
	["Cycle ammo", ["intent:ammo_next", "command:set_ammo_type"], "Fire page", 1],
	["Fire guided", ["intent:fire_guided"], "Fire page", 1],
	["Claim / release", ["intent:claim", "release_claim"], "Fire page", 1],
	["Direct mount", ["intent:mount_1"], "Mounts page, row", 2],
	["Claim from the mount list", ["intent:mount_1", "release_claim"], "Mounts page, Claim", 2],
	["Power request", ["send_chip:power"], "Crew page", 2],
	["Bring to bear request", ["send_chip:bring_to_bear"], "Crew page", 2],
	["Ping", ["ping"], "Crew page or selection sheet", 2],
	["Mark at the selection", ["place_mark"], "Crew page or selection sheet", 2],
	["Cycle target", ["select"], "selection chip ‹ ›", 1],
	["Alert level", ["set_alert"], "alert chip, sheet", 2],
	["Menu (Controls, Settings, Leave)", ["menu"], "☰", 1],
]

var _vp: SubViewport
var _heard: Array[String] = []
var _menu: bool = false


func before() -> void:
	I18n.apply("en")


func after_test() -> void:
	SafeArea.simulate([])
	RotateBanner.dismissed_here = false
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))


func _screen(size: Vector2i, insets: Array) -> StationScreen:
	SafeArea.simulate(insets)
	_vp = auto_free(SubViewport.new())
	_vp.size = size
	add_child(_vp)
	var ctx: StationContext = StationFixture.context("weapons", SETTINGS)
	ctx.crew.claims["mount:0"] = {"session": StationFixture.SESSION, "name": "Ana"}
	var s: StationScreen = auto_free(StationScreen.new())
	s.setup(ctx)
	_vp.add_child(s)
	var p: WeaponsPanel = s.panels[0] as WeaponsPanel
	p.set_process(false)
	p.touch_intent.connect(func(id: String) -> void: _heard.append(id))
	s.menu_requested.connect(func() -> void: _menu = true)
	await _rest(s)
	return s


func _frames(n: int) -> void:
	for i: int in n:
		await get_tree().process_frame


## The resting state: no sheet, the first page, U3 selected.
func _rest(s: StationScreen) -> void:
	if s.sheet.is_open():
		s.sheet.cancel()
	s.ctx.crew.select("contact", StationFixture.U3)
	s.focused_panel().pages.current = 0
	(s.focused_panel() as WeaponsPanel).step(0.016)
	await _frames(2)


## A page's parts built and laid out (the mount rows, the Crew page's buttons).
func _settle(s: StationScreen) -> void:
	(s.focused_panel() as WeaponsPanel).step(0.016)
	await _frames(2)


## The centres of every tap target on the screen now.
func _targets(s: StationScreen) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for t: Dictionary in TapAudit.targets(s):
		out.append((t["rect"] as Rect2).get_center())
	return out


func _tap(at: Vector2) -> void:
	for down: bool in [true, false]:
		var t: InputEventScreenTouch = InputEventScreenTouch.new()
		t.position = at
		t.pressed = down
		_vp.push_input(t, true)


## Taps `at` and returns what the tap sent.
func _observe(s: StationScreen, at: Vector2) -> Array[String]:
	var sent: Array = StationFixture.sent(s.ctx).sent
	var from: int = sent.size()
	var sel: Dictionary = s.ctx.crew.selection.duplicate()
	_heard.clear()
	_menu = false
	_tap(at)
	await _frames(1)
	var out: Array[String] = []
	for id: String in _heard:
		out.append("intent:" + id)
	for e: Array in sent.slice(from):
		match str(e[0]):
			"command":
				out.append("command:" + str(e[1][0]["kind"]))
			"send_chip":
				out.append("send_chip:" + str(e[1][0]))
			_:
				out.append(str(e[0]))
	if s.ctx.crew.selection != sel:
		out.append("select")
	if _menu:
		out.append("menu")
	return out


## Every tap sequence of one or two taps from rest (the second only after a tap that changed
## the page or opened a sheet): [[what it sent], taps, page title], one per tap.
func _walk(s: StationScreen) -> Array:
	var pages: PageHost = s.focused_panel().pages
	var seen: Array = []
	var first: Array[Vector2] = _targets(s)
	for a: Vector2 in first:
		await _rest(s)
		var got: Array[String] = await _observe(s, a)
		seen.append([got, 1, pages.title(pages.current)])
		if pages.current == 0 and not s.sheet.is_open():
			continue
		await _settle(s)
		var second: Array[Vector2] = _targets(s)
		for b: Vector2 in second:
			await _rest(s)
			await _observe(s, a)
			await _settle(s)
			var page: String = pages.title(pages.current)
			seen.append([await _observe(s, b), 2, page])
	await _rest(s)
	return seen


## The fewest taps of a sequence whose one tap sent all of `keys`, or 99.
static func _taps(seen: Array, keys: Array) -> int:
	var best: int = 99
	for e: Array in seen:
		var got: Array = e[0]
		if keys.all(func(k: String) -> bool: return k in got):
			best = mini(best, int(e[1]))
	return best


# FT: FT-STN-005, FT-STN-009, FT-STN-010, FT-WPN-003, FT-WPN-004, FT-WPN-006, FT-WPN-008
# Every action of Weapons' table within its taps from rest, on its side and upright:
# combat actions at 1 tap on the Fire page, the rest within 2 (D287).
func test_every_action_within_two_taps() -> void:
	for c: Array in [[Vector2i(844, 390), LANDSCAPE], [Vector2i(390, 844), PORTRAIT]]:
		var s: StationScreen = await _screen(c[0], c[1])
		# The banner sits over the view-top row upright (a Request to the frame); dismissed.
		s.rotate_banner.dismiss()
		var seen: Array = await _walk(s)
		for row: Array in TABLE:
			var taps: int = _taps(seen, row[1])
			(
				assert_int(taps)
				. override_failure_message(
					(
						"%s %s: %s needs %d taps, the table says %d"
						% [c[0], row[0], row[1], taps, row[3]]
					)
				)
				. is_less_equal(int(row[3]))
			)
