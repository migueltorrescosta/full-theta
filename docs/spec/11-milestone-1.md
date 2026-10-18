# 11. Milestone 1 (first playable)

One ship, three networked clients covering all six functional stations through joint views (for example Tactical · Systems · Ops), one authoritative headless server, one enemy, and the Engineering + Helm loop (D72).

## 11.1 Scope

1. Controllable ship with 6DOF Newtonian movement, flight assist and decoupled mode.
2. Helm, Weapons and Engineering interfaces at their chosen layouts; Science, Relay and Comms with station definitions and enough UI to be covered in the lobby.
3. Tactical, Systems and Ops joint views and the coverage check.
4. One enemy with basic AI (attack, keep range, retreat).
5. Manual aiming from a claimed, arc-limited mount.
6. A damageable and repairable subsystem (hit location, repair crew, spare parts).
7. The Engineering + Helm loop (P1), with its pair test.
8. Immediate event notifications and synchronised station state.
9. Clear encounter outcome and complete run reset.
10. Refresh-to-rejoin.
11. State keyed by ship and faction; a 2-ship PvP simulation test.
12. Dev flag letting one client hold all stations.
13. Automated tests and documented launch instructions.

Desktop clients only; browser stations come later (D8).

## 11.2 Requirements

- **FT-M1-001** Milestone 1 shall run one ship with three clients covering all six functional stations through joint views. (D72)
- **FT-M1-002** Milestone 1 shall run one authoritative headless server spawned by the Host button. (D7, D72)
- **FT-M1-003** Milestone 1 shall include a ship with 6DOF Newtonian flight, assist on by default and decoupled mode. (D24, v0.3 §9)
- **FT-M1-004** Milestone 1 shall include the Helm, Weapons and Engineering layouts of §5. (v0.3 §9)
- **FT-M1-005** Milestone 1 shall include station definitions for Science, Relay and Comms. (v0.3 §9)
- **FT-M1-006** Milestone 1 shall include the Tactical, Systems and Ops joint views and the lobby coverage check. (D67, D72)
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
