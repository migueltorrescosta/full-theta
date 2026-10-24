# 5. Stations

Six functional stations plus the optional Captain seat and the shared main screen. Roles (owner, round 11): Helm = movement; Weapons = damage; Engineering = systems; Science = information gathering, scanning and hacking; Relay = tactical view of the universe; Comms = story of the universe; Captain = information only (D15, D23, D50–D54).

Wireframes are 16:9 sketches. A requirement below that says "on Easy" for a data shortcut means "when that shortcut's toggle is on" (§7.2, D84). Controls are listed as KB/M, controller, touch. Touch layouts for Helm and Weapons come with browser stations after milestone 1 (D8).

## 5.0 Common to every station

Top bar: ship name, hull, shields, reactor, alert level, station name(s), mission timer. Any crew station sets the alert level from the top bar (D89). Toasts top-right. Colour-blind-safe palette. The shared disc radar (§6) appears on every station (D43). Every callsign chip is clickable (select) and pingable (D61).

Common actions have the same binding on every station (D95). Station-specific bindings below avoid these keys and the always-live keys. In cockpit and turret views, where the mouse or sticks steer, "under the cursor" means under the reticle, and a left click selects only when the pointer is over a chip, mark or radar item; elsewhere it fires (T and Y also select). The binding-table check exempts this pointer case (D176).

| Action | KB/M | Controller | Touch |
|---|---|---|---|
| Select under the cursor | click | A | tap |
| Cycle target | T | RB | swipe the target chip |
| Select the last pinged item | Y | hold RB | tap the ping toast |
| Ping | middle-click | R3 | long-press |
| Place a mark at the cursor, or on the selection | Shift+middle-click | hold R3 | long-press, then drag |
| Accept / decline (oldest request, mark or selected card) | Enter / Backspace | X / Y | ACCEPT / DECLINE |
| Send a request chip (§7.4) | B, then 1–2 if the station has several | View+Y, then d-pad | chip bar |
| Claim / release | K | View+X | CLAIM |
| Radar side strip (§6.2) | Z | View + d-pad left | — |
| Controls overlay | ? | View (tap) | i |

Always-live set (works whatever panel has focus, §5.9): alert (Alt+A cycles; hold View + d-pad up Red, right Yellow, down Normal), ping (as above), panel switch (F1/F2; hold View + LB/RB; tap the panel), Helm translation (WASD, R/V), face (hold F; hold L3) and all-stop (Space; View+B). On a controller the sticks belong to the focused panel, so Helm translation is KB/M only and flight assist holds the throttle setpoint (D97). No station binds an always-live key for anything else.

