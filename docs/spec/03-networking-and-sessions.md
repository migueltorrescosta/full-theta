# 3. Networking and sessions

## 3.1 Hosting and joining

The Host button on any desktop client starts the same executable as a headless server child process and connects to it on localhost. The same binary runs on a dedicated machine (D7). Desktop clients find hosts by UDP broadcast or manual IP; browser stations (after milestone 1, D8) join through a URL and QR code served by the host (D70).

## 3.2 Protocol

Commands go up, each with a client sequence number. Down: per-station filtered snapshots at 30 Hz (full on join or resync, deltas afterwards) and a reliable ordered event stream (`Event{tick, type, payload}`) for alerts, voice and feedback (D70). Godot scene replication is not used for gameplay state.

## 3.3 Lobby, joint views and the coverage check

1. A player joins a ship, or adds one in the lobby; any player may add a ship, up to 6, and a ship nobody picked vanishes at Start (D260).
2. The player picks one entry from the catalogue: a single functional station, a joint view, the Captain seat, or Viewer (D10, D67).
3. Several players may pick the same station or joint view; they share it through claims (§3.4).
4. The ship's Ready/Start control becomes clickable only when the coverage check passes: at least 3 crew players, and every one of Helm, Weapons, Engineering, Science, Relay and Comms covered by at least one crew player's pick (D66, D67). Any crew player of the ship may then press Start; the universe starts once every crewed ship has pressed Start, each passing its coverage check, and the world is built from the picked ships in lobby order (D129, D260, D261).

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
| P12 | Quartermaster | Engineering + Comms | Cutaway with card board; one player sees both by design (D76); D68 binds Engineering and Comms held by different players (FT-PAIR-010) |
| P13 | Sensors | Science + Relay | Sensor disc and world map with a frame toggle |
| P14 | Intel | Science + Comms | Sensor disc with card board panel |
| P15 | Ops | Relay + Comms | World map with the card board |

With 2-station joint views, a 3-player crew must be an exact partition, for example Tactical · Systems · Ops. A joint view keeps every control of its stations; it is a layout, not automation (D20).

## 3.4 Claims on shared stations

Claimable sub-controls (D18): weapon mounts; repair crews; the active scan or hack; probes; NPC conversations; Helm flight control; Helm shield facing. A claimed item is locked for others and shows the claimer's name. Unclaimed items can be claimed by any player at that station. A player alone on a station holds all its claims; when a second player joins, the first keeps them and the newcomer claims only what the first releases (D130). Every other control is ship-wide (FT-NET-044).

## 3.5 Reconnect

Each client holds a session token. A refresh or relaunch presents the token and receives a full snapshot, returning the player to the same ship, station and claims (D6).

Mid-run disconnect (D83, D96): a dropped crew player's picks, settings and claims stay for a 10 s grace period. If the ship's coverage check then fails, the whole universe pauses, every ship included, until coverage is restored by the player rejoining, by an ally, the ship's own Captain or a viewer taking the station over, or by the ship being abandoned (D265). Captain and Viewer drops never pause the game (D19, D23).

Coverage counts only ships still in play; a destroyed or abandoned ship leaves play (D96).

## 3.6 Requirements

