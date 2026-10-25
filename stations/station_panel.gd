class_name StationPanel
extends Control
## Base of every station panel (FT-JNT-001). A StationScreen holds one panel for a
## single station, two for a joint view (six for the dev entry); one is focused at a
## time and only it receives its station's intents, apart from the intents live on the
## device (IntentTable.target). The focused panel shows its main view (cockpit, turret,
## cutaway, map) in the screen's main area; the others show their compact docked view.
##
## Subclass it in stations/<station>/, register the script in StationRegistry, and
## override the virtuals below. Read state through `ctx` (StationContext): ctx.view and
## ctx.interp for the snapshot, ctx.crew for selection, marks, pings, claims; send with
## ctx.intents. Never name sim/ (FT-ARC-011).

## The station this panel serves (IntentTable group).
var station: String = ""
var ctx: StationContext = null
var focused: bool = false
var docked: bool = false


## Called once by the screen before the panel enters the tree.
func setup(context: StationContext, station_id: String) -> void:
	ctx = context
	station = station_id
	_setup()


## Focus and dock state; the screen calls it on every focus change.
func set_mode(is_focused: bool, is_docked: bool) -> void:
	focused = is_focused
	docked = is_docked
	_mode_changed()
	queue_redraw()


# --- Virtuals. ---


## Build children here (ctx and station are set).
func _setup() -> void:
	pass


## Focus or dock state changed: switch between the main and the compact view.
func _mode_changed() -> void:
	pass


## A station intent event (InputMatcher's dictionary) routed to this panel; return true
## when handled. Axis intents are polled instead: ctx.matcher.axis(id).
func handle_intent(_event: Dictionary) -> bool:
	return false


## The item under the cursor or reticle for select / ping / mark (§5.0: in cockpit and
## turret views "under the cursor" means under the reticle): {"kind", "id"} or
## {"kind": "point", "site", "pos"}; {} for nothing. `screen_pos` is in this panel's
## coordinates.
func item_at(_screen_pos: Vector2) -> Dictionary:
	return {}


## Where a controller's "under the cursor" points on this panel (its coordinates): the
## reticle at the centre unless the panel moves a cursor (Relay's map).
func cursor_pos() -> Vector2:
	return size / 2.0


## True when the panel draws its own radar and wants the whole screen when it is alone
## (the main screen's wide radar, §5.8): the screen hides its side column.
func full_screen() -> bool:
	return false


## The ship has 8 marks and the common mark action wants `item` (as item_at returns):
## a panel that may replace one (Relay, FT-SPA-022) does it and returns true; false
## shows the "marks full" toast.
func replace_mark(_item: Dictionary) -> bool:
	return false


## True when the panel's main view looks forward (Helm's cockpit, the turret): a mark
## there attaches to the tapped contact and a tap that hits none places no mark
## (FT-SPA-030).
func marks_attach_only() -> bool:
	return false


## True when the panel has request chips (B / View+Y sends one, §5.0, §7.4).
func has_request_chip() -> bool:
	return false


## The panel's request-chip handler (B, View+Y). FT-JNT-005: a request to a station on
## this same screen (ctx.crew.stations()) runs as the direct action instead of a chip
## (Boost in a Helm+Engineering view overcharges at once). M1 has no request chips yet.
func send_request() -> void:
	pass


## The claim item the common claim action (K, View+X) takes or releases on this panel
## (e.g. "flight", "mount:2"); "" when it has none.
func claim_item() -> String:
	return ""


## Whether mouse motion steers this panel (the mouse stick behind "MouseX"/"MouseY")
## while it has focus; Helm says no while the pointer is free.
func mouse_steers() -> bool:
	return true


## Whether the disc radar should be orbitable on this panel's screen (FT-SPA-011:
## Science and Relay yes, Helm and Weapons insets fixed).
func radar_orbitable() -> bool:
	return station in ["science", "relay"]


## Contact id -> blip size factor for the screen's disc radar while this panel is
## focused (Science's detection confidence, FT-SCI-001); {} draws every blip alike.
func blip_scale() -> Dictionary:
	return {}