- **FT-STN-001** Every station shall show the common top bar. (station-ui §2)
- **FT-STN-002** Every station shall show the shared disc radar at some size. (D43)
- **FT-STN-003** Every callsign chip and mark shall be selectable by click/tap and pingable by middle-click/long-press. (D44, D61)
- **FT-STN-004** Every critical alert shall be both visual and audible on the affected stations. (v0.3 §5)
- **FT-STN-005** Every station shall be usable with KB/M and a controller; touch layouts shall exist for every station once browser stations ship. (v0.3 §2, D8)
- **FT-STN-006** UI colours shall stay distinguishable under the common forms of colour blindness, and allegiance and alert level shall also be encoded by letter or shape; the three alert levels are Normal (green circle, N), Yellow (amber triangle, Y) and Red (red square, R). (station-ui §2, plan review UX-8, D170)
- **FT-STN-007** Input bindings shall be rebindable and persisted per client. (v0.3 §2)
- **FT-STN-008** Any crew station shall set the ship's alert level, Normal, Yellow or Red, from the top bar (KB/M: click the alert chip for a three-button picker, or Alt+A to cycle; controller: hold View and press d-pad up for Red, right for Yellow, down for Normal; touch: tap the alert chip); the Captain and viewers shall not. (D15, D89, D170)
- **FT-STN-009** Every station shall bind the common actions of §5.0 identically, and no station-specific binding shall reuse a common or always-live key. (D95, plan review UX-5)
- **FT-STN-010** Every crew station shall place a mark at its selection or cursor and send the request chips its pairs define, with one binding per device. (D44, §7.4, plan review STN-6)
- **FT-STN-011** Every station shall show an opaque controls overlay on `?`, View or `i`, generated from the live input map and translated, that retranslates at once when the language changes. (D100, plan review UX-1)
- **FT-STN-012** The controls overlay shall open by itself on a seat's first visit, once per client and station, and be re-enabled by a setting. It shall be headed by the seat's role summary (a short text of what the seat controls and what the crew expects, also shown on the seat's lobby entry), explain controls only and never tell a player to talk to another station. There is no separate first-run tooltip. (D100, D185, FT-PAIR-012)
- **FT-STN-013** Each client shall set a UI scale from 75 % to 150 %, persisted like bindings. (plan review UX-8)
- **FT-STN-014** Every hold input shall be switchable to a toggle in the bindings. (plan review UX-8)
- **FT-STN-015** The lobby catalogue shall show a load tag (light, busy or intense) for each station and joint view, read from its data definition (StationDef): Helm and Weapons intense, Engineering and Science busy, Relay and Comms light; Tactical intense, Systems busy, Ops light; Captain light; Viewer untagged. (D99, D126)
- **FT-STN-016** On first launch the lobby preset shall default to Easy, persisted per host; the toggles shall sit behind "Customise", each with a one-line description naming both stations. (plan review UX-9, D84)
- **FT-STN-017** Each client shall have a comfort toggle (roll locked to the ship's deck plane, the selected target or the player's optional cosmetic reference plane; reduced field of view) for the Helm cockpit, the turret camera and the main screen; the cosmetic plane shall never be spoken or used by rules. (plan review NAV-6, NAV-9, D124)

## 5.1 Helm (H-A cockpit, C toggles chase camera; D46)

Full-screen forward view; HUD with prograde/retrograde markers, target compass, off-screen arrows, route ribbon (routes toggle, D84), faint weapon-arc cones; thrust envelope and assist mode bottom-left; disc radar bottom-right; shield ring on the right edge.

```
+-[HELM]-hull 92 shld 70 rx 80-------------- ALERT RED -+
|  <H1                      ^Bravo                       |
|               .  +  .        H2[]  4 high 2.3km        |
|            (  prograde  )                     shield  |
|               '     '                         ( ring )|
|  compass (o)  sel: Kestrel Yard (site)  T/Y   4H sel  |
| THR [#####   ] ASSIST on      .--12--.  F face  L align|
| ROT [###     ] [STOP] [APPR] 9 H1* H2 3  [DOCK][JUMP]  |
+---------------------------------------'--6---'---------+
```

- KB/M: WASD translate, R/V up/down, mouse pitch/yaw, Q/E roll, Space all-stop, hold X approach, Tab decoupled, hold F face, L align, C chase camera, H dock, J jump, numpad 1–6 shield faces, click shield-ring sector, G shield track selected, B boost request; T/Y select (§5.0).
- Controller: left stick pitch/yaw (hold LB: left/right rolls), right stick strafe, triggers forward/back, hold L3 face, hold B approach, View+B all-stop, d-pad shield faces fore/aft/port/starboard, LB + d-pad up/down dorsal/ventral; hold View + right stick for a radial with dock, jump, ping, chase camera, Align, decoupled and shield track; A, RB and hold RB select (§5.0), View+Y boost request.
- Touch (assist on only): left virtual stick attitude, right stick translate, throttle slider, ALL-STOP, hold APPROACH, FACE / ALIGN / SHIELD-TRACK / DOCK / JUMP buttons, tap shield-ring sectors.

- **FT-HLM-001** Helm shall default to a cockpit forward view with HUD, target compass, disc radar and shield ring. (D46)
- **FT-HLM-002** Helm shall toggle a chase camera with C (controller: the Helm radial) without changing the HUD. (D46, D95)
- **FT-HLM-003** The target compass shall place a dot for the selected callsign, mark or site: filled when ahead, hollow when behind. (D47, D98)
- **FT-HLM-004** The cockpit shall show off-screen arrows for the selected target and pinged items. (station-ui §1.6)
- **FT-HLM-005** Holding F shall rotate the ship to face the selected target at the ship's real turn rate, through flight assist. (D47)
- **FT-HLM-006** Face assist shall work for contacts and marks, and in decoupled mode. (D47)
- **FT-HLM-007** Align shall roll the ship about its bow axis until the selected item lies in the ship's pitch plane above the bow (12 o'clock); a second press, or a press with the roll already done, shall also face it; Align shall end within tolerance, on rotation input or when the target is lost; with nothing selected Align shall do nothing. (D97, D124, D125)
- **FT-HLM-008** Helm shall snap shield focus to six faces (fore, aft, port, starboard, dorsal, ventral) with one input each. (D48)
- **FT-HLM-009** Tapping a clock sector with height on the shield ring shall set shield focus to that direction. (D48)
- **FT-HLM-010** A shield-track toggle shall keep shield focus on the selected callsign as both ships move. (D48)
- **FT-HLM-011** The shield ring shall show focus direction (Helm) and focus tightness and power (Engineering) in one widget. (D16, P1)
- **FT-HLM-012** Helm shall show the thrust envelope set by Engineering and the propellant remaining. (P1, D34)
- **FT-HLM-013** Helm shall offer dock and jump controls. (D29, P5)
- **FT-HLM-014** All-stop shall bring the ship's velocity and rotation to zero through real thrust, from one input on every device. (D97, plan review NAV-2)
- **FT-HLM-015** While hold-to-approach is held, flight assist shall face the selected item, fly to a data-defined stand-off and match its velocity, on every device. (D97, plan review NAV-2)
- **FT-HLM-016** JUMP shall jump to the selected site or mark once Helm faces it; sites shall be selectable on Helm like marks (§6). (D98, plan review NAV-4)
- **FT-HLM-017** Every Helm action, including cycle target, select pinged, Align, decoupled, all-stop and approach, shall have a controller binding. (FT-STN-005, plan review NAV-5, D124)

