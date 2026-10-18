# Full Theta: station UI and 3D spatial language

Status: proposal for the owner. Binding inputs: decisions.md (D10–D29), spec sections 4–6, emptyepsilon.md section 4. Wireframes are 16:9 sketches, at most 12 lines by 60 characters. Questions for the owner are in section 5; each option there has a preview where a picture helps.

## 0. Precedents (what we borrow and what we avoid)

| Game | 3D handling | Lesson for Full Theta |
|---|---|---|
| EmptyEpsilon | Flat 2D world, radar from above, no elevation | Readable and teachable, but it dodges the 3D problem we must solve (D29). |
| Artemis SBS | Mostly flat map, "very limited elevation"; Helm/Weapons can pick the main-screen view (chase or out-the-window) | Main-screen view switching is a cheap, loved feature; flatness is what made its callouts easy. |
| Space Nerds in Space | Fully 3D; Navigation, Weapons, Science screens each get their own 3D view; players report steering "by the window" rather than the nav display | 3D works in a bridge sim, but a nav display that can't be read at a glance gets ignored. Make the shared radar the first thing a player looks at. |
| Elite Dangerous | Ship-relative 3D scanner: ellipse = ship's plane, contacts as blips with elevation stems; solid/hollow blips for above/below; target "compass" dot (filled = ahead, hollow = behind) | The best-known 3D radar. Known weakness: stems hide horizontal distance (players asked for arcs). Keep stems, add range rings and an optional side view. |
| Homeworld | Move disc on a plane, hold Shift and drag to set height | Separating "where on the plane" from "how high" is the trick that makes 3D placement usable with a mouse. Use it for marks and waypoints. |
| Star Trek | "Bearing 045 mark 20": first angle in the ship's plane, second above/below; 0 mark 0 = dead ahead for relative bearings | Familiar, sayable, precise. But the numbers go stale as soon as the ship turns. Keep it as the precise layer, not the default. |
| Fighter pilots / flight sims | Clock code ("bandit 4 o'clock high"), BRAA calls, and "bullseye": a pre-agreed named point everyone references | Clock + high/low is the fastest spoken 3D direction. Bullseye is the precedent for shared named marks that survive the ship turning. |
| X-Wing / FreeSpace / Elite | Target brackets, off-screen arrows, lead indicators | Standard HUD vocabulary; every pointing aid should work off screen. |
| PULSAR, Starship Horizons, Objects in Space | Role screens, mostly 2D sensor maps; Starship Horizons runs stations in a browser | Confirms the browser-station model (D5, D8); no strong 3D callout conventions to copy. |

Sources consulted: Memory Alpha "Bearing" (memory-alpha.fandom.com/wiki/Bearing); Frontier forum threads on the Elite scanner stems (forums.frontier.co.uk); SNIS project pages (flathub.org, forum.freegamedev.net); Artemis reviews (pcgamer.com, callapple.org); Homeworld controls (springrts.com forum, gamesbeat.com interview); starshiphorizons.com/pedia; PULSAR Steam page.

## 1. Cross-station 3D spatial language

### 1.1 The problem

In 6DOF (D24) there is no natural "up", the ship rotates constantly, and five people in one room must agree in under two seconds on which contact or direction they mean. Numbers like "045 mark 20" are precise but stale after a one-second roll. Words like "that one" only work when everyone sees the same picture. The language has to work for voice, for the screen, and for the hands (Helm turning, Helm facing shields at a threat, D16).

The design principle behind all three alternatives: **players should talk about things, not angles.** Give every contact and every point of interest a short shared name, and make every UI element accept that name. Angles are only needed for empty space, and empty space can be named too (marks).

### 1.2 Alternative A (Recommended): "Callsign, clock, mark"

Three layers, coarse to precise, identical on every station:

1. **Callsigns.** Every contact gets a short name the moment it's detected, coloured by known allegiance: `H1` hostile, `U2` unknown, `F3` friendly, `N4` neutral, player ships by ship name. The number never changes: when Science identifies `U2` as hostile it becomes `H2`, so people keep tracking it. Callsigns are per faction (D21): each player ship's crew sees its own set.
2. **Clock and height (ship-relative, spoken).** `12` = bow, `3` = starboard, `6` = stern, `9` = port, measured in the ship's deck plane. Height words: `level` (within ±15°), `high`/`low` (15°–60°), `overhead`/`under` (over 60°). Range bands: `close` (under 1 km), `mid`, `far`. A contact chip always reads like the callout: `H2 · 4 high · 2.3 km ▲closing`.
3. **Marks (world-anchored, persistent).** Named points in space, NATO alphabet (`Alpha`…`Hotel`), shown on every radar, HUD and map, as a diamond with a stem. A mark can be free (fixed in world space) or attached to a contact ("Mark Charlie on H4's last known position"). Marks are the "bullseye" of fighter-pilot comms: "Two hostiles near Bravo" stays true however the ship turns.

