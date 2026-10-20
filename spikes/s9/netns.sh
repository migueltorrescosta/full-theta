#!/usr/bin/env bash
# Private network namespace ft-s9 with its own loopback, so the S9 run's wire
# bytes (/proc/net/dev lo) count only its own traffic. No netem: S9 needs no loss.
#   spikes/s9/netns.sh up [mtu]     create ft-s9 (default MTU 1500, as on Ethernet or Wi-Fi)
#   spikes/s9/netns.sh exec CMD...  run CMD in it as $USER (run.sh pins the CPUs)
#   spikes/s9/netns.sh down         delete the namespace
set -euo pipefail
ns=ft-s9
case ${1:-} in
  up)
    sudo ip netns add "$ns"
    sudo ip netns exec "$ns" ip link set lo mtu "${2:-1500}" up
    ;;
  exec)
    shift
    exec sudo ip netns exec "$ns" sudo -u "$USER" env HOME="$HOME" PATH="$PATH" "$@"
    ;;
  down)
    sudo ip netns del "$ns"
    ;;
  *)
    echo "usage: $0 up [mtu] | exec CMD... | down" >&2
    exit 2
    ;;
esac
