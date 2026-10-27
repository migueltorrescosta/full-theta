class_name WeaponsTouch
extends Control
## Weapons on a phone (#28, owner pick B, 2026-10-28): the turret view with touch controls
## feeding the panel the same intents as the keyboard and the pad (FT-STN-005).
##
## Landscape: docked rails (RailLayout), the view narrowed between them. The left rail
## holds the camera mount (tap: the next mount, `mount_next`), Claim or Release (the
## screen's `claim`), the ammunition (`ammo_next`) and the target line; the right rail a
## 160 px disc radar when Weapons is alone on the screen (FT-WPN-002), Guided
## (`fire_guided`) and a large FIRE at the thumb (held: `fire`). Upright, a reduced layout
## puts the same five buttons in two rows under the view; the screen keeps its own radar
## and shows the "turn sideways" banner. A finger dragged across the view aims, a tap
## selects (WeaponsAimPad).

## Rail width (px): 152 px buttons inside the rail's padding.
const RAIL_W: float = 168.0
## The rail radar's height (px).
const RADAR_H: float = 124.0
## The mount button shows two lines.
const MOUNT_H: float = 64.0
const FIRE_H: float = 100.0
const FONT_SMALL: int = 14
## How far (px) a tap on the rail radar reaches for a blip.
const RADAR_REACH: float = 24.0

## The LayoutMode.Form this arrangement is for.
var form: LayoutMode.Form = LayoutMode.Form.PHONE_LANDSCAPE
## Holds the turret view, its overlay and the aim pad.
var stage: Control = Control.new()
var pad: WeaponsAimPad = WeaponsAimPad.new()
var mount_button: RailButton
var claim_button: RailButton
var ammo_button: RailButton
var guided_button: RailButton
var fire_button: RailButton
## The target line (landscape only; upright the overlay draws it).
var target_label: Label = null
## The rail's radar (landscape, Weapons alone on the screen), else null.
var radar: DiscRadar = null
## The landscape rails, else null.
var layout: RailLayout = null

var _panel: WeaponsPanel


func _init(panel: WeaponsPanel, for_form: LayoutMode.Form, with_radar: bool) -> void:
	_panel = panel
	form = for_form
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.dragged.connect(panel.touch_aim)
	pad.tapped.connect(func(p: Vector2) -> void: panel.touch_select(pad.get_global_transform() * p))
	_make_buttons()
	if form == LayoutMode.Form.PHONE_LANDSCAPE:
		_landscape(with_radar)
	else:
		_portrait()


## Moves the panel's view and overlay onto the stage, under the aim pad.
func take_view(view: Control, overlay: Control) -> void:
	for c: Control in [view, overlay]:
		c.reparent(stage, false)
		c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(pad)


## Texts and states from the panel, once a frame.
func refresh() -> void:
	var p: WeaponsPanel = _panel
	mount_button.text = p.mount_text(p.mount)
	var mine: bool = p.is_mine(p.mount)
	var free: bool = p.is_usable(p.mount)
	claim_button.text = (
		TouchText.of("weapons.touch_release", "Release")
		if mine
		else TouchText.of("weapons.touch_claim", "Claim") if free else p.holder_name(p.mount)
	)
	claim_button.disabled = not free
	ammo_button.text = p.ammo_name() + " ▸"
	if target_label != null:
		target_label.text = p.target_text()
	if radar != null:
		radar.set_picture(p.ctx.picture(), p.ctx.crew.selection)


func _make_buttons() -> void:
	mount_button = RailButton.make("", RailButton.Role.ACCENT)
	mount_button.custom_minimum_size.y = MOUNT_H
	mount_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mount_button.add_theme_font_size_override("font_size", FONT_SMALL)
	mount_button.pressed.connect(_panel.touch_press.bind("mount_next"))
	claim_button = RailButton.make("")
	claim_button.pressed.connect(_panel.touch_claim)
	ammo_button = RailButton.make("")
	ammo_button.pressed.connect(_panel.touch_press.bind("ammo_next"))
	guided_button = RailButton.make(TouchText.of("weapons.touch_guided", "Guided"))
	guided_button.pressed.connect(_panel.touch_press.bind("fire_guided"))
	fire_button = RailButton.make(
		TouchText.of("weapons.touch_fire", "FIRE"), RailButton.Role.DANGER
	)
	fire_button.hold = true
	fire_button.custom_minimum_size.y = FIRE_H
	fire_button.held.connect(_panel.touch_hold.bind("fire"))


func _landscape(with_radar: bool) -> void:
	layout = RailLayout.new()
	layout.docked = true
	add_child(layout)
	layout.set_content(stage)
	var left: TouchRail = layout.rail(SIDE_LEFT)
	left.custom_minimum_size.x = RAIL_W
	left.add(mount_button)
	left.add(claim_button)
	left.add(ammo_button)
	target_label = Label.new()
	target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	target_label.add_theme_font_size_override("font_size", FONT_SMALL - 1)
	target_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add(target_label)
	var right: TouchRail = layout.rail(SIDE_RIGHT)
	right.custom_minimum_size.x = RAIL_W
	if with_radar:
		radar = DiscRadar.new()
		radar.custom_minimum_size.y = RADAR_H
		radar.gui_input.connect(_on_radar_input)
		right.add(radar)
	right.add(guided_button)
	right.add_spacer()
	right.add(fire_button)


## Upright: the view, then [mount | ammo] and [claim | Guided | FIRE] under it, FIRE
## under the right thumb.
func _portrait() -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	add_child(col)
	col.add_child(stage)
	var bar: MarginContainer = MarginContainer.new()
	for side: String in ["margin_left", "margin_right"]:
		bar.add_theme_constant_override(side, UiTheme.TOUCH_GAP)
	bar.add_to_group(TouchInput.GROUP)
	col.add_child(bar)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
	bar.add_child(rows)
	fire_button.custom_minimum_size.y = UiTheme.TOUCH_PRIMARY
	fire_button.size_flags_stretch_ratio = 1.5
	for row: Array in [[mount_button, ammo_button], [claim_button, guided_button, fire_button]]:
		var box: HBoxContainer = HBoxContainer.new()
		box.add_theme_constant_override("separation", UiTheme.TOUCH_GAP)
		for b: RailButton in row:
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			box.add_child(b)
		rows.add_child(box)


## A finger on the rail radar selects the nearest blip (the screen never sees taps on a
## rail); the range label still steps the range through the emulated mouse.
func _on_radar_input(event: InputEvent) -> void:
	var t: InputEventScreenTouch = event as InputEventScreenTouch
	if t == null or t.pressed:
		return
	var item: Dictionary = radar.item_at(t.position, RADAR_REACH)
	if not item.is_empty() and item["kind"] != "point":
		_panel.ctx.crew.select(item["kind"], item["id"])
