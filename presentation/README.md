# presentation/

Rendering, cameras and shared widgets; never sim/ (FT-ARC-011). May name stations/, input/, audio/, net/, shared/ and content/ only. All text goes through `tr()` keys in `content/i18n/strings.json`.

## Files

- `palette.gd` (`Palette`): the colour roles (`ROLES`), the groups that must stay apart (`GROUPS`) and the text contrast pairs (`CONTRAST`), checked by `tools/check_palette.py` in l0 (FT-STN-006); allegiance letter to shape and role, alert levels (`ALERTS`), `shape_points` for blips and chips.
- `snapshot_interpolator.gd` (`SnapshotInterpolator`): the own ship and contacts between snapshots, a render clock behind the newest snapshot, minimum-image interpolation (FT-ARC-015, D124). The class comment covers the clock and when contacts appear and go.
- `chip_text.gd` (`ChipText`): `chip` ("H2 · 4 high · mid") and `precise` (hover bearing and mark), from `Callout` (FT-SPA-003, FT-SPA-005, D114).
- `contact_picture.gd` (`ContactPicture`): the frame's items from a `StationContext` (contacts, marks, point pings, with ping pulses), each with its world-axis minimum-image offset from the own ship (`world`) and its ship-frame offset (`local`); built at most once a frame by `StationContext.picture()`.
- `space_view.gd` (`SpaceView`): the shared 3D space of Helm, Weapons and the main screen: environment, stars and the other ships (`sync_ships`).
- `disc_radar.gd` (`DiscRadar`): the shared disc radar, drawn in 2D (§6.2). Helpers `project`, `is_above`, `is_beyond`, `item_at`, `hover_text`.
- `top_bar.gd` (`TopBar`): ship name, hull, shields, reactor pips, the alert chip and its crew-only picker (`alert_picked`), station names, mission timer (FT-STN-001, FT-STN-006, FT-STN-008).
- `toasts.gd` (`Toasts`): top-right lines that expire (`SHOW_MS`, `MAX`).
- `alert_flash.gd` (`AlertFlash`): the screen-edge flash of an alert, fading over `FLASH_MS`.
- `controls_overlay.gd` (`ControlsOverlay`): the `?` overlay, generated from `Bindings` and `IntentTable` for the screen's stations and device; it follows rebinds (FT-STN-011).
- `first_run_tooltip.gd` (`FirstRunTooltip`): a station's controls tip, once per client and station (FT-STN-012).
- `procedural_ship.gd` (`ProceduralShip`): the approved ship art (D107).
- `comfort_camera.gd` (`ComfortCamera`): the comfort toggle's camera roll (deck, target, reference plane) and field of view (FT-STN-017), for the cockpit, turret and main screen; `target_rot(ctx)` reads the selected ship's NEAR orientation.

## Using the radar on a station

A panel owns a `DiscRadar` child sized to its inset or main view. Every frame (or on `ctx.crew.changed` and a new snapshot) it calls `radar.set_picture(ctx.picture(), ctx.crew.selection)`. It sets `orbitable` from `StationPanel.radar_orbitable`, `chips = false` on small insets, and `centre` to the selection where the station may centre the radar (Relay, Captain, the tactical main screen). There is no world up (D124): the picture's items carry world-axis offsets from the own ship by minimum image, and the radar draws each one as the wrapped offset from its centre (the own ship or the selected reference) rotated into the ship frame, so clock and height words match the ship's. The screen toggles the elevation side strip with `toggle_strip` on the `radar_strip` intent: Z, controller View + d-pad left, on every station (FT-SPA-009, D175). Clicks stay with the screen: `StationPanel.item_at` maps the pointer into the radar and returns `radar.item_at(pos)` for select, ping and mark. The wheel zooms, a click on the range label steps the range, and right-drag orbits when `orbitable` is set.

The screen owns one `TopBar` and calls `show_state` with `ctx.crew.ship_name()`, the STATUS block (`ctx.view.blocks`), `ctx.crew.alert`, `ctx.crew.stations()` and `ctx.crew.mission_seconds(ctx.view.tick)`. It sets `can_set_alert = ctx.crew.is_crew()` and sends the alert intent on `alert_picked`.
