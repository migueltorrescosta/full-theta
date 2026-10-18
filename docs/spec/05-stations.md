# 5. Stations

Six functional stations plus the optional Captain seat and the shared main screen. Roles (owner, round 11): Helm = movement; Weapons = damage; Engineering = systems; Science = information gathering, scanning and hacking; Relay = tactical view of the universe; Comms = story of the universe; Captain = information only (D15, D23, D50–D54).

Wireframes are 16:9 sketches. A requirement below that says "on Easy" for a data shortcut means "when that shortcut's toggle is on" (§7.2, D84). Controls are listed as KB/M, controller, touch. Touch layouts for Helm and Weapons come with browser stations after milestone 1 (D8).

## 5.0 Common to every station

Top bar: ship name, hull, shields, reactor, alert level, station name(s), mission timer. Any crew station sets the alert level from the top bar (D89). Toasts top-right. Colour-blind-safe palette. The shared disc radar (§6) appears on every station (D43). Every callsign chip is clickable (select) and pingable (D61).

- **FT-STN-001** Every station shall show the common top bar. (station-ui §2)
- **FT-STN-002** Every station shall show the shared disc radar at some size. (D43)
- **FT-STN-003** Every callsign chip and mark shall be selectable by click/tap and pingable by middle-click/long-press. (D44, D61)
- **FT-STN-004** Every critical alert shall be both visual and audible on the affected stations. (v0.3 §5)
- **FT-STN-005** Every station shall be usable with KB/M and a controller; touch layouts shall exist for every station once browser stations ship. (v0.3 §2, D8)
- **FT-STN-006** UI colours shall stay distinguishable under the common forms of colour blindness. (station-ui §2)
- **FT-STN-007** Input bindings shall be rebindable and persisted per client. (v0.3 §2)
- **FT-STN-008** Any crew station shall set the ship's alert level from the top bar (KB/M: click the alert chip or Alt+A; controller: hold View and press a d-pad direction; touch: tap the alert chip); the Captain and viewers shall not. (D15, D89)

## 5.1 Helm (H-A cockpit, C toggles chase camera; D46)

Full-screen forward view; HUD with prograde/retrograde markers, target compass, off-screen arrows, route ribbon (routes toggle, D84), faint weapon-arc cones; thrust envelope and assist mode bottom-left; disc radar bottom-right; shield ring on the right edge.

```
+-[HELM]-hull 92 shld 70 rx 80-------------- ALERT RED -+
|  <H1                      ^Bravo                       |
|               .  +  .        H2[]  4 high 2.3km        |
|            (  prograde  )                     shield  |
|               '     '                         ( ring )|
|  compass (o)                                  4H sel  |
| THR [#####   ] ASSIST on      .--12--.  F face  L level|
| ROT [###     ] dV 230 m/s    9 H1* H2 3  [DOCK][JUMP]  |
+---------------------------------------'--6---'---------+
```

- KB/M: WASD translate, R/V up/down, mouse pitch/yaw, Q/E roll, Shift boost request, Space all-stop, Tab decoupled, hold F face, L level, C chase camera, numpad 1–6 shield faces, click shield-ring sector, G shield track selected, middle-click ping.
- Controller: left stick pitch/yaw, right stick strafe, triggers forward/back, bumpers roll, R3 hold face, d-pad shield faces, Y shield track, A boost request, View button chase camera.
- Touch (assist on only): left virtual stick attitude, right stick translate, throttle slider, FACE / LEVEL / SHIELD-TRACK buttons, tap shield-ring sectors.