- **FT-NET-001** The Host button shall spawn the game executable as a headless authoritative server child process and connect to it on localhost. (D7)
- **FT-NET-002** The same executable shall run as a dedicated headless server. (D7)
- **FT-NET-003** The host client shall terminate its server child process on exit; on start it shall offer to rejoin an orphaned server from this install with its stored token, and a server shall exit by itself after N minutes with no connections. (D7, D96, plan review TECH-8)
- **FT-NET-004** Every client shall connect over WebSocket using the custom protocol, so browser stations reuse the desktop code path. (D8, D70)
- **FT-NET-005** The protocol handshake shall carry a protocol version and reject mismatched clients with a reason. (D70)
- **FT-NET-006** Clients shall send only commands; the server shall validate each command against station holding, claims, rate limits and game rules. (v0.3 §3, D18)
- **FT-NET-007** A rejected command shall produce a `CommandRejected{reason}` event to the sender. (D70)
- **FT-NET-008** The server shall send each client a snapshot filtered to the stations it holds, at 30 Hz. (D70)
- **FT-NET-009** A snapshot shall contain no field the receiving station may not see at the session difficulty. (D14, D69)
- **FT-NET-010** A client shall receive no knowledge belonging to another faction. The live scoreboard shows per ship its name, team, state (in play, finished or destroyed), encounters done, elapsed time and, in PvP, kills, but no hull or positions. (D21, D266)
- **FT-NET-011** Discrete changes shall be delivered as reliable ordered events stamped with the simulation tick. (D70)
- **FT-NET-012** The server shall broadcast its presence on the LAN by UDP once a second. (D70)
- **FT-NET-013** Clients shall join by discovered host, manual IP, or (browser) URL and QR code. (D70)
- **FT-NET-014** The server shall refuse connection 65 and above with a "session full" reason. (D22)
- **FT-NET-015** A player shall pick exactly one catalogue entry: a functional station, a joint view, Captain or Viewer. (D10, D67)
- **FT-NET-016** The lobby shall let any number of players pick the same station or joint view, and at most one player per ship pick Captain. (D10, plan review CLASH-10)
- **FT-NET-017** The lobby shall offer the joint views in the catalogue and no other station combinations. (D13, D67)
- **FT-NET-018** A joint view shall keep every control of each station it contains. (D20)
- **FT-NET-019** The Ready/Start control shall become clickable only when the coverage check passes for that ship, and the universe shall start once every crewed ship has pressed Start. (D19, D66, D67, D129, D261)
- **FT-NET-020** The coverage check shall ignore Captain and Viewer picks. (D19, D23)
- **FT-NET-021** The lobby shall show which functional stations are still uncovered. (D67)
- **FT-NET-022** Weapon mounts, repair crews, the active scan or hack, probes, NPC conversations, Helm flight control and Helm shield facing shall be claimable. (D18, plan review STN-3)
- **FT-NET-023** A claimed item shall accept commands only from its claimer and shall show the claimer's name to others at that station. (D18)
- **FT-NET-024** A claim shall be released explicitly, on station change, or when the claimer's reconnect grace period ends. (D6, D18)
- **FT-NET-025** Each client shall hold a session token that survives a browser refresh or desktop relaunch. (D6)
- **FT-NET-026** A client presenting a valid token shall receive a full snapshot and return to the same ship, catalogue entry and claims if they are still free, else to that ship's pick screen. (D6, D96)
- **FT-NET-027** A rejoined client's state shall converge to the server state within one snapshot interval of the full snapshot. (D6)
- **FT-NET-028** Viewers shall receive only their ship's main-screen state. (D10, D21)
- **FT-NET-029** A development flag shall let one client hold all stations, bypassing the 3-player minimum. (D72)
- **FT-NET-030** The server shall serve the web export over plain HTTP for browser stations once they ship; the export pipeline shall use a shell without the secure-context check and guard the engine's AudioWorklet start-up, with a test that fails when the patched pattern changes. (D8, D70, D108)
- **FT-NET-031** The game shall offer no internet play, relay or master-server registration. (D70)
- **FT-NET-032** The catalogue shall offer one joint view for each of the 15 pairs of functional stations and no view of 3 or more stations. (D67, D76)
- **FT-NET-033** When a crew client disconnects mid-run, the server shall keep its catalogue pick, station settings and claims for a 15 s grace period, timed like every pause timer on wall clock outside `sim/` (re-timed from tablet refresh-to-rejoin times in #4; the phone took 11 s). (D83, D96, D108, D188, plan review TECH-3)
- **FT-NET-034** If the coverage check of a ship still in play fails when a grace period ends, the server shall pause the simulation of the whole universe, every ship included, and show every client which ship and stations are uncovered. (D83, D96)
- **FT-NET-035** During a pause, a rejoining player or any player of that ship changing catalogue entry shall be able to restore coverage; the simulation shall resume once the coverage check of every ship still in play passes. (D83, D96)
- **FT-NET-036** A Captain or Viewer disconnect shall never pause the simulation. (D19, D23, D83)
- **FT-NET-037** When a send to a client fails, its high-priority queue passes 256 KiB or more than 15 snapshots (about 533 ms at 30 Hz) go unacknowledged, the server shall stop sending it deltas and send a full snapshot once the queue drains; events shall never be dropped. (plan review TECH-2, D106)
- **FT-NET-038** Messages above a size limit, such as voice clips and full snapshots, shall be sent in chunks, with voice chunks at lower priority than snapshots. (plan review TECH-2)
- **FT-NET-039** The static HTTP server shall never delay a simulation tick by more than 1 ms. (plan review TECH-3)
- **FT-NET-040** The server shall encode each snapshot once per distinct view key (ship, catalogue entry, difficulty toggles) and send it to every client sharing that key, encoding and sending on a worker thread from a copy of the state so the sim tick holds only the sim. (plan review TECH-9, D111)
- **FT-NET-041** During a pause, the remaining connected crew of a paused ship shall be able to abandon it by a majority vote (more than half of them; a vote may be withdrawn, and votes clear when the pause ends), and the host alone shall be able to abandon it; abandoning eliminates the ship and takes it out of play; in PvP the crew may also give up outside a pause by the same vote, or the host at once for the host's own ship only (the host's request for another ship is refused `not_your_ship`), and then goes to a friendly ship's viewer or the scoreboard (D267, M4-F1). The host is the client presenting the host secret its Host button passed to the child server; a dedicated server has no host. (D96, D127, D128)
- **FT-NET-042** During a pause, players of allied ships and the paused ship's own Captain and viewers shall be able to take over an uncovered station, never an enemy; there is no accept prompt, the first claim wins and the ship's side sees who took it; a takeover that would make the taker's own ship fail the coverage check is refused. (D96, D265)
- **FT-NET-043** Outside a pause, the server shall reject with `CommandRejected` any mid-run catalogue change that would make a ship fail the coverage check. (D96, plan review CLASH-1)
- **FT-NET-044** A player alone on a station shall hold all its claims; controls that are not claimable shall be ship-wide, last writer wins, and show who changed them last. (plan review STN-3, D130)
- **FT-NET-045** Dock, jump, Align and face shall belong to the Helm flight claim, ammo type to the mount claim, and a card's Accept to its conversation claim when one exists. (plan review STN-3, D124)
- **FT-NET-046** A browser station shall keep the tablet or phone awake while connected (a muted looping VP9 video started by the first tap, since Wake Lock needs a secure context; an H.264 MP4 only if iPads need it; documented Auto-Lock settings as the fallback), so an idle station doesn't drop and pause the universe; S3 and #4 check a 10 min idle; the hidden-video keep-awake stays until #25 shows devices still sleeping. (plan review TECH-3, D108, D278)
