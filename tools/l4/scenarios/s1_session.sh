# shellcheck shell=bash disable=SC2034,SC2154  # sourced by tools/l4/run.sh
# Scenario 1 (FT-TST-011, FT-TST-014): a dedicated server and three crew clients.
# Join and coverage, claims on a shared station, reconnect after a SIGKILL within the
# grace, then a crew client killed past the grace: the universe pauses until it rejoins.
# Sourced by tools/l4/run.sh (helpers: server, client, await, kill9, signal).
server
client c1 c1.intent    # Tactical; claims mount 0; killed and relaunched within the grace
client c2 c2.intent    # Tactical, then Ops; its command on c1's mount is rejected
client c3 c3.intent    # Systems; killed past the grace, relaunched after the pause
await c1_kill
kill9 c1
client c1 c1.relaunch.intent
await c3_kill
kill9 c3
await paused 60        # c1 and c2 saw the pause and a frozen tick
client c3 c3.relaunch.intent