Precise layer, on hover or long-press only: Trek-style **bearing/mark** in the ship frame (`bearing 120 mark +35`, bearing 000–359 clockwise from the bow in the deck plane, mark signed −90…+90; no mod-360 wrap). Relay's map also shows world grid squares for free-space marks (`grid D4, up 2`).

Mapping callouts to UI (the key part):

| Callout | What the listener does |
|---|---|
| "Helm, face H2" | Helm selects H2 (click its chip, or say nothing and press `Face selected`), holds `F`: flight assist turns the nose onto it. |
| "Shields to H2" / "shields 4 high" | Helm presses `Shield track selected`, or taps the 4-high sector on the shield ring (D16). |
| "Weapons, H2 is at 4 high" | Weapons' radar and gunnery view show H2 bracketed; `T` cycles to it, or click the chip. |
| "Bring us to Bravo" | Helm selects Bravo (marks are selectable like contacts), autopilot or manual using the HUD compass. |
| "Science, what's U3?" | Science selects U3 from the list; same callsign everywhere. |
| "Look here" (any station) | **Ping**: middle-click or long-press any contact, mark or radar point. It pulses for 3 s on every station's radar and on the main screen, with a short chime. Pings replace pointing a finger at a screen. |

Why recommended: callsigns and marks are frame-independent, so the crew rarely needs angles. Clock code is the fastest spoken 3D direction and maps one-to-one onto the radar disc. Numbers remain available for players who enjoy Trek-speak.

### 1.3 Alternative B: "Bearing and mark first" (Trek)

All UI expresses directions as ship-relative `bearing/mark` numbers; a heading tape on Helm and a mark ladder (like an aircraft pitch ladder). Helm types or dials "045 mark 20" to turn. Precise and flavourful; teaches well in a club. Weakness: numbers go stale as the ship turns, they're slow to say under fire, and two numbers per contact is heavy on a busy radar.

### 1.4 Alternative C: "World grid" (strategy-game frame)

Every encounter has a fixed galactic plane (ecliptic) with a lettered/numbered grid and altitude layers (`D4 up 2`, `F7 down 1`). All radars are world-aligned, not ship-aligned. Stable for every ship and every station, good for PvP coordination across 6 ships (D11). Weakness: "what's in front of me?" needs mental rotation; Helm and Weapons constantly translate world to ship frame, which is exactly the hard 3D step we want the UI to do for them.

### 1.5 Shared radar visual (used on every station)

Recommended: the **ship-relative disc radar** (Elite lineage), the same widget everywhere, at different sizes:

```
        .-----------  12  -----------.
     .'      F1 o                      '.
   9|    H1 *                 H2 *      |3
    |      |       ( ^ )        |       |
     '.    .        ship        :     .'
        '-----------  6  ------------'
  * above (solid, stem up)   o below (hollow, stem down)
  <> mark   range rings 1/3/10 km   clock ticks every 30deg
```

- Disc = ship's deck plane; clock numbers around the rim match callouts.
- Each blip has a stem to the disc: solid blip with stem going up = above, hollow = below (Elite convention). Stem foot sits on the disc at the contact's horizontal position, so range is read at the foot; a range ring is drawn through the foot of the selected contact to fix the known stem weakness.
- Disc tilts and can be orbited on large views (Science, Relay); on small views (Helm, Weapons minimap) the camera angle is fixed so the shape is learnt once.
- Optional **side strip** (toggle `B`): a 1-D elevation bar showing every contact's mark angle, for players who struggle with stems.
- World-frame variant for Relay and Captain maps: the same disc drawn on the encounter's ecliptic instead of the deck plane, with the ship shown as an arrow and its deck plane as a faint tilted ring. A `Level` command on Helm rolls/pitches the ship onto the ecliptic, so in calm moments both frames coincide and the two maps look the same.

### 1.6 Pointing the ship and the shields (Helm)

- **Target compass** (Elite lineage) on the Helm HUD: a small circle with a dot for the selected callsign or mark. Dot position = where it is relative to the nose; filled = ahead, hollow = behind. Off-screen arrows on the cockpit edge too.
- **Face assist:** hold `F` (controller: click right stick) and flight assist rotates the ship to put the selected target at the nose at the ship's real turn rate (no cheating, spec 5). Release to take over. Works for contacts and marks. Decoupled mode (D24) also allows "face" while drifting, the classic strafing run.
- **Shield facing (D16):** shields have one focus direction on a sphere. Helm sets it three ways: snap to the six faces (fore/aft/port/starboard/dorsal/ventral, numpad or d-pad), tap a clock sector on the shield ring (clock + high/low, so "shields 4 high" is one tap), or `Shield track selected` (keeps focus on a callsign as both ships move). Engineering sets total shield power and how tight the focus is (spread vs. concentrated); the ring shows both.

## 2. Station layouts

Common to all stations: top bar (ship name, hull, shields, reactor, alert level, station name(s), mission timer); toasts at top-right; colour-blind-safe palette; every critical alert both visual and audio; the shared disc radar somewhere on every screen; every callsign chip clickable (select) and pingable (middle-click / long-press).

Controls are listed as KB/M | controller | touch.

### 2.1 Helm

