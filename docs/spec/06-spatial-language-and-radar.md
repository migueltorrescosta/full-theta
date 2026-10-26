# 6. Spatial language and radar

Principle: players talk about things, not angles. Every contact and point of interest has a short shared name, and every UI element accepts that name (D45).

## 6.1 Callout layers (D45, alternative A)

1. **Callsigns.** Each contact gets a name on detection, coloured by known allegiance: `H1` hostile, `U2` unknown, `F3` friendly, `N4` neutral; player ships by ship name. The number never changes: `U2` identified as hostile becomes `H2`. In M1 a faction identifies a contact once one of its ships has it within that ship's identify range (D112).
2. **Clock, height, range (ship frame, spoken).** `12` bow, `3` starboard, `6` stern, `9` port in the deck plane. Height: `level` (within ±15°), `high`/`low` (15°–60°), `overhead`/`under` (over 60°, said without a clock). Range: `close` (< 1 km), `mid` (1–10 km), `far` (> 10 km). Chips read like the callout: `H2 · 4 high · mid ▲closing` (D114).
3. **Marks (world-anchored).** Up to 8 per ship, named Alpha to Hotel, free or attached to a contact; drawn as a diamond with a stem everywhere (D44).
4. **Sites.** Each site is a named point with a radius on the scenario map, with a shared name from the scenario (`Kestrel Yard`), selectable like marks and outside the 8-mark cap (D98, D229).

Frame rule (D97, D124): clock and the words level/high/low/overhead/under are always ship frame, on every station, including Relay and the Captain. Space has no privileged up: no word or rule uses a world-fixed direction. A point away from the own ship is said relative to a mark or site, with the speaker's ship-frame clock, height and range (`Bravo, 12 high, 3 km`).

Precise layer, on hover or long-press only: bearing 000–359 clockwise from the bow and mark −90…+90 in the ship frame. There are no grid squares or altitude layers (D124 retires D113).

| Callout | Listener's action |
|---|---|
| "Helm, face H2" | Select H2, hold F |
| "Shields 4 high" | Tap the 4-high sector on the shield ring |
| "Bring us to Bravo" | Select Bravo, hold approach (§5.1) |
| "Helm, all stop" | All-stop (§5.1) |
| "Helm, align on Bravo" | Select Bravo, press Align (§5.1) |
| "Jump to Kestrel Yard" | Select Kestrel Yard, JUMP |
| "Look here" | Ping: middle-click or long-press |

Callout grammar (plan review NAV, used by the [callout card](../callout-card.md)):

```
<who>, <verb> <object> [<qualifier>]
who:     Helm | Weapons | Shields | Science | Relay | Engineering | All
verb:    face | approach | stop | jump to | track | shields to | scan | mark | align
object:  callsign (H2) | mark (Bravo) | site (Kestrel Yard) | clock-height (4 high)
qual.:   range (2 km) | relative (Bravo, 12 high, 3 km) | "on my ping"
Prefer names over directions; directions only for unnamed space.
```

## 6.2 Radar (D42, D43)

Elite-style disc: the disc is the deck plane, clock numbers on the rim; each blip has a stem to the disc (solid blip, stem up = above; hollow, stem down = below); a range ring passes through the selected contact's stem foot; an optional side strip (Z; controller View + d-pad left) shows elevation. Every disc uses the ship frame. Relay, Captain map views and the tactical main-screen view may centre it on a selected mark, site or contact, keeping the ship's axes so clock and height words still match; no radar uses a world-fixed up (D124). Range zooms in fixed steps (2, 10, 50 km); contacts beyond the scale are arrows clamped to the rim. The selected contact's stem is drawn on top.

```
        .-----------  12  -----------.
     .'      F1 o                      '.
   9|    H1 *                 H2 *      |3
    |      |       ( ^ )        |       |
     '.    .        ship        :     .'
        '-----------  6  ------------'
  * above (solid, stem up)   o below (hollow, stem down)
```

## 6.3 Marks and pings (D44, D61)

Any station, including the Captain, places marks; Relay curates them. A mark may attach to a contact or to one of its scanned subsystems, so a weak point can be aimed at on Hard. Scan positions and hazard zones are MARK items (§7.1) outside the 8 named marks. Pinging an item someone else pinged is a silent "copy" (plan review COOP-8). A ping pulses an item for 3 s on every screen of the ship, including the main screen, with a chime; pings are rate-limited.

Allied ships share one faction, so they share callsigns and contact knowledge, but marks and pings stay per ship (D82). Relay can send a mark to an allied ship; it waits in that ship's Relay inbox and reaches its crew only once its Relay accepts it, as a copy that becomes one of that ship's marks (D82).

## 6.4 Requirements

