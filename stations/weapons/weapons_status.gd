class_name WeaponsStatus
extends RefCounted
## What a mount's state reads as on Weapons' touch controls (C6): heat as a word and a
## colour role, why FIRE can't shoot, the one Claim button's text, the arrow at the reticle
## toward an out-of-arc target. Reads the panel; draws nothing.

## Heat share from which a mount reads warm (amber).
const HEAT_WARM: float = 0.7


## Heat share (0..1 and over) of mount i.
static func heat_share(p: WeaponsPanel, i: int) -> float:
	return float(p.mount_row(i).get("heat", 0.0)) / p.weapon_of(i).heat_limit


## The word for mount i's heat: cool, warm from HEAT_WARM of the limit, HOT at it (the colour
## is never the only signal).
static func heat_word(p: WeaponsPanel, i: int) -> String:
	var heat: float = heat_share(p, i)
	if heat >= 1.0:
		return p.tr("weapons.heat_hot")
	return p.tr("weapons.heat_warm" if heat >= HEAT_WARM else "weapons.heat_cool")


## The palette role of mount i's heat: text, warn when warm, danger at the limit.
static func heat_role(p: WeaponsPanel, i: int) -> String:
	var heat: float = heat_share(p, i)
	return "danger_text" if heat >= 1.0 else ("warn" if heat >= HEAT_WARM else "text")


## Why FIRE can't shoot mount i now: the word for it ("empty", "locked", "hot", "arc",
## "taken"), "" when it can. A free mount is no reason: it fires without a claim (V29).
static func fire_block(p: WeaponsPanel, i: int) -> String:
	if i < 0 or i >= p.mount_count():
		return ""
	if not p.is_usable(i):
		return "taken"
	var row: Dictionary = p.mount_row(i)
	if int(row.get("ammo", 1)) == 0:
		return "empty"
	if bool(row.get("locked", false)):
		return "locked"
	if float(row.get("heat", 0.0)) >= p.weapon_of(i).heat_limit:
		return "hot"
	return "" if p.in_arc(i, p.aim_dir(i)) else "arc"


## The FIRE button's text: FIRE, with the reason under it while it can't shoot.
static func fire_text(p: WeaponsPanel, i: int) -> String:
	var fire: String = TouchText.of("weapons.touch_fire", "FIRE")
	var why: String = fire_block(p, i)
	if why == "":
		return fire
	var key: String = ("weapons.fire_" if why in ["arc", "taken"] else "weapons.") + why
	return "%s\n%s" % [fire, p.tr(key)]


## Sets the FIRE button's text and role for mount i: it says why it can't shoot and greys
## then (a free mount fires, V29). Phone and tablet share it.
static func show_fire(p: WeaponsPanel, button: RailButton, i: int) -> void:
	var text: String = fire_text(p, i)
	if button.text != text:
		button.text = text
	var role: RailButton.Role = (
		RailButton.Role.PLAIN if fire_block(p, i) != "" else RailButton.Role.DANGER
	)
	if button.role != role:
		button.role = role


## The Claim button's text for mount i: ticked while this client holds it, the holder's name
## while another does; one button in one place, whatever the state.
static func claim_text(p: WeaponsPanel, i: int) -> String:
	if p.is_mine(i):
		return TouchText.of("weapons.touch_claim_held", "✓ Claim")
	if p.is_usable(i):
		return TouchText.of("weapons.touch_claim", "Claim")
	return p.holder_name(i)


## The direction (screen, unit) the camera must turn toward the selected contact when it is
## out of the camera mount's arc, else ZERO: the arrow at the reticle.
static func arc_arrow_dir(p: WeaponsPanel) -> Vector2:
	if p.out_of_arc_text() == "":
		return Vector2.ZERO
	var at: Vector3 = p.ctx.interp.contact_position(p.selected_contact())
	var cam: Vector3 = p.cam_basis.transposed() * p.ctx.interp.offset_to(at).normalized()
	var d: Vector2 = Vector2(cam.x, -cam.y)
	return d.normalized() if d.length() > 0.05 else Vector2.UP


## Mount i for the phone's mount button: "1 bow · ready", "heat 15% cool", "380/400 rounds"
## on a line each; `wide` joins the last two (the mount list).
static func mount_text(p: WeaponsPanel, i: int, wide: bool = false) -> String:
	if i < 0 or i >= p.mount_count():
		return ""
	var w: WeaponDef = p.weapon_of(i)
	var ammo: int = int(p.mount_row(i).get("ammo", w.ammo_capacity))
	var rounds: String = "∞" if ammo < 0 else p.tr("weapons.rounds") % [ammo, w.ammo_capacity]
	var heat: String = p.tr("weapons.heat") % roundi(heat_share(p, i) * 100.0)
	return (
		"%d %s · %s\n%s %s%s%s"
		% [
			i + 1,
			p.ship_def.mounts[i].id,
			p.tr("weapons." + WeaponsReadout.mount_state(p, i)),
			heat,
			heat_word(p, i),
			" · " if wide else "\n",
			rounds,
		]
	)
