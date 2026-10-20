# 1. Objective and scope

Full Theta is a cross-platform, LAN, multi-crew 3D spaceship game loosely inspired by EmptyEpsilon (EE). Players in one room crew one or more spaceships. Each player runs a station: a view of, and controls over, one authoritative simulation. Play combines 6DOF Newtonian combat, exploration, ship operations, branching missions, synthetic voices and crew coordination. The look is semi-realistic science fiction with procedural geometry and readable silhouettes (D107).

## 1.1 Session shape

- A session hosts up to 6 player ships, in co-op or PvP (D11, D21).
- Each ship needs at least 3 crew players covering the 6 functional stations through stations and joint views (D19, D66, D67). Typical crews are 3–6 players; several players may share a station (D10, D18).
- The Captain seat and main-screen viewers are optional extras (D15, D23, D54).
- One session admits at most 64 connections in total: crew, Captains and viewers (D22).
- A run lasts 20–40 minutes and holds about 5 encounters (v0.3 §2, D31). Nothing persists between runs (D32).
- Players communicate by voice in the same room, aided by shared names, marks, pings and alerts. Speech recognition is out of scope (v0.3 §2).
- No human game master: an adaptive director composes handcrafted scenario components (v0.3 §2, D35, D64).

## 1.2 Requirements

- **FT-GEN-001** The game shall support up to 6 player ships in one session. (D11)
- **FT-GEN-002** The game shall support co-op and PvP sessions from the first architecture onward. (D21)
- **FT-GEN-003** A session shall admit at most 64 connections, counting crew, Captains and viewers. (D22)
- **FT-GEN-004** A ship shall not launch with fewer than 3 crew players (Captain and viewers excluded). (D66)
- **FT-GEN-005** A ship shall not launch until its crew covers all 6 functional stations. (D19, D67)
- **FT-GEN-006** The Captain seat shall never be required to launch or to play. (D19, D23)
- **FT-GEN-007** The game shall have no unstaffed-station automation and no "off" state for stations. (D19)
- **FT-GEN-008** The game shall not use speech recognition. (v0.3 §2)
- **FT-GEN-009** The game shall not require a human game master. (v0.3 §2)
- **FT-GEN-010** Nothing shall persist between runs. (D32)
- **FT-GEN-011** A typical run shall last 20–40 minutes. (v0.3 §2)
- **FT-GEN-012** Desktop builds shall target Linux, Windows and macOS. (D9)
- **FT-GEN-013** Play shall be LAN only. (D70)
- **FT-GEN-014** The repository shall be public at migueltorrescosta/full-theta under GPL-3.0. (D1, D2, D4)

## 1.3 Out of scope for v1

Internet play, speech recognition, cross-run unlocks, EE content compatibility (D62), browser stations before the first playable (D8), native mobile apps.