- **FT-HLM-001** Helm shall default to a cockpit forward view with HUD, target compass, disc radar and shield ring. (D46)
- **FT-HLM-002** Helm shall toggle a chase camera with C (controller: View) without changing the HUD. (D46)
- **FT-HLM-003** The target compass shall place a dot for the selected callsign or mark: filled when ahead, hollow when behind. (D47)
- **FT-HLM-004** The cockpit shall show off-screen arrows for the selected target and pinged items. (station-ui §1.6)
- **FT-HLM-005** Holding F shall rotate the ship to face the selected target at the ship's real turn rate, through flight assist. (D47)
- **FT-HLM-006** Face assist shall work for contacts and marks, and in decoupled mode. (D47)
- **FT-HLM-007** The L key shall roll and pitch the ship onto the map's ecliptic. (D42, D77)
- **FT-HLM-008** Helm shall snap shield focus to six faces (fore, aft, port, starboard, dorsal, ventral) with one input each. (D48)
- **FT-HLM-009** Tapping a clock sector with height on the shield ring shall set shield focus to that direction. (D48)
- **FT-HLM-010** A shield-track toggle shall keep shield focus on the selected callsign as both ships move. (D48)
- **FT-HLM-011** The shield ring shall show focus direction (Helm) and focus tightness and power (Engineering) in one widget. (D16, P1)
- **FT-HLM-012** Helm shall show the thrust envelope set by Engineering and the propellant remaining. (P1, D34)
- **FT-HLM-013** Helm shall offer dock and jump controls. (D29, P5)

## 5.2 Weapons (W-B turret camera; D49)

Full-screen view from one claimed mount with lead reticle, arc edge and radar inset; swap between the player's claimed mounts. Weak-point brackets appear only when the weak-points toggle is on (D69, D84).

```
+-[WEAPONS mount 2]--------------------------------------+
|                      H2[]   weak:engine [toggle]       |
|                   .   +   .   lead                      |
|                  (  reticle )                           |
|                   '       '        arc edge ->|        |
| mount 2 beam HOT 78%  ammo --  [swap 1..4] [claim]     |
| claimed: 1 me  2 me  3 Ana  4 free       .-12-.        |
| target H2 4 high 2.3km  IFF hostile      9  *  3       |
+------------------------------------------'--6-'--------+
```

- KB/M: mouse aims, LMB fire, RMB fire all claimed mounts in arc, 1–4 swap to claimed mount, C claim/release mount, T cycle target, Y select pinged, R ammo type, middle-click ping.
- Controller: right stick aim (light assist), triggers fire, bumpers swap mount, X cycle target, Y claim, d-pad ammo type.
- Touch: drag to aim (stronger assist), fire button, tap mount list to claim or swap, tap target to select.

- **FT-WPN-001** Weapons shall render a full-screen turret camera from one claimed mount, with lead reticle and arc edge. (D49)
- **FT-WPN-002** Weapons shall show a disc radar inset. (D49)
- **FT-WPN-003** A player shall swap the camera between mounts they have claimed with one input. (D49)
- **FT-WPN-004** Weapons shall list every mount with ready, heat and ammo state and its claimer. (D18)
- **FT-WPN-005** Weapons shall show when the target is out of the current mount's arc. (P2)
- **FT-WPN-006** Weapons shall select ammunition type per mount where the mount allows several. (v0.3 §5)
- **FT-WPN-007** On Easy, shared weak points and ammunition effectiveness shall appear in the turret view. (D69, P7)

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
|                   | tight--o--wide  4H  | 2 sns     |
| requests: [Helm: boost] [Weapons: torp power]       |
+-----------------------------------------------------+
```

- KB/M: number keys select subsystem, +/- or scroll pips, drag crews, Space accept request, middle-click ping a subsystem.
- Controller: d-pad select subsystem, A/B add/remove pip, bumpers switch panel, right stick rotate cutaway, X dispatch nearest crew.
- Touch: tap pips, drag crews, pinch-rotate cutaway.

- **FT-ENG-001** Engineering shall show a rotatable cutaway with subsystems coloured by health and heat and recent hit locations. (D50, D26)
- **FT-ENG-002** Engineering shall set power pips per subsystem within the reactor cap, including overcharge. (D50)
- **FT-ENG-003** Engineering shall set total shield power and focus tightness. (D16, D50)
- **FT-ENG-004** Engineering shall dispatch repair crews by dragging them to a subsystem on the cutaway. (D27)
- **FT-ENG-005** Engineering shall list faults, the repair queue and spare parts. (D27, D50)
- **FT-ENG-006** A repair job on an unknown fault shall let Engineering choose a cause; on Easy a diagnosed cause is pre-filled. (P10, D69)
- **FT-ENG-007** Engineering shall show reactor load and per-face shield strength but not threat positions beyond the radar. (P1)

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
|[PASSIVE|ACTIVE] [SCAN] [HACK] [M scanpos] [share*]    |
+-------------------------------------------------------+
```