## 5.2 Weapons (W-B turret camera; D49)

Full-screen view from one claimed mount with lead reticle, arc edge and radar inset; swap between the player's claimed mounts. Weak-point brackets appear only when the weak-points toggle is on (D69, D84).

```
+-[WEAPONS mount 2]--------------------------------------+
|                      H2[]   weak:engine [toggle]       |
|                   .   +   .   lead                      |
|                  (  reticle )                           |
|                   '       '   arc edge ->| bring 3 high|
| mount 2 beam HOT 78%  ammo --  [swap 1..4] [K claim]   |
| claimed: 1 me  2 me  3 Ana  4 free       .-12-.        |
| target H2 4 high 2.3km  [G guided>Delta] 9  *  3       |
+------------------------------------------'--6-'--------+
```

- KB/M: mouse aims, LMB fire, RMB fire all claimed mounts in arc, 1–4 swap to claimed mount, Q ammo type, G fire guided ordnance at the selected attached mark, B power request, B then 2 bring mount to bear; K claim, T/Y select (§5.0).
- Controller: right stick aim (light assist), RT fire, LT fire all claimed mounts in arc, d-pad left/right swap mount, d-pad up/down ammo type, LB fire guided; View+X claim, RB and hold RB select (§5.0).
- Touch: drag to aim (stronger assist), fire and GUIDED buttons, tap mount list to claim or swap, tap target to select.

- **FT-WPN-001** Weapons shall render a full-screen turret camera from one claimed mount, with lead reticle and arc edge. (D49)
- **FT-WPN-002** Weapons shall show a disc radar inset. (D49)
- **FT-WPN-003** A player shall swap the camera between mounts they have claimed with one input. (D49)
- **FT-WPN-004** Weapons shall list every mount with ready, heat and ammo state and its claimer. (D18)
- **FT-WPN-005** Weapons shall show when the target is out of the current mount's arc, with the clock and height direction that brings it into arc. (P2, plan review NAV-6)
- **FT-WPN-006** Weapons shall select ammunition type per mount where the mount allows several. (v0.3 §5)
- **FT-WPN-007** On Easy, shared weak points and ammunition effectiveness shall appear in the turret view. (D69, P7)
- **FT-WPN-008** Weapons shall fire guided ordnance at a mark attached to a tracked contact. (P8)
- **FT-WPN-009** A mount shall hold its aim point in world space while the ship rotates, slewing at its traverse rate, and the turret camera shall roll with the ship's deck plane, keeping the ship's up at the top of the view. (plan review NAV-6, D124)

