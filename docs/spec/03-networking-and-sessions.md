# 3. Networking and sessions

## 3.1 Hosting and joining

The Host button on any desktop client starts the same executable as a headless server child process and connects to it on localhost. The same binary runs on a dedicated machine (D7). Desktop clients find hosts by UDP broadcast or manual IP; browser stations (after milestone 1, D8) join through a URL and QR code served by the host (D70).

## 3.2 Protocol

Commands go up, each with a client sequence number. Down: per-station filtered snapshots at 30 Hz (full on join or resync, deltas afterwards) and a reliable ordered event stream (`Event{tick, type, payload}`) for alerts, voice and feedback (D70). Godot scene replication is not used for gameplay state.

## 3.3 Lobby, joint views and the coverage check

1. A player joins a ship (or creates one, up to 6).
2. The player picks one entry from the catalogue: a single functional station, a joint view, the Captain seat, or Viewer (D10, D67).
3. Several players may pick the same station or joint view; they share it through claims (§3.4).
4. The ship's Ready/Start control becomes clickable only when the coverage check passes: at least 3 crew players, and every one of Helm, Weapons, Engineering, Science, Relay and Comms covered by at least one crew player's pick (D66, D67).

Joint-view catalogue (D67, D76): every 2-station pair, 15 layouts, all offered in the lobby. Names are working titles; each view is named after the pair it serves (§7.3).

| Pair | Joint view | Stations | Notes |
|---|---|---|---|
| P1 | Drive | Engineering + Helm | Cockpit with power pips and shield panel |
| P2 | Tactical | Helm + Weapons | Cockpit and turret aim on one screen |
| P3 | Survey | Helm + Science | Cockpit with sensor disc and contact card |
| P4 | Nav | Helm + Relay | Cockpit with world map panel |
| P5 | Approach | Helm + Comms | Cockpit with card board panel |
| P6 | Gunnery | Weapons + Engineering | Turret view with power pips and cutaway |
| P7 | Targeting | Weapons + Science | Turret view with contact card |
| P8 | Fire Control | Weapons + Relay | Turret view with world map panel |
| P9 | Parley | Weapons + Comms | Turret view with card board panel |
| P10 | Systems | Engineering + Science | Cutaway and contact card |
| P11 | Logistics | Engineering + Relay | Cutaway with world map panel |
| P12 | Quartermaster | Engineering + Comms | Cutaway with card board; one player sees both, so D68 binds only two-player crews |
| P13 | Sensors | Science + Relay | Sensor disc and world map with a frame toggle |
| P14 | Intel | Science + Comms | Sensor disc with card board panel |
| P15 | Ops | Relay + Comms | World map with the card board |

With 2-station joint views, a 3-player crew must be an exact partition, for example Tactical · Systems · Ops. A joint view keeps every control of its stations; it is a layout, not automation (D20).

## 3.4 Claims on shared stations

Claimable sub-controls (D18): weapon mounts; repair crews; scan and hack queue slots; probes; NPC conversations; Helm flight control; Helm shield facing. A claimed item is locked for others and shows the claimer's name. Unclaimed items can be claimed by any player at that station.

## 3.5 Reconnect

Each client holds a session token. A refresh or relaunch presents the token and receives a full snapshot, returning the player to the same ship, station and claims (D6).

Mid-run disconnect (D83): a dropped crew player's picks, settings and claims stay for a 10 s grace period. If the ship's coverage check then fails, the whole universe pauses, every ship included, until coverage is restored by the player rejoining or by another player taking the station over. Captain and Viewer drops never pause the game (D19, D23).

## 3.6 Requirements