- KB/M: click contacts, drag orbit, scroll zoom, S scan, H hack, A active ping, M drop scan-position mark, 1–3 share (toggle on).
- Controller: stick cursor with snap-to-contact, A scan, X hack, right stick orbit, bumpers cycle contacts.
- Touch: tap contacts, two-finger orbit, SCAN and HACK buttons.

Scan minigame (Scan-B silhouette alignment, D58): rotate a wireframe until it matches a sparse point cloud; cloud noise rises with range and sensor damage and falls with active ping, sensor power and Helm at the scan-position mark.

```
+-[SCAN U3 alignment]-----------------------------------+
|    . .  .   cloud           wireframe /\              |
|  .  ..  . .                         /____\  drag to   |
|   . . ..  .                          \  /   rotate    |
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
- **FT-SCI-012** Each minigame shall take 5–20 s for an average player at nominal noise. (station-ui §4)
- **FT-SCI-013** Both minigames shall be playable with KB/M, controller and touch. (station-ui §4)

## 5.5 Relay (world map; D52)

Centre: freely rotatable world-frame 3D map on the ecliptic with grid squares, altitude stems, probe coverage bubbles, routes, hazards and all marks. Left: probes (stock, launch) and contacts by faction. Bottom: log and the inbox of marks sent by allied ships, each waiting for Accept or Decline (D82). With no Captain seated, Relay alone switches the main-screen view (D88). No NPC text.

```
+-[RELAY]-----------------------------------------------+
|PROBES 3/5   | A    B    C    D    E    F   (ecliptic) |
|[LAUNCH]     |1      <>Alpha       probe( )            |
|CONTACTS     |2            H2*                         |
|H2 hostile   |3   ship->  - - - - route - -> <>Bravo   |
|N4 trade     |4  hazard~~~~          <>Charlie up2     |
|MARKS A B C  | drag: place  Shift+drag: height  [ROUTE]|
|log: H2 changed course; probe 2 lost                   |
|INBOX: Delta from Kestrel [ACCEPT] [DECLINE] [SEND >]  |
+-------------------------------------------------------+
```

- KB/M: click/drag map to place a probe or mark, Shift+drag height, right-drag rotate, scroll zoom, R route to selected, Del delete mark, F2 rename mark, S send selected mark to an allied ship, Enter/Backspace accept/decline the oldest received mark, Alt+1–5 main-screen view (no Captain seated).
- Controller: cursor plus radial menu (probe, mark, route, send mark, main-screen view), triggers raise/lower height, right stick rotate, X/Y accept/decline received mark.
- Touch: tap to place, second finger slides height, pinch zoom, two-finger rotate, SEND on a selected mark, ACCEPT/DECLINE in the inbox, main-screen view buttons.

- **FT-RLY-001** Relay shall show a freely rotatable world-frame 3D map with grid squares, altitude stems, probe coverage, routes, hazards and marks. (D52, D42)
- **FT-RLY-002** Relay shall place marks by dragging on the ecliptic and set height with Shift+drag. (D52)
- **FT-RLY-003** Relay shall rename, attach to a contact, move and delete any mark of its ship. (D44)
- **FT-RLY-004** Relay shall launch probes to a chosen point from a finite stock. (D56)
- **FT-RLY-005** Relay shall draw routes; on Easy a route appears as a ribbon on Helm's HUD. (D52, D69)
- **FT-RLY-006** Relay shall list probes and contacts and keep a ship's log. (D52)
- **FT-RLY-007** Relay shall show no NPC dialogue text. (D52)
- **FT-RLY-008** Relay shall send a selected mark of its ship to another ship of its faction. (D82)
- **FT-RLY-009** Relay shall list received marks in an inbox and accept or decline each; only an accepted mark is shared with its crew. (D82)
- **FT-RLY-010** With no Captain seated, Relay shall switch the main-screen view. (D88)

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
| rep Kappa +12 (+/-3)   N4 -2         [A]ccept [D]ecline |
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

- KB/M: click a card or arrows + Enter to open it, Tab next column, A accept / D decline the selected card, H hail the selected contact, 1–4 reply in the overlay, Esc close the overlay, middle-click ping the card's contact or mark.
- Controller: d-pad or left stick move between cards, bumpers switch column, A open, X accept, Y decline, d-pad + A pick a reply in the overlay, B close the overlay.
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

The Captain's device mirrors the main screen, with view buttons and tap-to-ping. Information only: no ship controls. With no Captain seated, Relay switches the main-screen view (D88).

```
+-[CAPTAIN director]------------------------------------+
|  ( mirror of main screen )                            |
|        H2[]                                           |
|  tap = ping            long-press = place mark        |
| [FWD] [CHASE] [TACT] [TARGET H2] [STATUS]             |
+-------------------------------------------------------+
```

- KB/M: 1–5 views, click ping, Shift+click mark. Controller: d-pad cycle views, A ping at cursor. Touch: tap ping, buttons for views.

- **FT-CPT-001** The Captain seat shall mirror the main screen and switch its view among forward, chase, tactical, target and status. (D54, D60)
- **FT-CPT-002** The Captain shall place pings and marks. (D44, D54)
- **FT-CPT-003** The Captain shall have no command that changes ship mechanics. (D15, D23)

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

- **FT-MSC-001** The main screen shall default to the forward view with a wide disc radar and a callsign rail showing clock and range. (D60)
- **FT-MSC-002** The main screen shall offer forward, chase, tactical, target and status views. (D60)
- **FT-MSC-003** The main screen shall draw pings and marks. (D60, D61)
- **FT-MSC-004** Any number of viewers shall display the main screen read-only, within the 64-connection cap. (D10, D22)
- **FT-MSC-005** The main-screen view shall be switched only by the Captain when one is seated, and only by Relay otherwise. (D54, D88)

## 5.9 Joint views (D67)

A joint view keeps one top bar and one disc radar; each extra station becomes a docked panel switched by F1–F2 or a controller bumper. Hotkeys do not collide: Helm keeps the sticks, Weapons the mouse buttons, the rest move to panels and Ctrl/Alt chords (pairs-and-combos §2). All 15 pairs have a joint view (catalogue in §3.3, D76); milestone 1 builds three of them:

```
+-[TACTICAL = HELM+WEAPONS]-----------------------------+
| <H1          +-lead   H2[] 4 high 2.3km       shield  |
|           (  reticle  )                       (ring)  |
|  compass(o)        view [COCKPIT|TURRET]              |
| MOUNTS 1RDY 2HOT 3 2/6 4 Ana                          |
| THR[####] ASSIST [F face][G track]   .-12-. 9 * * 3   |
+-------------------------------------------------------+
+-[SYSTEMS = ENG+SCI]-----------------------------------+
| cutaway  PWR E W S T | .--12--. sensor  | U3 ?? 40%   |
| [SNS40]  # # # #     |9 U3? (^) 3       | [SCAN][HACK]|
| crews A B  parts 6   | '--6---'         | faults 2 ?  |
+-------------------------------------------------------+
+-[OPS = RELAY+COMMS]-----------------------------------+
| PROBES 3/5 | world map  <>A  H2*  ship->  | [Rescue] |
| [LAUNCH]   |   hazard~~   - - route       | [!HAIL ] |
| MARKS A B  |                              | [Kappa ] |
+-------------------------------------------------------+
```

- **FT-JNT-001** A joint view shall show one top bar and one disc radar and present each further station as a docked panel. (pairs-and-combos §2, D20)
- **FT-JNT-002** Hotkeys within a joint view shall not collide. (D20)
- **FT-JNT-003** Milestone 1 shall provide the Tactical, Systems and Ops joint views. (D72)
- **FT-JNT-004** The 12 joint views not built in milestone 1 shall follow FT-JNT-001 and FT-JNT-002 and ship with milestone M2 (Full crew). (D75, D76)