## 5.3 Engineering (E-A cutaway + pips; D50)

Left: rotatable low-poly cutaway, subsystems coloured by health and heat, hit locations, repair crews dragged to jobs. Centre: power pips per subsystem, reactor cap, overcharge row, shield power and focus tightness with a mirror of Helm's shield ring. Right: faults, repair queue, spare parts, request chips (difficulty-dependent, D69).

```
+-[ENGINEERING]--------------------------------------+
| cutaway (drag)    | PWR ENG WPN SHD SNS | FAULTS    |
|   ___[SNS]___     |     ### ##  ### #   | eng 40%   |
|  /[WPN] [SHD]\    |     ### ##  ### #   | sns 75%   |
| <  [ENG] [RX] >   |     ###     ###     | parts 6   |
|  \___________/    | rx cap ==========|  | queue:    |
| crew A->ENG B idle| shield pwr 4  focus | 1 eng ?   |
| [H harden][P prb] | tight--o--wide  4H  | 2 sns     |
| requests: [Helm: boost] [Weapons: torp power]       |
+-----------------------------------------------------+
```

- KB/M: number keys select subsystem, +/- or scroll pips, drag crews, H harden selected subsystem, P fabricate probe; Enter/Backspace accept/decline request, middle-click ping a subsystem (§5.0).
- Controller: left stick cursor with snap to subsystems, d-pad left/right cycle subsystem, LT/RT remove/add pip, right stick rotate cutaway, B dispatch nearest crew, LB harden, d-pad up fabricate probe; A select, X/Y accept/decline (§5.0).
- Touch: tap pips, drag crews, pinch-rotate cutaway, HARDEN and PROBE buttons.

- **FT-ENG-001** Engineering shall show a rotatable cutaway with subsystems coloured by health and heat and recent hit locations. (D50, D26)
- **FT-ENG-002** Engineering shall set power pips per subsystem within the reactor cap, including overcharge. (D50)
- **FT-ENG-003** Engineering shall set total shield power and focus tightness. (D16, D50)
- **FT-ENG-004** Engineering shall dispatch repair crews by dragging them to a subsystem on the cutaway. (D27)
- **FT-ENG-005** Engineering shall list faults, the repair queue and spare parts. (D27, D50)
- **FT-ENG-006** A repair job on an unknown fault shall let Engineering choose a cause; on Easy a diagnosed cause is pre-filled. (P10, D69)
- **FT-ENG-007** Engineering shall show reactor load and per-face shield strength but not threat positions beyond the radar. (P1)
- **FT-ENG-008** Engineering shall pre-harden a chosen subsystem and fabricate probes from spare parts. (P11, plan review STN-6)

## 5.4 Science (S-A sensor disc + card; D51)

Centre: orbitable 3D disc radar with confidence-sized icons and probe bubbles. Left: contacts by threat/interest. Right: contact card (class, identity, intent, weak points and resistances with confidence bars). Bottom: passive/active, Scan, Hack, scan-position mark, share buttons (when their toggles are on, D84).

```
+-[SCIENCE]---------------------------------------------+
|CONTACTS     |      .------ 12 ------.     | U3        |
|H2 frig 2.3k |    .'   U3?    H2*      '.  | class ??  |
|U3 ?    8.1k |   9  ()probe   (^)       3  | weak: 40% |
|N4 hauler    |    '.     H1*          .'   | resist:   |
|anomaly A1   |      '------ 6 -------'     |  kin ##   |
|own ship     | elev strip: U3 +40 H2 +20   | hack: --  |
|[P PASS|ACT] [E SCAN] [H HACK] [M scanpos] [share*]    |
+-------------------------------------------------------+
```

