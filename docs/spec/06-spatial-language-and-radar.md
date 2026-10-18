# 6. Spatial language and radar

Principle: players talk about things, not angles. Every contact and point of interest has a short shared name, and every UI element accepts that name (D45).

## 6.1 Callout layers (D45, alternative A)

1. **Callsigns.** Each contact gets a name on detection, coloured by known allegiance: `H1` hostile, `U2` unknown, `F3` friendly, `N4` neutral; player ships by ship name. The number never changes: `U2` identified as hostile becomes `H2`.
2. **Clock, height, range (ship frame, spoken).** `12` bow, `3` starboard, `6` stern, `9` port in the deck plane. Height: `level` (within ±15°), `high`/`low` (15°–60°), `overhead`/`under` (over 60°). Range: `close` (< 1 km), `mid`, `far`. Chips read like the callout: `H2 · 4 high · 2.3 km ▲closing`.
3. **Marks (world-anchored).** Up to 8 per ship, named Alpha to Hotel, free or attached to a contact; drawn as a diamond with a stem everywhere (D44).

Precise layer, on hover or long-press only: bearing 000–359 clockwise from the bow and mark −90…+90 in the ship frame; grid squares on world-frame maps (`grid D4, up 2`).

| Callout | Listener's action |
|---|---|
| "Helm, face H2" | Select H2, hold F |
| "Shields 4 high" | Tap the 4-high sector on the shield ring |
| "Bring us to Bravo" | Select Bravo, face or follow route |
| "Look here" | Ping: middle-click or long-press |

## 6.2 Radar (D42, D43)

Elite-style disc: the disc is the deck plane, clock numbers on the rim; each blip has a stem to the disc (solid blip, stem up = above; hollow, stem down = below); a range ring passes through the selected contact's stem foot; an optional side strip (B) shows elevation. Crew stations (Helm, Weapons, Science) use the ship frame; Relay, Captain map views and the tactical main-screen view use the world frame on the scenario map's ecliptic (D77). Helm's Level aligns the two.

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

Any station, including the Captain, places marks; Relay curates them. A ping pulses an item for 3 s on every screen of the ship, including the main screen, with a chime; pings are rate-limited.

Allied ships share one faction, so they share callsigns and contact knowledge, but marks and pings stay per ship (D82). Relay can send a mark to an allied ship; it waits in that ship's Relay inbox and reaches its crew only once its Relay accepts it, as a copy that becomes one of that ship's marks (D82).

## 6.4 Requirements

- **FT-SPA-001** Every detected contact shall get a callsign whose prefix shows known allegiance (H, U, F, N) and whose number never changes. (D45)
- **FT-SPA-002** Callsigns shall be assigned per faction, and every station of a ship shall use the same callsign for a contact. (D21, D45)
- **FT-SPA-003** Contact chips shall show callsign, clock position, height word and range. (D45)
- **FT-SPA-004** Clock position shall be measured in the ship's deck plane, with height words at ±15° and ±60° boundaries. (D45)
- **FT-SPA-005** Bearing/mark values shall appear only on hover or long-press. (D45)
- **FT-SPA-006** World-frame maps shall show grid squares and altitude. (D45)
- **FT-SPA-007** The disc radar shall draw elevation stems, solid blips above and hollow blips below the disc. (D43)
- **FT-SPA-008** The disc radar shall draw a range ring through the selected contact's stem foot. (D43)
- **FT-SPA-009** The disc radar shall offer an optional elevation side strip toggled by B. (D43)
- **FT-SPA-010** Helm, Weapons and Science radars shall use the ship frame; Relay, Captain and the tactical main-screen view shall use the world frame. (D42)
- **FT-SPA-011** Orbiting the disc shall be possible on Science and Relay; Helm and Weapons insets shall use a fixed camera angle. (station-ui §1.5)
- **FT-SPA-012** Each ship shall have at most 8 marks, named Alpha to Hotel. (D44)
- **FT-SPA-013** Any crew station and the Captain shall place marks; only Relay shall rename or delete marks placed by others. (D44)
- **FT-SPA-014** A mark shall be free in world space or attached to a contact. (D44)
- **FT-SPA-015** Marks shall be selectable like contacts on every station. (D44, D47)
- **FT-SPA-016** A ping shall pulse the pinged item for 3 s on every screen of that ship, including the main screen, with a chime. (D61)
- **FT-SPA-017** Pings shall be rate-limited per client. (D44, D61)
- ~~**FT-SPA-018**~~ Removed (D82): superseded by FT-SPA-020, which adds Relay-to-Relay mark sending.
- **FT-SPA-019** Marks and pings shall remain available at every difficulty. (D69)
- **FT-SPA-020** Marks and pings shall be visible only to the ship that made them, except a mark sent and accepted under FT-SPA-021. (D21, D44, D82)
- **FT-SPA-021** A mark sent by Relay to an allied ship shall be visible only to that ship's Relay until its Relay accepts it; on acceptance it shall become one of the receiving ship's marks, visible to its crew; a declined mark shall be discarded. (D82)
- **FT-SPA-022** Accepting a sent mark when the receiving ship has 8 marks shall require its Relay to pick a mark to replace. (D44, D82)
- **FT-SPA-023** Allied ships shall use the same callsign for a contact. (D45, D82)
