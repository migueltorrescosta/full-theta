# Accessibility audit (M5, #12, FT-STN-006, FT-STN-007, FT-STN-013, FT-STN-014, FT-STN-017, FT-AUD-010)

This is the audit phase. It records what was checked, what passed and each gap with its proposed fix. Fixes follow in a second phase, after the 3D-view and HUD strand merges, because most of them change layouts or colours and so the L5 baselines. Effort: S is under an hour, M a few hours, L a day or more. "Baselines" in the last column means the fix changes L5 images.

## How to rerun the checks

| Check | Command | In L0 |
|---|---|---|
| Palette roles stay apart under protanopia, deuteranopia and tritanopia (CIEDE2000 at least 10); WCAG contrast of the listed pairs | `uv run --project tools python tools/check_palette.py` | yes (`palette`) |
| Allegiance and alert level keep a distinct letter, shape and role; every script that tints by allegiance or alert also draws a shape or letter | `uv run --project tools python tools/check_colourblind.py` | yes (`colourblind`, 0.3 s) |
| The same on all L5 baselines, a baseline for every station and joint view, and simulated copies for review | `tools/check_colourblind.py --images --simulate DIR` | no (about 1.5 min on 4 cores) |
| Contrast of every colour role on each surface | `tools/check_palette.py --report` | no |