- KB/M: click contacts, drag orbit, scroll zoom, E scan, H hack, P active ping, M drop scan-position mark, 1–3 share (toggle on), B sensor power request, B then 2 to-scan-mark request.
- Controller: left stick cursor with snap-to-contact, RT scan, LT hack, d-pad up active ping, d-pad down scan-position mark, right stick orbit; A, RB and hold RB select contacts (§5.0).
- Touch: tap contacts, two-finger orbit, SCAN and HACK buttons.

Scan minigame (Scan-B silhouette alignment, D58): rotate a wireframe until it matches a sparse point cloud; cloud noise rises with range and sensor damage and falls with active ping, sensor power and Helm at the scan-position mark.

```
+-[SCAN U3 alignment]-----------------------------------+
|    . .  .   cloud           wireframe /\              |
|  .  ..  . .                         /____\  drag to   |
|   . . ..  .   axes: 2 of 3           \  /   rotate    |
| match 64%  [####----]  noise: range 8km, sensors 40%  |
+-------------------------------------------------------+
```

Hack minigame (Hack-A node route, D59): find a path from entry to the chosen subsystem before the trace bar fills; some nodes stay hidden until revealed by scans or probe coverage.

```
+-[HACK H2 -> engines]----------------------------------+
| IN o--o  ?  o--o                                      |
|       |     |  |      trace [######------]            |
|    o  o--o--o  ?      target: ENG                     |
|    ?        |         moves: arrows / tap node        |
|       o--o--o ENG                                     |
+-------------------------------------------------------+
```

- **FT-SCI-001** Science shall show an orbitable 3D disc radar with contact icons sized by detection confidence. (D51)
- **FT-SCI-002** Science shall show a contact card with class, identity, intent, weak points and resistances, each with a confidence value. (D28, D51)
- **FT-SCI-003** Science shall switch sensors between passive and active. (D51)
- **FT-SCI-004** Every scan shall require the silhouette-alignment minigame. (D17, D58)
- **FT-SCI-005** Scan point-cloud noise shall be computed on the server from range, aspect, sensor health, sensor power, active ping and probe coverage. (D58, P3, P10, P13)
- **FT-SCI-006** Every hack shall require the node-route minigame against a trace bar. (D17, D59)
- **FT-SCI-007** Hidden hack nodes shall be revealed by prior scans and probe coverage. (D59, D56)
- **FT-SCI-008** A successful hack shall apply its data-defined effect to the chosen subsystem for a limited window. (D51, P7)
- **FT-SCI-009** Science shall scan its own ship to diagnose faults of unknown cause. (P10)
- **FT-SCI-010** Science shall place a scan-position mark for a selected contact. (D58, P3)
- **FT-SCI-011** Minigame parameters shall be generated by the server from simulation state, and the server shall verify submitted solutions. (v0.3 §3, D17)
- **FT-SCI-012** Each minigame shall take 5–20 s for an average player at nominal noise, and at most 45 s for a first-time player. (station-ui §4, plan review UX-4)
- **FT-SCI-013** Both minigames shall be playable with KB/M, controller and touch. (station-ui §4)
- **FT-SCI-014** The scan minigame's rotation axes shall grow with noise, from 1 axis when clean to 3 when noisy. (plan review UX-4)
- **FT-SCI-015** A class the crew has fully scanned in this run shall start later scans pre-aligned on two axes. (plan review UX-4)
- **FT-SCI-016** Match quality above the lock threshold shall raise the confidence of the scan result. (plan review UX-4, P3)

## 5.5 Relay (world map; D52, D124)

Centre: the world map, a freely rotatable 3D map of the site's wrapping cube, centred on the ship or a selected mark, site or contact, with probe coverage bubbles, routes, hazards and all marks; it has no grid squares, altitude layers or world-fixed up (D124). Left: probes (stock, launch) and contacts by faction. Bottom: log and the inbox of marks sent by allied ships, each waiting for Accept or Decline (D82). With no Captain seated, Relay alone switches the main-screen view (D88). No NPC text.

