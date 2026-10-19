# stations/

Station UIs; they read snapshots and send intents, never sim/ (FT-ARC-011). The client's main menu is `app/main_menu.gd` (`MainMenu`): only app/ may name `HostSession`. Once a client is welcomed it hands the `NetClient` to `ClientShell` here.

## Files

| File | Role |
|---|---|
| `client_shell.gd` | `ClientShell`: the session. Polls the client, forwards every event to `VoicePlayer.handle_event` (voice lines) or `CrewState.handle_event`, pumps voice parts, applies Welcome `lang` (`I18n.apply`, `LocalLines`), pushes snapshots into the `SnapshotInterpolator`, resumes a dropped connection with its token, and shows `LobbyScreen` until the pick's ship has started, then the `StationScreen` of the pick, with `PauseOverlay`, `OutcomeCard`, subtitles and `SettingsScreen` on top. |
| `station_context.gd` | `StationContext`: what panels read and send through: `view` (`NetViewState`), `interp`, `crew`, `intents`, `settings`, `matcher`, `clock`; helpers `selection_local()`, `mark_position()`. |
| `crew_state.gd` | `CrewState`: the model built from Welcome, the Catalogue and events: pick, catalogue, lobby, Start, claims, pause, abandon votes, the outcome card and its "Run again" votes (`run_over`), alert, marks (Alpha to Hotel), pings (3 s pulse, copies), and the selection every panel of the client shares. Signals `changed(what)`, `toast(key, args)`, `pinged(ping)` (the ping chime), `sim_event(kind, payload)` (events it doesn't keep: hit, fault, ...). |
| `ship_intents.gd` | `ShipIntents`: the one send seam (alert, marks, pings, claims, picks, Start, votes, commands). Tests swap the client for a recorder. |
| `station_screen.gd` | `StationScreen`: top bar, one disc radar, panels (one focused in the main area, the rest docked), toasts, controls overlay, first-run tip. Feeds input through `InputMatcher` and routes each intent event by `IntentTable.target`; handles the common actions (`_common`) and the station-less live set (`_live`). |
| `station_alerts.gd` | `StationAlerts`: the own ship's hits, faults, low shields and collision warnings as a toast, an edge flash (`AlertFlash`) and a tone (`AlertTones`) on the stations they affect (`ROUTES`, `DEPENDS`); the ping chime and the alert-level tone (T056). |
| `station_panel.gd` | `StationPanel`: base class of every panel. |
| `station_registry.gd` | `StationRegistry.PANELS`: station id to panel script; unlisted ids get `PlaceholderPanel`. |
| `helm/` | `HelmPanel` (§5.1, T051): cockpit or chase view (`HelmView`), HUD with compass and off-screen arrows (`HelmHud`), `ShieldRing`; the controller radial is `HelmPanel.RADIAL`. The class comments give what it sends and when. |
| `relay/relay_panel.gd`, `relay/relay_map.gd` | `RelayPanel`, `RelayMap`: Relay's map read-out and mark curation (§5.5): drag to place on the view plane, Shift+drag depth, drag to move, drop on a contact to attach, N rename, Delete, M attach or free, C centre on the selection, right-drag turn, wheel zoom; controller cursor on the sticks and triggers. |
| `viewer/viewer_panel.gd` | `ViewerPanel`: the main screen (§5.8): forward or chase view, callsign rail, wide radar; comfort roll locks and the auto-chase. |
| `placeholder_panel.gd` | `PlaceholderPanel`: name and StationDef read-out (Science and Comms in M1, FT-M1-005). |
| `lobby_screen.gd` | `LobbyScreen`: ships, catalogue entries with load tag and joint-view hint (`joint_hint`), coverage, pick, Start. |
| `pause_overlay.gd` | `PauseOverlay`: the pause, abandon vote, host Abandon, Captain/Viewer takeover. |
| `outcome_card.gd` | `OutcomeCard`: Victory or Ship lost, run time and hull on every station after the outcome; the crew's "Run again" vote, the host's "Run again now" (D178). |
| `settings_screen.gd` | `SettingsScreen`: bindings (rebind per device, hold/toggle, reset), UI scale, first-run tips again, invert pitch, comfort. |
| `client_settings.gd` | `ClientSettings`: per-client settings in one ConfigFile (`user://client_settings.cfg`, path injectable): name, bindings, UI scale, tips seen, invert pitch, comfort (roll lock deck / target / reference, reduced FOV, the cosmetic reference plane). |

## Adding a station panel

1. Subclass `StationPanel` in `stations/<station>/<station>_panel.gd` and add one line to `StationRegistry.PANELS`.
2. Override what you need: `_setup()` (build children; `ctx` and `station` are set), `_mode_changed()` (focused main view or docked compact view: `focused`, `docked`), `handle_intent(event)` (your group's press and hold intents; return true when handled), `item_at(pos)` (the item under the cursor or reticle for select, ping and mark: `{"kind", "id"}` or `{"kind": "point", "site", "pos"}`), `has_request_chip()` and `send_request()` (B, View+Y), `claim_item()` (K, View+X), `tooltip_intents()` (first-run tip), `radar_orbitable()`, `mouse_steers()` (the screen feeds mouse motion to the matcher only while it is true; Helm frees the pointer), `cursor_pos()` (where a controller's "under the cursor" points; the centre by default), `full_screen()` (a lone panel that draws its own radar hides the side column: the main screen), `replace_mark(item)` (Relay replaces a mark when all 8 are used).
3. Axes are polled: `ctx.matcher.axis("helm_pitch")`; hold state: `ctx.matcher.is_held("face")` (toggle-aware).
4. Read `ctx.interp` for interpolated positions (`own_position`, `own_rotation`, `contact_ids`, `contact_position`, `offset_to`, `local`), `ctx.view.blocks[StationViews.Section.X]` for block fields, `ctx.view.claimer(item)`, `ctx.crew.selection`, `ctx.crew.marks`, `ctx.crew.pulse(kind, id, ctx.now_ms())`.
5. Send with `ctx.intents.command({"kind": ...})`, `ctx.intents.claim(item)`, `ctx.intents.place_mark(...)`.
6. Bindings: add rows to `IntentTable.INTENTS` (`input/intent_table.gd`, your station as group) and an `intent.<id>` key in every language of `content/i18n/strings.json`. The overlay and Settings follow.

The layout is fixed: top bar; the focused panel in the main area on the left; the radar and docked panels in a right column. A joint view is the same screen with two panels; F1/F2, hold View + LB/RB, or a click on a docked panel moves the focus (FT-JNT-001). Always-live intents (`IntentTable.is_live`) reach their station's panel whatever the focus (FT-JNT-007).

## Common actions (§5.0, FT-STN-009)

- Select (click, A): the item under the pointer or reticle; over nothing the click falls through, so LMB still fires in the turret (owner decision in #7).
- Cycle target (T, RB tap): contacts nearest first. Select last pinged (Y, hold RB).
- Ping (middle-click, R3 tap): under the cursor, else the selection. Mark (Shift+middle-click, hold R3): under the cursor, else on the selected contact; refused with a toast at 8 marks; viewers don't mark.
- Accept and decline (Enter / Backspace, X / Y): to the focused panel. Request chip (B, View+Y): the focused panel's.
- Radar side strip (Z, View+Left; moved off B by the owner in #7). Claim or release (K, View+X): the focused panel's `claim_item()`.
- Overlay (?, View tap), menu (Esc, Menu).
- Alert (Alt+A cycles; hold View + d-pad; the top bar's chip picker): crew only (FT-STN-008).

## Tests and fixture

`tests/stations/station_fixture.gd` (`StationFixture`): `context(entry)` builds a full `StationContext` with no server: ship 0 "Kestrel" started, a hostile H2 at 4 high 2.3 km, an unknown U3 at 11 high 8 km, an own-faction F4 at 7 level 600 m, mark Bravo at 8 low 1.2 km, a pinned clock (`StationFixture.clock(ctx).ms`) and a `RecordingClient` (`StationFixture.sent(ctx).of("ping")`). Scene tests set `StationScreen.panel_factory` to inject test panels.

L5: `tests/visual/station_shot.tscn` shows the fixture (properties in `station_shot.gd`). Add a shot as a `tests/visual/shots.json` row with `"scene": "res://tests/visual/station_shot.tscn"`, `"size": [1280, 720]` and its `"set"` properties (`view`, `entry`, `selected`, `ping`, `overlay`, `tooltip`, `strip`, `ui_scale`), run `tools/gate.sh l5 --update-baselines`, and check the PNG by eye.