The simulation is Machado, Oliveira and Fernandes (2009), severity 1.0, in linear RGB. The image check finds which palette roles are on screen (pixels within 3 per channel of the role's colour, at least 12 of them) and reports the smallest CIEDE2000 between two on-screen roles of a group. It also lists, as information, any two on-screen roles that differ by 20 or more under normal vision and by under 5 under a simulation.

## 1. Colour-blind simulation (criterion 1)

| Check | Result |
|---|---|
| Roles of each group (allegiance, radar, alert, load, stations) at least 10 apart under every simulation | Pass. Smallest on the baselines: allegiance 16.7, radar 14.2, alert 13.3, stations 10.9 |
| 268 baselines analysed, 174 show allegiance roles and 201 alert roles; a baseline exists for all 8 stations and all 15 joint views | Pass, no group pair under 10 in any image |
| Allegiance has distinct letters (H, U, F, N), shapes (triangle, circle, square, hexagon) and roles | Pass (tested) |
| Alert level has distinct letters (N, Y, R), shapes (circle, triangle, square) and roles | Pass (tested) |
| Every script that tints by allegiance or alert draws a shape or letter | Pass: 10 scripts draw a shape or read the allegiance letter; 5 are listed in `TEXT_CARRIERS` (tinted list rows that carry the callsign, the alert flash whose chip and tone carry the level, and two id tables with no drawing). A new colour-only use fails L0 |
| Simulated images reviewed by eye (relay station, deuteranopia) | Blips keep their shape, rows keep their callsign letter, the alert chip keeps N |

Gaps:

| # | Gap | Proposed fix | Effort |
|---|---|---|---|
| C1 | The seat load of the lobby (intense, busy, light) is red, yellow or green on the name and border only. FT-STN-006 does not require a second code for it, but WCAG 1.4.1 does. The three colours are 12.7 or more apart under every simulation, so the colour itself is safe. | Add a pip count (3, 2 or 1 filled pips) beside the seat name in `lobby_screen.gd` and the legend. Owner choice Q1. | S, baselines |
| C2 | Blips are 6 px in radius at 100 %, so 4.5 px at 75 % UI scale: triangle, square and circle are hard to tell apart. | Draw blips at least 6 physical px (divide by the window's `content_scale_factor`) in `disc_radar.gd` and `relay_map.gd` (`BLIP_R`). | S, baselines |
| C3 | Information only: `st_captain` vs `st_helm` is 3.9 under protanopia, `st_relay` vs `st_viewer` 1.7 under deuteranopia. These tints appear only in the controls diagram, which always names the station. | None proposed; the checker does not put Captain and Viewer in the `stations` group because they are never in a joint view. | none |

## 2. Contrast (criterion 2)

Ratios come from `check_palette.py --report` (WCAG 2.2: 4.5 body text, 3 large text and user-interface parts). Roles that are only ever drawn as fills and strokes need 3; roles used as text need 4.5.

| Check | Result |
|---|---|
| `text` on background, panel, panel focus and the danger button fill | Pass: 16.3, 14.7, 12.3, 11.1 |
| `text_dim` (captions, placeholders, disabled) on background, panel, panel focus | Pass: 6.5, 5.9, 4.9. Disabled text is exempt in any case |
| `accent`, `warn`, `ok`, `unknown`, `friendly`, `hostile`, `neutral` as text on background, panel, panel focus | Pass: lowest is hostile on panel focus, 4.69 |
| Lobby load colours as text on panel and panel focus | Pass: lowest 5.73 (also checked under each simulation by `check_palette.py`) |
| `line_strong` hairlines (panels, rails, sheets, cards, lists, tabs) on background and panel | Pass: 3.52 and 3.17 (D304) |
| Focus ring (`accent`, 2 px) on panel | Pass: 6.85 |
| `danger` and `alert_red` as text on background, panel, panel focus | Fail: 3.87, 3.49, 2.93 |
| Borders of buttons, option buttons, text fields and lobby cells (`line`) on panel and background | Fail: 1.8 and 2.0 |
| `st_weapons` on panel, `st_science` on panel focus, as text | Below 4.5 (4.48, 4.25), but they are never text: tints of the controls diagram |
| `text_dim` on the diagram's `key` fill | 3.89; not used (diagram key labels use `text`, 9.7) |
| Subtitles over the 3D view and overlay rails (80 % opaque panel over the view) | Not measurable: no backing for subtitles, rails depend on the view behind them |

Gaps:

| # | Gap | Proposed fix | Effort |
|---|---|---|---|
| W1 | Red text is 3.49 on panels. It is used for fault lines and the hit and lane warnings: `engineering_panel.gd` (fault lines and spare parts), `station_alerts.gd` (the `danger` toast kind), `helm_hud.gd` (the "late" word), `viewer/status_view.gd` and `hack_game.gd`. | Add a role `danger_text` (`#e56c7b`, 4.68 on background, panel and panel focus) to `palette.gd` ROLES and CONTRAST. Use it for those text sites; keep `danger` for fills and strokes, where 3.49 on panel passes 3:1 (on panel focus it is 2.93, so lighten `danger` itself if it is ever drawn there). | S, baselines |
| W2 | Control borders are 1.8 to 2.0 against their surroundings, under the 3 of WCAG 1.4.11 where the border is what shows a control's extent (text fields, option buttons). | In `ui_theme.gd` `_buttons`, `_fields`, `_check` and `_cell` use `line_strong` for the resting border (as D304 did for panels); hover and pressed already use `accent`. | S, baselines |
| W3 | Subtitles are a bare label over the view, with no backing or outline. | Put them in a `Banner` panel (the panel style already in `ui_theme.gd`) in `client_shell.gd` `_subtitles`; see also S1. | S, baselines |

## 3. Text size and UI scale (criterion 3)

Shots at 75 % and 150 % of every station, joint view and the lobby (1280 x 720, thirty throwaway renders in `~/.local/state/full-theta/m5a11y/scale/`, not baselines). 150 % leaves 853 x 480 logical pixels, 75 % gives 1707 x 960.

Smallest rendered text sizes (px at 100 %, then at 75 %): alert chip letter 11 (8.3), captions and the shield ring 12 (9), touch hints and the relay map 13 (9.8), HUD and viewer labels 14 to 15 (10.5 to 11.3), body 16 (12). Touch targets are 44 px at 100 % and 33 px at 75 %.

| Check | Result |
|---|---|
| Slider range and step | Pass: 75 to 150 %, 5 % steps, persisted, clamped on load (`test_ui_scale_is_clamped_to_75_150_percent`) |
| 75 %: clipping or overlap on any station | None found; text is small (above) |
| 150 %: Helm, Weapons, Tactical, Systems, Ops, Viewer, Comms, Relay | No clipping; radar labels overlap their ring lines (also at 100 %) |
| 150 %: Science | Fail, see T1 |
| 150 %: Engineering | Fail, see T2 |
| 150 %: lobby | One line clipped with an ellipsis, see T3 |

Gaps:

| # | Gap | Proposed fix | Effort |
|---|---|---|---|
| T1 | Science at 150 %: the contact list takes the whole upper area, so the scan radar is squeezed into a strip about 20 px high, with "10 km" and the Kappa chip cut, and the detail text is mostly empty. | In `science_panel.gd` give the radar a minimum height and let the list scroll (a share of the height, not all of it). | M, baselines |
| T2 | Engineering at 150 %: the hint "Drag a crew onto a part ..." overlaps the WPN label; the red hit line ("Hit, 6 level") overlaps the radar's U3 label; the Shields block is cut after "Focus" and the faults list needs scrolling. | In `engineering_panel.gd` / `engineering_cutaway.gd` wrap the hint above the cutaway, move the hit line under the fault line, and make the middle column scroll. | M, baselines |
| T3 | Lobby at 150 %: the description of the picked pair ("Systems ... what br...") ends in an ellipsis. | Wrap it to two lines in `lobby_screen.gd` instead of clipping. | S, baselines |
| T4 | Alert chip letter is 11 px at 100 % (8.3 px at 75 %): the letter that backs the shape is the smallest text in the game. | Raise `CHIP_LETTER_SIZE` in `top_bar.gd` to 14. Owner choice Q4 for a general floor. | S, baselines |
| T5 | Touch targets shrink to 33 px at 75 % (below the 44 px of D218), because the scale applies to every size. | Hide scales under 100 % on the touch and phone layouts in `settings_screen.gd`, or keep `TOUCH_MIN` in physical pixels. Owner choice Q3. | S |
| T6 | Radar and relay labels overlap their own ring and stem lines at every scale ("H2 4 high mid" crossed by the ring). | Draw labels with `Palette.draw_outlined` (exists) in `disc_radar.gd` and `relay_map.gd`. | S, baselines |

## 4. Input, hold-to-toggle, comfort, subtitles (criterion 4)

| Check | Result |
|---|---|
| FT-STN-007 rebindable and persisted per client | Pass: `IntentTable` rows for every intent on keyboard and mouse and on the controller; capture in `settings_screen.gd`, collisions reported (`settings.taken`), reset button, saved in `ClientSettings` (`test_rebind_replaces_defaults_per_device`, `test_settings_screen_rebinds_from_a_pressed_key`) |
| FT-STN-014 every hold has a toggle | Pass: the seven hold intents (face, approach, helm radial, helm pointer, fire, fire all, relay radial) each show a Toggle check box; the matcher honours it (`test_hold_and_toggle_modes`); persisted with the bindings |
| FT-STN-017 comfort toggle | Pass: `ComfortCamera` is used by the Helm cockpit (`helm_view.gd`), the turret camera (`weapons_panel.gd`) and the main screen (`viewer_panel.gd`); roll lock to deck, target or reference plane, reduced field of view, "set reference plane" (`test_helm_panel`, `test_viewer_panel`, `test_weapons_panel`, `test_client_settings`) |
| FT-AUD-010 every spoken line is also a subtitle | Pass: `SubtitleFeed` makes a subtitle for every voice line whether or not audio plays, labelled with the speaker, on screen 2 s plus 60 ms per character (about 17 characters a second), at most 6 kept |
| Sound off | Pass: the top bar shows "Sound on" / "off" (`test_sound_toggle`) |
| Motion and flashing | Pass: the alert flash is one 700 ms fade of a frame, not a flash sequence; the star backdrop has no parallax (D310) |
| Alert is not sound only | Pass: the tone comes with the flash, the top bar's chip (letter and shape) and the toast |

Gaps:

| # | Gap | Proposed fix | Effort |
|---|---|---|---|
| S1 | Subtitles have no setting: size follows only the UI scale, and a missed line cannot be read again. | Backing panel (W3). A size option or a log is owner choice Q2. | S to M |
| I1 | The pad's alert and radial intents are chords that need View held while another button is pressed (View+Up, View+RS). The toggle option exists only for the single-button holds. | None proposed: chords are rebindable, and one-button alternatives can be bound. Mention in the in-app Controls tab if the owner wants. | none |

Not assessed, because the spec has no requirement: screen-reader support (Godot's AccessKit), a high-contrast theme, remappable touch gestures. They are not gaps against the spec.

## Questions for the owner

Each has a recommendation; the first option is the recommended one.

- **Q1 (C1).** How should the lobby show seat load beyond colour (D187)? (a) A pip count beside the name, 3, 2 or 1 filled pips, and the same in the legend. (b) Bring back the words intense, busy and light, which D187 dropped. (c) Leave it as colour: the colours are distinguishable, and FT-STN-006 asks no more.
- **Q2 (S1).** What should subtitles offer? (a) A backing panel only (recommended: FT-AUD-010 says every line shows). (b) The panel and a size setting, small, normal, large. (c) The panel, the size and a log of the last 20 lines.
- **Q3 (T5).** What should scales below 100 % do on touch and phone layouts? (a) Hide them, so targets stay 44 px or more. (b) Keep them and accept 33 px targets. (c) Keep them and keep targets at 44 physical px.
- **Q4 (T4).** What is the smallest text? (a) 12 px at 100 % for everything, so the chip letter moves from 11 to 12 and nothing else changes (recommended: smallest change, 9 px at 75 %). (b) 14 px at 100 %, which touches about 25 constants and many layouts (L). (c) No floor.
- **Q5 (T1, T2).** The 150 % layouts of Science and Engineering are cramped at 1280 x 720 (853 x 480 logical). (a) Fix both layouts so nothing overlaps at 853 x 480 (recommended, M each). (b) Limit the maximum scale to what fits the window, for example 125 % on a 720p window, which narrows FT-STN-013's 75 to 150 %. (c) Accept as is.
