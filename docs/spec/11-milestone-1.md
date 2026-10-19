# 11. Milestone 1 (first playable)

One ship, three networked clients covering all six functional stations through joint views (for example Tactical · Systems · Ops), one authoritative headless server, one enemy, and the Engineering + Helm loop, with marks, pings and Relay's map read-out so Ops has a job (D72, D99).

## 11.1 Scope

1. Controllable ship with 6DOF Newtonian movement, flight assist (rotation, drift and throttle holds), all-stop, hold-to-approach and decoupled mode (D97), at site-local positions (D98).
2. Helm, Weapons and Engineering interfaces at their chosen layouts; Science, Relay and Comms with station definitions and enough UI to be covered in the lobby; Relay's map read-out.
3. Tactical, Systems and Ops joint views, modal with one focused panel (D95), the coverage check and lobby load tags (D99).
4. Marks and pings on every station.
5. One enemy with basic AI (attack, keep range, retreat).
6. Manual aiming from a claimed, arc-limited mount.
7. A damageable and repairable subsystem (hit location, repair crew, spare parts).
8. The Engineering + Helm loop (P1), with its pair test.
9. Immediate event notifications and synchronised station state.
10. Clear encounter outcome and complete run reset.
11. Refresh-to-rejoin.
12. State keyed by ship and faction; a 2-ship PvP simulation test.
13. Dev flag letting one client hold all stations.
14. Controls overlay and per-station first-run tooltips (D100).
15. Automated tests and documented launch instructions.
16. A playtest that rotates every player through Tactical, Systems and Ops (D99).

Desktop clients only; browser stations come later (D8).

## 11.2 Requirements

- **FT-M1-001** Milestone 1 shall run one ship with three clients covering all six functional stations through joint views. (D72)
- **FT-M1-002** Milestone 1 shall run one authoritative headless server spawned by the Host button. (D7, D72)
- **FT-M1-003** Milestone 1 shall include a ship with 6DOF Newtonian flight, assist on by default with its holds, all-stop, hold-to-approach and decoupled mode. (D24, D97, v0.3 §9)
- **FT-M1-004** Milestone 1 shall include the Helm, Weapons and Engineering layouts of §5. (v0.3 §9)
- **FT-M1-005** Milestone 1 shall include station definitions for Science, Relay and Comms. (v0.3 §9)
- **FT-M1-006** Milestone 1 shall include the Tactical, Systems and Ops joint views, modal with one focused panel, and the lobby coverage check. (D67, D72, D95)
- **FT-M1-007** Milestone 1 shall include one enemy with attack, keep-range and retreat behaviours. (v0.3 §9)
- **FT-M1-008** Milestone 1 shall include manual aiming from a claimed, arc-limited mount. (D25, D49)
- **FT-M1-009** Milestone 1 shall include one subsystem damaged by hit location and repaired by a repair crew using spare parts. (D26, D27)
- **FT-M1-010** Milestone 1 shall include the P1 Engineering + Helm loop with its automated pair test. (D72)
- **FT-M1-011** Milestone 1 shall show immediate event notifications and keep station state synchronised. (v0.3 §9)
- **FT-M1-012** Milestone 1 shall end the encounter with a clear win or loss and reset the run completely. (v0.3 §9, D30)
- **FT-M1-013** Milestone 1 shall support refresh-to-rejoin with a session token. (D6, D72)
- **FT-M1-014** Milestone 1 shall key all state by ship and faction and include a headless 2-ship PvP simulation test. (D21, D72)
- **FT-M1-015** Milestone 1 shall include the dev flag that lets one client hold all stations. (D72)
- **FT-M1-016** Milestone 1 shall document launch instructions for host, client and dedicated server. (v0.3 §9)
- **FT-M1-017** Milestone 1 shall include marks, pings and Relay's map read-out (FT-RLY-001 to FT-RLY-003, FT-SPA-006, FT-SPA-012 to FT-SPA-015). (D99)
- **FT-M1-018** Milestone 1's lobby shall show a load tag (light, busy, intense) per station and joint view. (D99)
- **FT-M1-019** Milestone 1 shall include the controls overlay generated from the input map and per-station first-run tooltips. (D100)
- **FT-M1-020** Milestone 1 shall store positions as a site id plus a local offset (FT-SIM-035). (D98)
- **FT-M1-021** The milestone 1 playtest shall rotate every player through Tactical, Systems and Ops. (D99)