```
+-[RELAY]-----------------------------------------------+
|PROBES 3/5   |              (centred on ship)          |
|[LAUNCH]     |       <>Alpha       probe( )            |
|CONTACTS     |             H2*                         |
|H2 hostile   |    ship->  - - - - route - -> <>Bravo   |
|N4 trade     |   hazard~~~~          <>Charlie         |
|MARKS A B C  | drag: place  Shift+drag: depth   [ROUTE]|
|log: H2 changed course   lane x N7 [L flag]            |
|INBOX: Delta from Kestrel [ACCEPT] [DECLINE] [SEND >]  |
+-------------------------------------------------------+
```

- KB/M: drag on the map to place a probe or mark, Shift+drag depth, right-drag rotate, scroll zoom, G route to selected, L flag lanes crossing friendlies, Del delete mark, N rename mark, X send selected mark to an allied ship, B fabricate-probe request, Alt+1–5 main-screen view (no Captain seated); Enter/Backspace accept/decline the oldest received mark (§5.0).
- Controller: left stick cursor plus a radial menu on hold B (probe, mark, route, flag lanes, send mark, main-screen view), triggers move the cursor nearer/farther, right stick rotate; X/Y accept/decline received mark (§5.0).
- Touch: drag to place, second finger slides depth, pinch zoom, two-finger rotate, SEND on a selected mark, ACCEPT/DECLINE in the inbox, main-screen view buttons.

- **FT-RLY-001** Relay shall show a freely rotatable 3D map of the site's wrapping cube, centred on the ship or a selected mark, site or contact, with probe coverage, routes, hazards and marks, and no grid squares, altitude layers or world-fixed up. (D52, D124)
- **FT-RLY-002** Relay shall place marks by dragging on the view plane through the map's centre and set depth along the view direction with Shift+drag. (D52, D124)
- **FT-RLY-003** Relay shall rename, attach to a contact, move and delete any mark of its ship. (D44)
- **FT-RLY-004** Relay shall launch probes to a chosen point from a finite stock. (D56)
- **FT-RLY-005** Relay shall draw routes; on Easy a route appears as a ribbon on Helm's HUD. (D52, D69)
- **FT-RLY-006** Relay shall list probes and contacts and keep a ship's log. (D52)
- **FT-RLY-007** Relay shall show no NPC dialogue text. (D52)
- **FT-RLY-008** Relay shall send a selected mark of its ship to another ship of its faction. (D82)
- **FT-RLY-009** Relay shall list received marks in an inbox and accept or decline each; only an accepted mark is shared with its crew. (D82)
- **FT-RLY-010** With no Captain seated, Relay shall switch the main-screen view. (D88)
- **FT-RLY-011** Relay shall flag lanes crossing friendlies, and Weapons shall get a warning before a shot along a flagged lane. (P8, D37)

## 5.6 Comms (new station; D53)

Comms holds all NPC text and replies, contracts, priorities, missions, opportunities, trade, upgrades and reputation. The Comms player hears NPC voices (D39). Layout: card board (D87). Missions, contracts, offers (trade, repairs, modules while docked) and hails are cards in three columns; opening a card's conversation shows it as an overlay above the board, and closing it returns to the board. A card with a conversation shows its claimer (D18).

```
+-[COMMS board]------------------ docked: Kappa  cr 1200--+
| MISSIONS         | CONTRACTS        | OFFERS + HAILS    |
| +--------------+ | +--------------+ | +---------------+ |
| | Rescue N4    | | | Escort N7    | | | ! HAIL H2     | |
| | at Bravo 9:30| | | pay 400 rep+ | | |   [answer]    | |
| +--------------+ | +--------------+ | +---------------+ |
| +--------------+ | +--------------+ | +---------------+ |
| | Scout A1 new | | | Disable H2   | | | Kappa trade   | |
| | reward 250   | | | do not kill  | | | parts 25 [me] | |
| +--------------+ | +--------------+ | +---------------+ |
| rep Kappa +12 (+/-3)   N4 -2   [Enter]accept [Bksp]decl |
+---------------------------------------------------------+

+-[COMMS board > Kappa trade  claimed: me]----------------+
|    +-----------------------------------------------+    |
|    | Station Kappa                                 |    |
|    | "We can repair you for 300."                  |    |
|    | 1 Accept   2 Haggle   3 Ask about H2          |    |
|    | 4 Close                         [Esc] board   |    |
|    | buy: parts 25/u  ammo 40/u  module HX-2 900   |    |
|    +-----------------------------------------------+    |
+---------------------------------------------------------+
```