- **FT-SPA-001** Every detected contact shall get a callsign whose prefix shows known allegiance (H, U, F, N) and whose number never changes. (D45)
- **FT-SPA-002** Callsigns shall be assigned per faction, and every station of a ship shall use the same callsign for a contact. (D21, D45)
- **FT-SPA-003** Contact chips shall show callsign, clock position, height word and range band (close < 1 km, mid 1–10 km, far > 10 km); above ±60° elevation they shall drop the clock and show only overhead or under. (D45, plan review NAV-7)
- **FT-SPA-004** Clock position shall be measured in the ship's deck plane, with height words at ±15° and ±60° boundaries. (D45)
- **FT-SPA-005** Bearing/mark values shall appear only on hover or long-press. (D45)
- **FT-SPA-006** Maps shall show no grid squares, altitude layers or world-fixed up; a point away from the own ship shall be read relative to a mark or site in ship-frame clock, height and range. (D45, D124, plan review NAV-1)
- **FT-SPA-007** The disc radar shall draw elevation stems, solid blips above and hollow blips below the disc. (D43)
- **FT-SPA-008** The disc radar shall draw a range ring through the selected contact's stem foot. (D43)
- **FT-SPA-009** The disc radar shall offer an optional elevation side strip toggled by Z (controller: View + d-pad left). (D43, D175)
- **FT-SPA-010** Every radar shall use the ship frame; Relay, Captain and the tactical main-screen view may centre it on a selected mark, site or contact with the ship's axes; no radar shall use a world-fixed up. (D42, D124)
- **FT-SPA-011** Orbiting the disc shall be possible on Science and Relay; Helm and Weapons insets shall use a fixed camera angle. (station-ui §1.5)
- **FT-SPA-012** Each ship shall have at most 8 named marks, Alpha to Hotel; site names, scan positions and hazard zones shall not count toward them. (D44, D98, plan review COOP-6)
- **FT-SPA-013** Any crew station and the Captain shall place marks; only Relay shall rename or delete marks placed by others; the Captain shall fill only empty slots and never move or delete a mark. (D44, plan review STN-5)
- **FT-SPA-014** A mark shall be free in world space, attached to a contact, or attached to one of a contact's scanned subsystems. (D44, P7, plan review COOP-6)
- **FT-SPA-015** Marks and sites shall be selectable like contacts on every station. (D44, D47, D98)
- **FT-SPA-016** A ping shall pulse the pinged item for 3 s on every screen of that ship, including the main screen, with a chime. (D61)
- **FT-SPA-017** Pings shall be rate-limited per client. (D44, D61)
- ~~**FT-SPA-018**~~ Removed (D82): superseded by FT-SPA-020, which adds Relay-to-Relay mark sending.
- **FT-SPA-019** Marks and pings shall remain available at every difficulty. (D69)
- **FT-SPA-020** Marks and pings shall be visible only to the ship that made them, except a mark sent and accepted under FT-SPA-021. (D21, D44, D82)
- **FT-SPA-021** A mark sent by Relay to an allied ship shall be visible only to that ship's Relay until its Relay accepts it; on acceptance it shall become one of the receiving ship's marks, visible to its crew; a declined mark shall be discarded. (D82)
- **FT-SPA-022** When a ship has 8 marks, placing a new mark shall be refused with a toast, except at Relay, which shall pick a mark to replace, both when placing a mark and when accepting a sent one. (D44, D82, plan review STN-5)
- **FT-SPA-023** Allied ships shall use the same callsign for a contact. (D45, D82)
- **FT-SPA-024** The disc radar shall zoom in fixed range steps (2, 10, 50 km) and draw contacts beyond the scale as arrows clamped to the rim. (plan review NAV-7)
- **FT-SPA-025** The disc radar shall draw the selected contact's stem on top of all others. (plan review NAV-7)
- **FT-SPA-026** Clock positions and the words level, high, low, overhead and under shall be ship frame on every station; no callout or rule shall use a world-fixed direction, and a point away from the own ship shall be said relative to a mark or site (`Bravo, 12 high, 3 km`). (D97, D124, plan review NAV-1)
- **FT-SPA-027** Each site shall have a shared name from scenario data, used by every station of every ship as a callout layer; a site is a named point with a radius on the scenario's one map. (D98, D229, plan review NAV-4)
- **FT-SPA-028** Scan positions and hazard zones shall be MARK items outside the 8 named marks and shall remain at every difficulty, including Hard. (plan review COOP-6)
- **FT-SPA-029** "Marks" in FT-PAIR-008 and the difficulty presets shall mean every MARK item (§7.1) except routes and approach lanes. (D84, plan review COOP-6)
- **FT-SPA-030** A mark placed on the forward view shall attach to the tapped contact; a tap that hits no contact shall place no mark. (plan review STN-5)
- **FT-SPA-031** A ping on an item that another station is pinging shall count as a silent "copy" and show the acknowledging station on the original ping. (plan review COOP-8)
