# presentation/

Rendering, cameras and shared widgets; never sim/ (FT-ARC-011). May name stations/, input/, audio/, net/, shared/ and content/ only. All text goes through `tr()` keys in `content/i18n/strings.json`.

## Files

- `palette.gd` (`Palette`): the colour roles (`ROLES`), the groups that must stay apart (`GROUPS`) and the text contrast pairs (`CONTRAST`), checked by `tools/check_palette.py` in l0 (FT-STN-006); allegiance letter to shape and role, alert levels (`ALERTS`), `shape_points` for blips and chips.
- `snapshot_interpolator.gd` (`SnapshotInterpolator`): the own ship and contacts between snapshots, a render clock behind the newest snapshot, minimum-image interpolation (FT-ARC-015, D124). The class comment covers the clock and when contacts appear and go.
- `chip_text.gd` (`ChipText`): `chip` ("H2 · 4 high · mid") and `precise` (hover bearing and mark), from `Callout` (FT-SPA-003, FT-SPA-005, D114).
- `contact_picture.gd` (`ContactPicture.build`): the radar's items from a `StationContext`: contacts, marks, point pings, with ping pulses.
- `disc_radar.gd` (`DiscRadar`): the shared disc radar, drawn in 2D (§6.2). Helpers `project`, `is_above`, `is_beyond`, `item_at`, `hover_text`.
- `top_bar.gd` (`TopBar`): ship name, hull, shields, reactor pips, the alert chip and its crew-only picker (`alert_picked`), station names, mission timer (FT-STN-001, FT-STN-006, FT-STN-008).
- `toasts.gd` (`Toasts`): top-right lines that expire (`SHOW_MS`, `MAX`).
- `controls_overlay.gd` (`ControlsOverlay`): the `?` overlay, generated from `Bindings` and `IntentTable` for the screen's stations and device; it follows rebinds (FT-STN-011).
- `first_run_tooltip.gd` (`FirstRunTooltip`): a station's controls tip, once per client and station (FT-STN-012).
- `procedural_ship.gd` (`ProceduralShip`): the approved ship art (D107).

## Using the radar on a station

A panel owns a `DiscRadar` child sized to its inset or main view. Every frame (or on `ctx.crew.changed` and a new snapshot) it calls `radar.set_items(ContactPicture.build(ctx), ctx.crew.selection)`. It sets `orbitable` from `StationPanel.radar_orbitable`, `chips = false` on small insets, and `centre` to the selection where the station may centre the radar (Relay, Captain, the tactical main screen). The screen toggles the side strip with `toggle_strip` on the `radar_strip` intent. Clicks stay with the screen: `StationPanel.item_at` maps the pointer into the radar and returns `radar.item_at(pos)` for select, ping and mark. The wheel zooms, a click on the range label steps the range, and right-drag orbits when `orbitable` is set.

The screen owns one `TopBar` and calls `show_state` with `ctx.crew.ship_name()`, the STATUS block (`ctx.view.blocks`), `ctx.crew.alert`, `ctx.crew.stations()` and `ctx.crew.mission_seconds(ctx.view.tick)`. It sets `can_set_alert = ctx.crew.is_crew()` and sends the alert intent on `alert_picked`.