- **FT-NET-001** The Host button shall spawn the game executable as a headless authoritative server child process and connect to it on localhost. (D7)
- **FT-NET-002** The same executable shall run as a dedicated headless server. (D7)
- **FT-NET-003** The host client shall terminate its server child process on exit and detect orphaned server processes on start. (D7)
- **FT-NET-004** Every client shall connect over WebSocket using the custom protocol, so browser stations reuse the desktop code path. (D8, D70)
- **FT-NET-005** The protocol handshake shall carry a protocol version and reject mismatched clients with a reason. (D70)
- **FT-NET-006** Clients shall send only commands; the server shall validate each command against station holding, claims, rate limits and game rules. (v0.3 §3, D18)
- **FT-NET-007** A rejected command shall produce a `CommandRejected{reason}` event to the sender. (D70)
- **FT-NET-008** The server shall send each client a snapshot filtered to the stations it holds, at 30 Hz. (D70)
- **FT-NET-009** A snapshot shall contain no field the receiving station may not see at the session difficulty. (D14, D69)
- **FT-NET-010** A client shall receive no knowledge belonging to another faction. (D21)
- **FT-NET-011** Discrete changes shall be delivered as reliable ordered events stamped with the simulation tick. (D70)
- **FT-NET-012** The server shall broadcast its presence on the LAN by UDP once a second. (D70)
- **FT-NET-013** Clients shall join by discovered host, manual IP, or (browser) URL and QR code. (D70)
- **FT-NET-014** The server shall refuse connection 65 and above with a "session full" reason. (D22)
- **FT-NET-015** A player shall pick exactly one catalogue entry: a functional station, a joint view, Captain or Viewer. (D10, D67)
- **FT-NET-016** The lobby shall let any number of players pick the same station or joint view. (D10)
- **FT-NET-017** The lobby shall offer the joint views in the catalogue and no other station combinations. (D13, D67)
- **FT-NET-018** A joint view shall keep every control of each station it contains. (D20)
- **FT-NET-019** The Ready/Start control shall become clickable only when the coverage check passes for that ship. (D19, D66, D67)
- **FT-NET-020** The coverage check shall ignore Captain and Viewer picks. (D19, D23)
- **FT-NET-021** The lobby shall show which functional stations are still uncovered. (D67)
- **FT-NET-022** Weapon mounts, repair crews, scan and hack queue slots, probes, NPC conversations, Helm flight control and Helm shield facing shall be claimable. (D18)
- **FT-NET-023** A claimed item shall accept commands only from its claimer and shall show the claimer's name to others at that station. (D18)
- **FT-NET-024** A claim shall be released explicitly, on station change, or when the claimer's reconnect grace period ends. (D6, D18)
- **FT-NET-025** Each client shall hold a session token that survives a browser refresh or desktop relaunch. (D6)
- **FT-NET-026** A client presenting a valid token shall return to the same ship, catalogue entry and claims and receive a full snapshot. (D6)
- **FT-NET-027** A rejoined client's state shall converge to the server state within one snapshot interval of the full snapshot. (D6)
- **FT-NET-028** Viewers shall receive only their ship's main-screen state. (D10, D21)
- **FT-NET-029** A development flag shall let one client hold all stations, bypassing the 3-player minimum. (D72)
- **FT-NET-030** The server shall serve the web export over plain HTTP for browser stations once they ship. (D8, D70)
- **FT-NET-031** The game shall offer no internet play, relay or master-server registration. (D70)
- **FT-NET-032** The catalogue shall offer one joint view for each of the 15 pairs of functional stations and no view of 3 or more stations. (D67, D76)
- **FT-NET-033** When a crew client disconnects mid-run, the server shall keep its catalogue pick, station settings and claims for a 10 s grace period. (D83)
- **FT-NET-034** If a ship's coverage check fails when a grace period ends, the server shall pause the simulation of the whole universe, every ship included, and show every client which ship and stations are uncovered. (D83)
- **FT-NET-035** During a pause, a rejoining player or any player of that ship changing catalogue entry shall be able to restore coverage; the simulation shall resume once every ship's coverage check passes. (D83)
- **FT-NET-036** A Captain or Viewer disconnect shall never pause the simulation. (D19, D23, D83)