- KB/M: click a card, or arrows then O, to open it, Tab next column, H hail the selected contact, B hold-fire request on the selected callsign, 1–4 reply in the overlay, Esc close the overlay; Enter/Backspace accept/decline the selected card, K claim its conversation, middle-click ping the card's contact or mark (§5.0).
- Controller: d-pad or left stick move between cards and columns, A open, d-pad + A pick a reply in the overlay, B close the overlay, LB hail the selected contact; X/Y accept/decline, View+X claim, View+Y hold-fire request (§5.0).
- Touch: tap a card to open it, swipe to switch column, tap a reply, tap outside or swipe down to close the overlay, long-press a card to ping.

- **FT-COM-001** Comms shall show all NPC dialogue, reply choices, contracts, missions, opportunities and priorities. (D53)
- **FT-COM-002** Comms shall hail contacts and answer hails. (D53)
- **FT-COM-003** Comms shall accept or decline contracts alone, with no co-sign. (D57)
- **FT-COM-004** Comms shall show what can be bought and sold, with prices, and shall make trades. (D68, D34)
- **FT-COM-005** Comms shall show reputation per faction and the visible range of reputation outcomes where sensible. (D34)
- **FT-COM-006** Each NPC conversation shall be claimable, and only its claimer shall hear that NPC's voice. (D18, D39)
- **FT-COM-007** Dialogue replies shall be structured choices; free text input shall not be required. (v0.3 §8)
- **FT-COM-008** Comms shall show missions, contracts, offers and hails as cards on a board, and shall open a card's conversation as an overlay above the board. (D87)
- **FT-COM-009** While the ship is docked, Comms shall buy and sell slot modules among the station's offers. (D86)

## 5.7 Captain (C-B main-screen director; D54)

The Captain's device mirrors the main screen, with view buttons, pings and read-only lists of open request chips and Comms' mission and contract cards. Information only: no ship controls. With no Captain seated, Relay switches the main-screen view (D88).

```
+-[CAPTAIN director]------------------------------------+
|  ( mirror of main screen )         | CHIPS (read only)|
|        H2[]                        | H>E boost   6s   |
|                                    | MISSIONS + CONTR.|
|  long-press ping  drag mark        | Rescue N4 9:30   |
| [FWD] [CHASE] [TACT] [TARGET H2] [STATUS]             |
+-------------------------------------------------------+
```

- KB/M: 1–5 views; click, middle-click and Shift+middle-click select, ping and mark (§5.0). Controller: left stick cursor, d-pad cycle views, A, R3 and hold R3 (§5.0). Touch: long-press ping, long-press then drag mark, buttons for views.

- **FT-CPT-001** The Captain seat shall mirror the main screen and switch its view among forward, chase, tactical, target and status. (D54, D60)
- **FT-CPT-002** The Captain shall place pings and marks. (D44, D54)
- **FT-CPT-003** The Captain shall have no command that changes ship mechanics. (D15, D23)
- **FT-CPT-004** The Captain shall see read-only lists of open request chips and of Comms' mission and contract cards. (D15, plan review COOP-10, STN-7)
- **FT-CPT-005** A Captain ping on a mission or contract card shall show that card on the main screen for 10 s or until the next ping. (D15, plan review COOP-10)

## 5.8 Main screen (M-A; D60)

Forward (or chase) view, wide disc radar along the bottom, and a callsign rail with clock and range; pings and marks drawn large. Viewers see it read-only.

```
+------------------- FULL THETA -------------------------+
|        <H1                         ^Bravo               |
|                  +           H2[]                       |
|  H1 8 low 4km | H2 4 high 2.3km | U3 11 high 8km | F1  |
| .-------------------- 12 ---------------------.        |
|9   H1*           (^)          <>Bravo  H2*     3 hull92|
| '-------------------- 6 ----------------------' shld70 |
+---------------------------------------------------------+
```