**H-A Cockpit + compass + disc (Recommended).** Full-screen forward view; HUD with prograde/retrograde markers, target compass, off-screen arrows, Relay route ribbon, weapon-arc hints (from Weapons' mounts) as faint cones; bottom-left thrust envelope (power-limited by Engineering) and assist mode; bottom-right disc radar; right edge shield ring.

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

Rationale: Helm sees what the ship faces, and the compass plus face assist make "face H2" a one-key action.

- KB/M: WASD translate, R/V up/down, mouse pitch/yaw, Q/E roll, Shift boost, Space all-stop, Tab decoupled, hold F face, L level, numpad 1–6 shield faces, G shield track, middle-click ping.
- Controller: left stick pitch/yaw, right stick strafe, triggers forward/back, bumpers roll, R3 hold face, d-pad shield faces, Y shield track, A boost.
- Touch (assist on only): left virtual stick attitude, right stick translate, throttle slider, big FACE / LEVEL / SHIELD-TRACK buttons, tap shield ring sectors.

**H-B Chase camera.** Third-person camera behind and above the ship; same HUD. Better awareness of what's above/below and of the ship's own orientation; weaker for precise docking. Toggle `C` between H-A and H-B in any case.

```
+-[HELM chase]-------------------------------------------+
|                 H1*                     H2[] 4 high     |
|                   \                                     |
|                 _/^\_     ship seen from behind         |
|                <_____>    deck-plane ring drawn round it|
|               ( ring  )                                 |
| THR [#####  ]  compass(o)        .--12--.  shield ring  |
+---------------------------------'--6---'---------------+
```

**H-C Split cockpit + tactical.** Cockpit top 65 %, a wide tilted disc radar bottom 35 % with marks, route and the elevation side strip. For navigation-heavy missions and touch screens.

```
+-[HELM split]-------------------------------------------+
|                 cockpit view (HUD reduced)              |
|            +       H2[]                ^Bravo           |
|--------------------------------------------------------|
|  .------------------ 12 -------------------.  elev    |
| 9   H1*        (^)           <>Bravo   H2*  3  |  H2   |
|  '------------------- 6 -------------------'   |  H1   |
| THR [####  ] ASSIST  [FACE] [LEVEL] [SHIELD TRACK]     |
+--------------------------------------------------------+
```

### 2.2 Weapons

**W-A Gunnery orbit + mount panel (Recommended).** Third-person orbit camera that looks along the aim direction from behind the ship (D25 gunnery view): mount cones drawn from their real positions, lead reticle, Science's weak-point markers on the target; left: mount list with claim locks (D18), heat, ammo, ready; right: target card (callsign, clock, IFF from Relay, shield facing of the target, priority from Captain); bottom-right: disc radar. Views: gunnery, target-lock (camera frames ship and target), per-mount.

```
+-[WEAPONS]---------------------------- target H2 -------+
|MOUNTS         |        .  cone 2          | H2 frigate  |
|1 beam  RDY [me]|      .'  +-lead          | 4 high 2.3km|
|2 beam  HOT [Ana]|   _/^\_   (o) H2        | shld: fore  |
|3 torp  2/6     |  <_____>    weak:engine | prio: 1     |
|4 PD    auto?no |                          | IFF hostile |
|[group1][group2]|  view: GUN | LOCK | MNT  | .-12-. disc |
|               |  out of arc: turn 4 high | 9 * *3      |
+----------------+---------------------------+-'-6-'------+
```

Rationale: aiming is in 3D but the camera keeps the ship in frame, so "out of arc: turn 4 high" can be called to Helm directly from what Weapons sees.

- KB/M: mouse aims, LMB group 1, RMB group 2, 1–4 select group, T cycle targets, Y select pinged, R reload type, V view, C claim mount.
- Controller: right stick aim (light aim assist, D25), left stick orbits camera, triggers fire, d-pad groups, X cycle target.
- Touch: tap target to select, drag to aim (assist stronger), fire buttons per group, tap mount to claim.

**W-B Turret camera.** Full-screen view from one claimed mount; most immersive, best for 2 players sharing Weapons (each in their own turret), weakest awareness. Disc radar inset.

```
+-[WEAPONS mount 2]--------------------------------------+
|                      H2[]                               |
|                   .   +   .   lead                      |
|                  (  reticle )                           |
|                   '       '        arc edge ->|        |
| mount 2 beam HOT 78%   [swap mount 1..4]     .-12-.    |
|                                             9  *  3    |
+---------------------------------------------'--6-'-----+
```

**W-C Tactical disc + inset.** Large tilted disc radar with lead markers and arc wedges, a small gunnery inset for final aim; best touch fit, closest to EE.

```
+-[WEAPONS tactical]-------------------------------------+
|      .----------------- 12 ------------------.         |
|    .'   arc1 \      H2*->lead   / arc2         '.       |
|   9    H1*    \       (^)      /                3      |
|    '.                                          .'      |
|      '----------------- 6 -------------------'         |
| MOUNTS 1 RDY 2 HOT 3 2/6 | [gunnery inset] | H2 card   |
+--------------------------------------------------------+
```

### 2.3 Engineering

**E-A Cutaway + pips (Recommended).** Left: rotatable low-poly ship cutaway with subsystems coloured by health and heat, damage hit points (D26), repair crews as tokens dragged to jobs (D27); centre: power pip columns per system, reactor cap, overcharge row; shield allocation (total power, focus tightness) with a small shield ring mirroring Helm's facing; right: faults, repair queue, spare parts, request chips from other stations ("Helm requests boost").

```
+-[ENGINEERING]--------------------------------------+
| cutaway (drag)    | PWR ENG WPN SHD SNS | FAULTS    |
|   ___[SNS]___     |     ### ##  ### #   | eng 40%   |
|  /[WPN] [SHD]\    |     ### ##  ### #   | sns 75%   |
| <  [ENG] [RX] >   |     ###     ###     | parts 6   |
|  \___________/    | rx cap ==========|  | queue:    |
| crew A->ENG B idle| shield pwr 4  focus | 1 eng     |
|                   | tight--o--wide  4H  | 2 sns     |
| requests: [Helm: boost] [Weapons: torp power]       |
+-----------------------------------------------------+
```

Rationale: damage is located on the hull (D26) and repairs are physical (D27), so the cutaway is the main view; pips work on every input type.

- KB/M: number keys select system, +/- or scroll pips, drag crews, Space accept request, middle-click ping a subsystem to Science ("diagnose this").
- Controller: d-pad select system, A/B add/remove pip, bumpers switch panel, right stick rotates cutaway, X dispatch nearest crew.
- Touch: tap pips, drag crews, pinch-rotate cutaway: the best touch station.

**E-B Slider rows (EE-like).** Rows of power 0–300 % and coolant sliders per system, small cutaway. Finer control, less spatial; familiar to EE players.

```
+-[ENGINEERING sliders]---------------------------------+
| SYSTEM   PWR 0..300%        COOL      HEALTH  HEAT   |
| Engines  [=======o----]     [==o-]    80%     ##     |
| Weapons  [=====o------]     [=o--]    100%    #      |
| Shields  [=========o--]     [===o]    55%     ###    |
| Sensors  [===o--------]     [o---]    40%     #      |
| [mini cutaway] crews: A eng  B idle   parts 6         |
+------------------------------------------------------+
```

**E-C Cutaway full-screen + radial.** The ship fills the screen; tap a subsystem for a radial menu (power +/-, repair, vent). Most diegetic, slower to scan totals.

```
+-[ENGINEERING ship]------------------------------------+
|               ____[SNS 40%]____                       |
|           .-'  (+pwr)(-pwr)    '-.                    |
|         <  [WPN]   (repair)  [SHD] >   rx 80%  heat ##|
|           '-.  [ENG]  [RX]    .-'      parts 6        |
|               '-------------'                         |
| crews: A->ENG  B idle    requests: [Helm boost]       |
+------------------------------------------------------+
```

### 2.4 Science

**S-A Sensor sphere + card (Recommended).** Centre: orbitable 3D disc radar (the shared widget at full size) with confidence-sized icons and Relay's probe bubbles; left: contact list sorted by threat/interest; right: contact card (class, identity, intent, weak points and resistances with confidence bars, D28); bottom: scan controls (passive/active, scan button starting the minigame, "share to" Weapons / Helm / Relay). Shows "best scan position" as a mark Helm can face.

```
+-[SCIENCE]---------------------------------------------+
|CONTACTS     |      .------ 12 ------.     | U3        |
|H2 frig 2.3k |    .'   U3?    H2*      '.  | class ??  |
|U3 ?    8.1k |   9  ()probe   (^)       3  | weak: 40% |
|N4 hauler    |    '.     H1*          .'   | resist:   |
|anomaly A1   |      '------ 6 -------'     |  kin ##   |
|             | elev strip: U3 +40 H2 +20   |  nrg #    |
| [PASSIVE|ACTIVE]  [SCAN U3]  share: [WPN][HELM][RLY] |
+-------------------------------------------------------+
```

Rationale: Science is the station that most needs to read 3D, so it gets the biggest, orbitable copy of the radar everyone else learns.

- KB/M: click contacts, drag orbit, scroll zoom, S scan, A active ping, 1–3 share to station, M drop "scan position" mark.
- Controller: stick cursor with snap-to-contact, A scan, right stick orbit, bumpers cycle contacts.
- Touch: tap contacts, two-finger orbit, big SCAN button.

**S-B Flat radar with stems (EE-like).** Top-down 2D long-range radar with elevation numbers next to blips, no orbit. Simpler and readable on small tablets; weaker 3D understanding.

```
+-[SCIENCE flat]----------------------------------------+
|              N                    | U3 unknown        |
|        U3(+40)       H2(+20)      | [SCAN]            |
|   W          (^)            E     | weak:  ??         |
|        H1(-10)                    | resist: ??        |
|              S                    | share [WPN][HELM] |
+-------------------------------------------------------+
```

**S-C Analysis-first.** The scan/analysis panel dominates (spectrum, database, diagnostics with Engineering); radar is a small inset. For puzzle-heavy missions.

```
+-[SCIENCE analysis]------------------------------------+
| U3 spectrum  ~~^~~~^^~~~~^~~   match 62%   [ANALYSE]  |
| database: "Kraylor raider, variant?"                 |
| weak: engines (60%)  resist: kinetic high            |
| eng diagnostics: [sensor fault 3 - unknown cause]    |
|                                      .-12-. inset    |
|                                      9 * *3          |
+-------------------------------------------------------+
```

### 2.5 Relay

**R-A World map + marks + comms (Recommended).** Centre: world-frame 3D map on the ecliptic with grid squares, altitude stems, probe coverage bubbles, routes, hazards, all marks; Relay owns marks (create, rename, attach, delete) and routes (sent to Helm's ribbon); right: comms (channel, NPC text, reply choices, contracts); left: probes (stock, launch), contacts by faction/intent, reputation/credits; bottom: log.

```
+-[RELAY]-----------------------------------------------+
|PROBES 3/5   | A  B  C  D  E  F  (ecliptic)| COMMS    |
|[LAUNCH]     |1      <>Alpha               | Station K|
|CONTACTS     |2   ( probe )    H2*         | "Dock?"  |
|H2 hostile   |3        ship->   - - -route | 1 accept |
|N4 trade     |4  hazard~~~      <>Bravo up2| 2 haggle |
|MARKS A B C  | drag: place  Shift+drag: up/down       |
|log: H2 hailed us; contract offered                    |
+-------------------------------------------------------+
```

Rationale: Relay is the keeper of the shared world-frame vocabulary; marks are placed Homeworld-style (drag on the plane, Shift+drag for height).

- KB/M: click/drag map to place probe or mark, Shift+drag height, right-drag orbit, 1–4 dialogue choices, R route to selected.
- Controller: cursor + radial menu (probe, mark, route), triggers raise/lower height.
- Touch: tap to place, second finger slides height, pinch zoom: excellent fit.

**R-B Comms-dominant.** Comms and contracts take two thirds; map small. For negotiation missions.

```
+-[RELAY comms]-----------------------------------------+
| CHANNEL: Station Kappa        | map inset            |
| "We can repair you for 300."  |  <>A   ship   H2*    |
| 1 Accept   2 Haggle (rep 40)  |                      |
| 3 Ask about H2    4 Close     | probes 3/5 [LAUNCH]  |
| contracts: [escort N4 +500]   | marks A B C          |
+-------------------------------------------------------+
```

**R-C Tabs.** Map tab and Comms tab, one small screen (phone). Hardest to multitask.

```
+-[RELAY]---[ MAP ]--[ COMMS ]--------------------------+
|  ( full-screen map or full-screen comms )            |
|  badge on COMMS tab when a hail arrives              |
+-------------------------------------------------------+
```

### 2.6 Captain (information only, D15/D23)

Captain cannot control ship mechanics. Captain sees everything the crew knows (per difficulty, D14), controls the main screen, and may place pings and marks (communication, not control; see question 4).

**C-A Overview dashboard (Recommended).** Centre: world-frame strategic map (same as Relay's, read-only except marks/pings); top: mission objectives and branches; right: crew status chips per station (who's seated, alerts, pending requests); bottom: main-screen view selector.

```
+-[CAPTAIN]---------------------------------------------+
| OBJ: escort N4 to Bravo (2/3)  branch: H2 hails?      |
|   strategic map (world frame)        | HELM  ok       |
|     <>Alpha     N4o     ship->       | WPN   2 HOT    |
|          H1*      H2*   <>Bravo      | ENG   sns 40%  |
|                                      | SCI   scanning |
|   [ping] [mark]                      | RLY   hail in  |
| MAIN SCREEN: [FWD] [CHASE] [TACT] [TARGET] [STATUS]   |
+-------------------------------------------------------+
```

Rationale: everything a captain needs to give orders by voice, nothing that could replace a crew member's hands.

- KB/M and touch both good; controller via radial menus (ping, mark, main screen view).

**C-B Main-screen director.** The Captain's device mirrors the main screen with view buttons and a ping cursor; minimal extra info. Best for a captain standing in front of the TV.

```
+-[CAPTAIN director]------------------------------------+
|  ( mirror of main screen )                            |
|        H2[]                                           |
|  tap = ping                                          |
| [FWD] [CHASE] [TACT] [TARGET H2] [STATUS] [COMMS]     |
+-------------------------------------------------------+
```

**C-C Overlay tab.** No separate seat: a Captain tab on any station's device. Useful for a crew of 5 that wants a captain without a sixth player.

```
+-[WEAPONS] .............................. [CAPTAIN tab] +
|  (normal Weapons layout; Captain tab slides over 40%) |
+-------------------------------------------------------+
```

### 2.7 Shared main screen

Controlled by the Captain, or by any crew station through a small menu when no Captain is seated (D15). Viewers (D10/D22) see it read-only.

**M-A Forward view + radar strip + callsign rail (Recommended).** Big forward or chase view, a wide disc radar along the bottom, and a rail of callsign chips with clock and range; pings and marks are drawn large. The room's common reference: everyone can look up and see "H2, 4 high".

```
+------------------- FULL THETA -------------------------+
|        <H1                         ^Bravo               |
|                  +           H2[]                       |
|                                                         |
|  H1 8 low 4km | H2 4 high 2.3km | U3 11 high 8km | F1  |
| .-------------------- 12 ---------------------.        |
|9   H1*           (^)          <>Bravo  H2*     3 hull92|
| '-------------------- 6 ----------------------' shld70 |
+---------------------------------------------------------+
```

Rationale: a shared big screen is how same-room crews agree on 3D; showing callsign + clock under the view turns every glance into a usable callout.

**M-B Cinematic.** Auto-framing external camera on the action (ship and selected target); minimal HUD. Great for viewers, poor for coordination.

```
+--------------------------------------------------------+
|        _/^\_  ->  ->  ->        H2                      |
|       <_____>                  (target)                 |
|                    cinematic, auto-framed               |
+--------------------------------------------------------+
```

**M-C Tactical.** Full-screen orbitable world map with all contacts, marks and routes. Best for planning between fights.

```
+--------------------------------------------------------+
|  A    B    C    D    E    F     (ecliptic grid)         |
|      <>Alpha       H1*        H2*                       |
|           ship->  - - - - - -> <>Bravo                  |
+--------------------------------------------------------+
```

Controls: Captain / station menu picks the view; a Captain on controller uses the d-pad to cycle views.

## 3. Curated station combos (D19, D20)

Functional stations to cover: Helm (H), Weapons (W), Engineering (E), Science (S), Relay (R). Captain is optional and never counts. Each combo keeps every control of its stations (D20); combos are layouts, not automation. Two players may still share one seat or combo (D10/D18).

Recommended set (several combos per size where useful; the lobby only offers sets that cover all five):

| Crew | Seats | Notes |
|---|---|---|
| 5 | H · W · E · S · R | One each; optional Captain as a 6th seat or tab (C-C). |
| 4 | H · W · E · **Ops** (S+R) | Science and Relay both read the big map; merges cleanly. Alt: **Tactical** (H+W) · E · S · R. |
| 3 | **Tactical** (H+W) · E · **Ops** (S+R) | EE's classic split. Alt: H · **Gunnery+Sensors** (W+S) · **Ship Ops** (E+R). |
| 2 | **Flight** (H+W) · **Systems** (E+S+R) | Pilot flies and shoots; the other runs the ship and the world. |
| 1 | **Solo Commander** (H+W+E+S+R) | Cockpit with hot-swappable side panels and pause-free quick actions. |

Combo rules: a combo screen keeps one shared disc radar and one top bar; extra stations become docked panels or tabs; hotkeys of the merged stations don't collide (Helm keeps the sticks, Weapons the mouse buttons, the rest move to panels and Ctrl/Alt chords).

**Flight (H+W), 2-player seat 1.** Cockpit view; nose gun groups fire along fixed forward mounts; turreted mounts fire at the selected target via the lead reticle; mount panel shrinks to a strip.

```
+-[FLIGHT = HELM+WEAPONS]-------------------------------+
| <H1          +-lead   H2[] 4 high 2.3km  prio1        |
|           (  reticle  )                      shield   |
|  compass(o)                                  (ring)   |
| MOUNTS 1RDY 2HOT 3 2/6 4PD | view [COCKPIT|GUNNERY]   |
| THR[#### ] ASSIST on  [F face][G shld track] .-12-.   |
| ROT[###  ] dV 230       LMB grp1 RMB grp2   9 * * 3   |
+-------------------------------------------------------+
```

**Systems (E+S+R), 2-player seat 2.** Map in the centre (Science sphere and Relay map are one widget with a frame toggle); left cutaway + pips; right contact card / comms switch.

```
+-[SYSTEMS = ENG+SCI+RELAY]-----------------------------+
|cutaway  PWR   | frame [SHIP|WORLD]       |[CARD|COMMS]|
| [SNS40] E W S | .------ 12 ------.       | U3 ??      |
| [ENG]   # # # |9  U3? (^)  H2*   3 <>A   | [SCAN U3]  |
| crews A B     | '------ 6 -------' probe | weak 40%   |
| parts 6       | [PASSIVE|ACTIVE] [LAUNCH]| hail: K?   |
| req: Helm boost  | log: H2 hailed us                  |
+-------------------------------------------------------+
```

**Solo Commander (all five).** Flight seat plus one swappable right panel (E, S or R), switched by F1–F3 or a controller bumper; scans and hacks keep their minigames but get a "hold to continue" that lets the player look up.

```
+-[SOLO]----------------------------------- [E][S][R] --+
| <H1          +-lead   H2[] 4 high      | ENG          |
|           (  reticle  )                | ### ## ####  |
|  compass(o)                            | crews A B    |
| MOUNTS 1RDY 2HOT 3 2/6                 | req/faults   |
| THR[####] ASSIST [F face][G shld]      |--------------|
| .--12--.  alerts: SNS 40% / hail K     | toasts jump  |
| 9 * * 3   (click toast = open panel)   | to panel     |
+-------------------------------------------------------+
```

Design note for solo: toasts are actionable (click opens the right panel at the right item), so one player can respond to a shield-40 % alert without hunting.

## 4. Mandatory minigames (D17)

Both minigames are mandatory, driven by server state (sensor or system damage, range, ship class) and never secretly rigged (spec 5). Both must work on KB/M, controller and touch and take 5–20 s.

### 4.1 Scan

**Scan-A Signal tuning (EE lineage).** Two or three waveform sliders to match a target trace; sliders added with distance and sensor damage; noise from Engineering's sensor power. Familiar, accessible, works on every input. Doesn't teach 3D.

```
+-[SCAN U3]---------------------------------------------+
| target ~~^~~^^~~~~^~~      yours ~~^~^~~~~^^~~        |
| freq   [-----o------]                                 |
| amp    [---o--------]      match 72% -> 90% to lock   |
| phase  [--------o---]      sensor pwr 3 pips          |
+-------------------------------------------------------+
```

**Scan-B Silhouette alignment (3D, Recommended).** The contact's sensor return is a sparse point cloud; rotate a wireframe (mouse drag / stick / two-finger) until it lines up with the cloud. Cloud density depends on range, sensor health and active ping; Helm parking the ship at Science's "scan position" mark reduces noise (Helm + Science pair). Trains the same 3D reading the radar needs.

```
+-[SCAN U3 alignment]-----------------------------------+
|    . .  .   cloud           wireframe /\              |
|  .  ..  . .                         /____\  drag to   |
|   . . ..  .                          \  /   rotate    |
| match 64%  [####----]  noise: range 8km, sensors 40%  |
| tip: Helm to <>ScanPos cuts noise                     |
+-------------------------------------------------------+
```

Rationale: same interaction cost as tuning, but it builds the crew's 3D intuition and creates a natural Helm call.

### 4.2 Hack

**Hack-A Node route (Recommended).** A small grid of nodes (the target's subsystems); find a path from entry to the chosen subsystem before the trace bar fills; some nodes hidden until probed. Grid size from target class; Science's scan reveals some nodes in advance (Science + Relay/Weapons tie-in). Discrete moves, so it plays well on controller and touch.

```
+-[HACK H2 -> engines]----------------------------------+
| IN o--o  ?  o--o                                      |
|       |     |  |      trace [######------]            |
|    o  o--o--o  ?      target: ENG (weak point known)  |
|    ?        |         moves: arrows / tap node        |
|       o--o--o ENG                                     |
+-------------------------------------------------------+
```

**Hack-B Tumbler rings.** Concentric rings with gaps; rotate each until all gaps line up, rings counter-rotate with each other. Quick and tactile, best on touch and controller sticks; less depth and no scan synergy.

```
+-[HACK H2 tumbler]-------------------------------------+
|           .-- ring 3 --.                              |
|         .'  .-ring2-.   '.     align gaps ->          |
|        |   ( ring1 )  >  |    trace [####------]     |
|         '.  '-----'    .'     Q/E ring, A/D rotate    |
|           '-----------'                               |
+-------------------------------------------------------+
```

## 5. Decision questions for the owner

Ordered by importance. Each option has a one-line trade-off; one is Recommended. Previews follow each question.

### Q1. Cross-station 3D spatial language

- **A. Callsign, clock, mark (Recommended):** names for contacts and points, clock + high/low for spoken direction, bearing/mark on hover. Fast and frame-proof; three things to learn.
- **B. Bearing/mark first (Trek):** numbers everywhere, Helm dials headings. Precise and flavourful; numbers go stale as the ship turns.
- **C. World grid:** fixed ecliptic grid squares and altitude layers. Stable across ships and PvP; Helm/Weapons must mentally rotate.
- **D. Clock only:** no numbers, no marks. Simplest; can't name empty space or coordinate across ships.

```
A  H2 · 4 high · 2.3km   <>Bravo   (hover: 120 mk +35)
B  H2 · 120 mark +35 · 2.3km   heading tape 090|120|150
C  H2 · grid D4 up 2 · 2.3km   radar world-aligned
D  H2 · 4 o'clock high         (no marks, no numbers)
```

### Q2. Reference frame of the radar

- **A. Ship frame on crew stations, world frame on Relay/Captain maps, plus Helm `Level` (Recommended):** what's ahead is always up on Helm/Weapons; Relay keeps a stable map; `Level` makes them coincide. Two frames to explain.
- **B. Ship frame everywhere:** one frame, simplest; maps spin as the ship rolls, hard to plan routes.
- **C. World frame everywhere:** stable for all; "in front of me" needs mental rotation in combat.

```
A  HELM disc (ship)          RELAY map (world)
     .--12--.                 A  B  C  D
    9 H2* (^)3                1  ship->  H2*
     '--6---'                 2      <>Bravo
B  every screen: ship disc, rotates with the ship
C  every screen: world map, ship arrow rotates on it
```

### Q3. Shared radar visual

- **A. Disc with stems + range ring at the selected foot + optional side strip (Recommended):** Elite-familiar, fixes its range weakness. Stems clutter with many contacts.
- **B. Sphere with arcs:** each contact on an arc from the disc; better distance reading. Unfamiliar, harder at small size.
- **C. Two flat views (top + side), flight-sim style:** no 3D reading needed. Doubles screen space, no single picture.

```
A   .---12---.     B   .--12--.     C  TOP    SIDE
   9  H2* |  3       9  H2 )  3        . H2   |  H2
      (^)  '           (^)/            (^)    (^)-
    '---6---'          '--6--'          .      |
```

### Q4. Marks: who places them, how many

- **A. Any station places (incl. Captain), Relay curates; 8 NATO names; pings unlimited but rate-limited (Recommended):** everyone can say "here"; Relay keeps it tidy.
- **B. Relay only:** clean single owner; other stations must ask, slower in combat.
- **C. Anyone, unlimited, no curation:** most expressive; clutter and griefing risk with 64 connections.

### Q5. Shield facing control (Helm, D16)

- **A. Six-face snap + clock-sector tap + track-selected toggle (Recommended):** one input per callout ("shields 4 high"); three modes to learn.
- **B. Free direction vector (mouse on sphere / stick):** precise; slow and fiddly while flying.
- **C. Track-selected only:** trivial to use; no way to cover an unselected or unknown threat.

```
A  shield ring:   .-12-.   [1 fore][2 aft][3 port]
                 9 (#) 3   [4 stbd][5 dors][6 vent]
                  '-6-'    G = track H2
```

### Q6. How Helm points the ship at a target

- **A. Compass + off-screen arrows + hold-to-face assist at real turn rate (Recommended):** "face H2" is one key; less manual skill expression.
- **B. Compass + arrows only, fully manual:** most skill; slow for new players and touch.
- **C. Click a contact on the radar to auto-set heading (autopilot):** easiest; Helm becomes passive.

### Q7. Helm layout

- **A. Cockpit + compass + disc (H-A) (Recommended):** precise, immersive.
- **B. Chase camera (H-B):** better orientation awareness; worse docking.
- **C. Split cockpit + tactical (H-C):** best for navigation and touch; smaller view.

### Q8. Weapons layout

- **A. Gunnery orbit + mount panel (W-A) (Recommended):** 3D aim with awareness; busy screen.
- **B. Turret camera (W-B):** immersive, great for 2 sharing Weapons; poor awareness.
- **C. Tactical disc + inset (W-C):** touch-friendly, EE-like; aiming less visceral.

### Q9. Combo set for crews of 1–5

- **A. Set in section 3 (Recommended):** 4 = H·W·E·Ops; 3 = Tactical·E·Ops; 2 = Flight·Systems; 1 = Solo.
- **B. Only one combo per size:** easier to balance and teach; less choice.
- **C. Alternative 2-player split: Pilot (H+E) · Mission (W+S+R):** weapons with sensors; Helm loses the gun but gains power control.

```
A  [ FLIGHT  H+W ]   [ SYSTEMS  E+S+R ]
C  [ PILOT   H+E ]   [ MISSION  W+S+R ]
```

### Q10. Solo combo form

- **A. Cockpit + one swappable side panel, actionable toasts (Recommended):** flying stays visible; panel switching costs a key.
- **B. Full-screen station tabs (F1–F5):** each station at full size; lose sight of the cockpit.
- **C. Everything shrunk on one screen:** nothing hidden; unreadable on a laptop.

```
A  [ cockpit ........ | ENG/SCI/RLY panel ]
B  [F1 HELM][F2 WPN][F3 ENG][F4 SCI][F5 RLY] one at a time
C  [cockpit][wpn][eng][sci][rly] tiles, all small
```

### Q11. Scan minigame

- **A. Signal tuning (Scan-A):** EE-familiar, accessible; no 3D learning.
- **B. Silhouette alignment (Scan-B) (Recommended):** teaches 3D, creates a Helm call; harder for some players.
- **C. Both, chosen by contact type:** variety; double the work.

### Q12. Hack minigame

- **A. Node route (Hack-A) (Recommended):** depth, scan synergy, input-agnostic.
- **B. Tumbler rings (Hack-B):** quick, tactile; shallow.

### Q13. Main screen default view

- **A. Forward view + radar strip + callsign rail (M-A) (Recommended):** the room's shared reference; busy for viewers.
- **B. Cinematic (M-B):** great spectacle; useless for coordination.
- **C. Tactical map (M-C):** best for planning; less exciting.

### Q14. Pings across stations

- **A. Ping on middle-click/long-press, 3 s pulse on all screens + chime (Recommended):** replaces finger-pointing; needs a rate limit.
- **B. No pings, voice only:** purest same-room play; slow for 3D.
- **C. Pings plus short canned text ("Need power", "Out of arc"):** works for remote players; risks becoming the "constant prompts" spec 6 forbids.
