# shellcheck shell=bash disable=SC2034,SC2154  # sourced by tools/l4/run.sh
# Scenario 3 (T058, FT-M1-001, FT-M1-012): the encounter end to end through the real
# client UI (--client ui: menu, lobby, station screens, outcome card). The host plays
# Tactical (HostSession, its server child started with the test flag
# --m1-player-hull-scale), c2 Systems, c3 Ops. Run 1: Ops marks the enemy and pings
# it, Systems puts the spare pips on the weapons (D212), Tactical selects the ping, faces
# it and fires the claimed mount until the enemy is destroyed (a win, about a minute of sim);
# the crew votes "Run again" (2 of 3) and everyone is back in the lobby. Run 2: Tactical charges with weapons cold and the
# raider destroys the ship (a loss, about 40 s with the hull scaled to 20 %); the host
# runs it again alone (D178). Two fights don't fit the default 90 s, so this scenario
# raises its own limit.
((limit >= 200)) || limit=200
PORT=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
client h h.intent --client ui
await url 90
URL=$(cat "$out/sig.url")
client c2 c2.intent --client ui
client c3 c3.intent --client ui