- **FT-MSC-001** The main screen shall default to the forward view with a wide disc radar and a callsign rail showing clock and range; the forward camera shall be stabilised on the ship's deck plane or the selected target (or a per-client cosmetic reference plane, never spoken or used by rules) and switch to chase while the ship is decoupled or rolls faster than 45°/s, and back to forward after 1.5 s below 30°/s. (D60, plan review NAV-9, D124, D173)
- **FT-MSC-002** The main screen shall offer forward, chase, tactical, target and status views. (D60)
- **FT-MSC-003** The main screen shall draw pings and marks. (D60, D61)
- **FT-MSC-004** Any number of viewers shall display the main screen read-only, within the 64-connection cap. (D10, D22)
- **FT-MSC-005** The main-screen view shall be switched only by the Captain when one is seated, counting the Captain's reconnect grace as seated, and only by Relay otherwise. (D54, D88, plan review STN-7)
- **FT-MSC-006** The status view shall show hull, shields, subsystem health, active objectives and alert level. (D15, D60, plan review STN-7)

## 5.9 Joint views (D67)

A joint view keeps one top bar and one disc radar; each extra station becomes a docked panel. Every control is reachable, one panel focused at a time (D95, amending D20's wording): F1/F2, hold View + LB/RB, or a tap moves the focus, the focused panel takes its station's bindings, and only the always-live set (§5.0) ignores focus. All 15 pairs have a joint view (catalogue in §3.3, D76); milestone 1 builds three of them:

```
+-[TACTICAL = HELM+WEAPONS]-----------------------------+
| <H1          +-lead   H2[] 4 high 2.3km       shield  |
|           (  reticle  )                       (ring)  |
|  compass(o)   focus [F1 COCKPIT*|F2 TURRET]           |
| MOUNTS 1RDY 2HOT 3 2/6 4 Ana                          |
| THR[####] ASSIST [F face][G track]   .-12-. 9 * * 3   |
+-------------------------------------------------------+
+-[SYSTEMS = ENG*+SCI]-F1/F2 focus----------------------+
| cutaway  PWR E W S T | .--12--. sensor  | U3 ?? 40%   |
| [SNS40]  # # # #     |9 U3? (^) 3       | [SCAN][HACK]|
| crews A B  parts 6   | '--6---'         | faults 2 ?  |
+-------------------------------------------------------+
+-[OPS = RELAY*+COMMS]-F1/F2 focus----------------------+
| PROBES 3/5 | world map  <>A  H2*  ship->  | [Rescue] |
| [LAUNCH]   |   hazard~~   - - route       | [!HAIL ] |
| MARKS A B  |                              | [Kappa ] |
+-------------------------------------------------------+
```

- **FT-JNT-001** A joint view shall show one top bar and one disc radar, present each further station as a docked panel, and route station bindings to the one focused panel. (pairs-and-combos §2, D20, D95)
- **FT-JNT-002** A station's bindings shall be the same in every view that contains it, and the always-live set shall collide with no station's bindings. (D20, D95)
- **FT-JNT-003** Milestone 1 shall provide the Tactical, Systems and Ops joint views. (D72)
- **FT-JNT-004** The 12 joint views not built in milestone 1 shall follow FT-JNT-001 and FT-JNT-002 and ship with milestone M2 (Full crew). (D75, D76)
- **FT-JNT-005** A joint view shall get the union of its stations' data; data shortcuts between its own stations shall show as if their toggles were on, and requests between them shall run as direct actions (Boost in a Helm+Engineering view overcharges at once). (plan review COOP-1)
- **FT-JNT-006** The lobby shall show a one-line hint per joint view naming the pair it makes solo. (plan review COOP-1)
- **FT-JNT-007** The always-live set (alert, ping, panel switch, Helm translation, face, all-stop; §5.0) shall work whatever panel has focus. (D95)
- **FT-JNT-008** In Tactical, Helm focus shall show the cockpit, where Helm flies and the KB/M fire buttons fire claimed mounts at the selected target; Weapons focus shall show the turret, where Weapons aims, flight assist holds attitude and Helm keeps the always-live set. (D95, plan review STN-1, UX-2)

