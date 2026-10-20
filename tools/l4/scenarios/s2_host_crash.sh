# shellcheck shell=bash disable=SC2034,SC2154  # sourced by tools/l4/run.sh
# Scenario 2 (TECH-8, FT-NET-001, FT-NET-003): the host client spawns the server as
# its child (HostLauncher, host secret) and plays Tactical with two crew clients. It
# is SIGKILLed mid-run and relaunched: it finds its orphaned server from the pid file
# and rejoins on the same ship and pick with its stored token, while the other two
# keep receiving snapshots. At the end the host stops its server; run.sh fails on any
# process left behind.
PORT=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
client h h.intent
await url 60
URL=$(cat "$out/sig.url")
client c2 c2.intent
client c3 c3.intent
await h_kill
kill9 h
client h h.relaunch.intent
