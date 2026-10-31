class_name WeaponsTablet
extends Control
## Weapons on a tablet (#32, D3xx): a TabletDock of two opaque rails at the screen's
## edges, the whole tablet screen between them, and a WeaponsAimPad over the view, so a
## finger dragged across it still aims and a tap selects. Every control feeds the panel the
## intent its key or pad button feeds (FT-STN-005): the same calls the phone's rail makes.
##
## Left rail: Mount 1-4 (look through a mount, `mount_N`), the Aim stick at the lower corner
## (`aim_x`, `aim_y`). Right rail: Ammo (`ammo_next`), Guided (`fire_guided`), Fire all
## (held: `fire_all`), Claim or Release (the screen's `claim`), FIRE (held: `fire`) at the
## lower corner. Upright the rails are one bottom bar and the Mount and right-rail buttons
## sit in a grid. The panel keeps its own target line, mount line and the screen's radar.

## FIRE's least size in the bottom bar, px.
const FIRE_W: float = 200.0
const FIRE_H: float = 104.0

var portrait: bool = false
var dock: TabletDock
var touch: TouchIntents
var pad: WeaponsAimPad = WeaponsAimPad.new()
var aim: VirtualStick = VirtualStick.new()
var mount_buttons: Array[RailButton] = []
var ammo_button: RailButton
var guided_button: RailButton
var fire_all_button: RailButton
var claim_button: RailButton
var fire_button: RailButton

var _panel: WeaponsPanel


func _init(panel: WeaponsPanel, is_portrait: bool) -> void:
	_panel = panel
	portrait = is_portrait
	name = "WeaponsTablet"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.name = "AimPad"
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.dragged.connect(panel.touch_aim)
	pad.tapped.connect(func(p: Vector2) -> void: panel.touch_select(pad.get_global_transform() * p))
	add_child(pad)
	touch = TouchIntents.new(panel.ctx.matcher, func(_ev: Dictionary) -> void: pass)
	dock = TabletDock.new(portrait)
	_build_left()
	_build_right()


func _build_left() -> void:
	var mounts: Array[Control] = []
	for i: int in 4:
		var b: RailButton = _button(
			"Mount%d" % (i + 1), TouchText.of("touch.weapons.mount", "Mount %d") % (i + 1)
		)
		b.pressed.connect(_panel.touch_press.bind("mount_%d" % (i + 1)))
		mount_buttons.append(b)
		mounts.append(b)
	dock.left.add(_group(mounts))
	dock.left.add_spacer()
	aim.label = TouchText.of("touch.weapons.aim", "Aim")
	aim.name = "Aim"
	touch.stick(aim, "aim_x", "aim_y")
	dock.left.add(aim)
	TabletDock.corner_stick(aim, portrait, true)


func _build_right() -> void:
	ammo_button = _button("Ammo", "")
	ammo_button.pressed.connect(_panel.touch_press.bind("ammo_next"))
	guided_button = _button("Guided", TouchText.of("weapons.touch_guided", "Guided"))
	guided_button.pressed.connect(_panel.touch_press.bind("fire_guided"))
	fire_all_button = _button("FireAll", TouchText.of("weapons.touch_fire_all", "Fire all"))
	fire_all_button.hold = true
	fire_all_button.held.connect(_panel.touch_hold.bind("fire_all"))
	claim_button = _button("Claim", "")
	claim_button.pressed.connect(_panel.touch_claim)
	dock.right.add(_group([ammo_button, guided_button, fire_all_button, claim_button]))
	dock.right.add_spacer()
	fire_button = RailButton.make(
		TouchText.of("weapons.touch_fire", "FIRE"), RailButton.Role.DANGER
	)
	fire_button.name = "Fire"
	fire_button.hold = true
	fire_button.custom_minimum_size.y = FIRE_H
	fire_button.held.connect(_panel.touch_hold.bind("fire"))
	dock.right.add(fire_button)
	if portrait:
		fire_button.custom_minimum_size.x = FIRE_W
		fire_button.size_flags_horizontal = Control.SIZE_SHRINK_END


func _button(button_name: String, label: String) -> RailButton:
	var b: RailButton = RailButton.make(label)
	b.name = button_name
	b.resized.connect(RailButton.fit_text.bind(b))
	return b


## The buttons in a column (landscape) or a two-column grid (upright, where a rail is wide).
func _group(buttons: Array) -> Control:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2 if portrait else 1
	grid.add_theme_constant_override("h_separation", UiTheme.TOUCH_GAP)
	grid.add_theme_constant_override("v_separation", UiTheme.TOUCH_GAP)
	for b: Control in buttons:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
	return grid


## Texts and states from the panel, once a frame: the lit mount, the ammunition, Claim or
## Release, and no button for a mount the ship lacks.
func refresh() -> void:
	var p: WeaponsPanel = _panel
	for i: int in mount_buttons.size():
		var b: RailButton = mount_buttons[i]
		b.visible = i < p.mount_count()
		b.role = RailButton.Role.ACCENT if i == p.mount else RailButton.Role.PLAIN
	ammo_button.text = p.ammo_name() + " ▸"
	claim_button.text = (
		TouchText.of("weapons.touch_release", "Release")
		if p.is_mine(p.mount)
		else TouchText.of("weapons.touch_claim", "Claim")
	)
	claim_button.disabled = not p.is_usable(p.mount)
