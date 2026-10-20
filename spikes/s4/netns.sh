#!/usr/bin/env bash
# Private network namespace with its own loopback for S4 loss runs, so netem
# never touches the host's lo (other services share it).
#   spikes/s4/netns.sh up [loss%] [mtu]   create ft-s4 with netem loss (default 2, 1500)
#   spikes/s4/netns.sh exec CMD...        run CMD in it as $USER, pinned to CPUs 2,3
#   spikes/s4/netns.sh down               delete the namespace
# netem on lo drops each packet with the given probability once, so both
# directions (data and ACKs) see the loss.
set -euo pipefail
ns=ft-s4
cpus=${S4_CPUS:-2,3}
case ${1:-} in
  up)
    loss=${2:-2}
    mtu=${3:-1500}
    sudo ip netns add "$ns"
    sudo ip netns exec "$ns" ip link set lo mtu "$mtu" up
    sudo ip netns exec "$ns" tc qdisc add dev lo root netem loss "${loss}%"
    sudo ip netns exec "$ns" tc qdisc show dev lo
    ;;
  exec)
    shift
    exec sudo ip netns exec "$ns" sudo -u "$USER" env HOME="$HOME" PATH="$PATH" \
      taskset -c "$cpus" "$@"
    ;;
  down)
    sudo ip netns del "$ns"
    ;;
  *)
    echo "usage: $0 up [loss%] [mtu] | exec CMD... | down" >&2
    exit 2
    ;;
esac
