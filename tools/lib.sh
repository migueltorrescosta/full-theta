# shellcheck shell=bash disable=SC2034
# Shared helpers for the tier scripts (tools/l4/*.sh, tools/l6/run.sh); source it, don't run it.
#   source "$(dirname "$0")/../lib.sh"      (after `set -uo pipefail`)
# The waits fail loudly: they print the cause on stderr and return non-zero, so the caller
# decides (die, failed=1) instead of carrying on with a server that never started.

# ft_alive PID: running and not a zombie.
ft_alive() {
  local st
  st=$(sed 's/^.*) //' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f1) || return 1
  [[ -n $st && $st != Z ]]
}

# ft_cpu_list SPEC: expands 0,1 or 4-7 into "0 1" / "4 5 6 7".
ft_cpu_list() {
  local part
  for part in ${1//,/ }; do
    if [[ $part == *-* ]]; then seq "${part%-*}" "${part#*-}"; else echo "$part"; fi
  done | tr '\n' ' '
}

# ft_allowed_cpus: the CPUs this process may run on, one per line (its affinity mask).
ft_allowed_cpus() {
  local spec
  spec=$(taskset -pc $$ 2>/dev/null | sed 's/^.*: //')
  [[ -n $spec ]] || spec="0-$(($(nproc) - 1))"
  ft_cpu_list "$spec" | tr ' ' '\n' | grep .
}

# ft_pick_cpus [COUNT] [EXCLUDE]: COUNT allowed CPUs (default 2) as a taskset list, taking
# physical cores before hyper-thread siblings and leaving out the EXCLUDE list (and, when
# others remain, its siblings). With fewer CPUs than asked it returns what there is.
ft_pick_cpus() {
  local want=${1:-2} skip=${2:-} c s sib out=() ex=" " all=()
  for c in $(ft_cpu_list "$skip"); do
    ex+="$c "
    sib=$(cat "/sys/devices/system/cpu/cpu$c/topology/thread_siblings_list" 2>/dev/null)
    for s in $(ft_cpu_list "$sib"); do ex+="$s "; done
  done
  mapfile -t all < <(ft_allowed_cpus)
  # Primary threads first: a CPU whose sibling list starts with its own number.
  for c in "${all[@]}"; do
    [[ $ex == *" $c "* ]] && continue
    sib=$(cut -d, -f1 "/sys/devices/system/cpu/cpu$c/topology/thread_siblings_list" 2>/dev/null | cut -d- -f1)
    [[ -z $sib || $sib == "$c" ]] && out+=("$c")
  done
  for c in "${all[@]}"; do
    ((${#out[@]} >= want)) && break
    [[ $ex == *" $c "* || " ${out[*]} " == *" $c "* ]] && continue
    out+=("$c")
  done
  if ((${#out[@]} == 0)); then out=("${all[@]}"); fi # nothing left after EXCLUDE: share
  local IFS=,
  echo "${out[*]:0:want}"
}

# ft_cpus VAR [COUNT] [EXCLUDE]: the value of env var VAR when set, else ft_pick_cpus.
ft_cpus() {
  local v=${!1:-}
  if [[ -n $v ]]; then echo "$v"; else ft_pick_cpus "${2:-2}" "${3:-}"; fi
}

# ft_wait_ready LOG PID SECS: waits for the server's line "ready ws=ADDR:PORT http=ADDR:PORT"
# (app/main.gd) in LOG; sets WS_URL (ws://...) and HTTP_URL (http://..., empty when the
# server serves no web export). Returns 1 with the cause on stderr when PID exits first or
# SECS pass.
ft_wait_ready() {
  local log=$1 pid=$2 end=$((SECONDS + $3)) line http
  until line=$(grep -a -m1 '^ready ws=' "$log" 2>/dev/null); do
    ft_alive "$pid" || { echo "server exited before it was ready: $(tail -n 3 "$log" 2>/dev/null | tr '\n' ' ')" >&2; return 1; }
    ((SECONDS < end)) || { echo "server not ready after $3 s (log $log)" >&2; return 1; }
    sleep 0.1
  done
  WS_URL=ws://$(sed 's/^ready ws=\([^ ]*\).*/\1/' <<<"$line")
  http=$(sed 's/.* http=//' <<<"$line")
  HTTP_URL=
  [[ $http == *:0 ]] || HTTP_URL=http://$http
}

# ft_wait_for WHAT SECS COMMAND...: polls COMMAND once a second; returns 1 and says what
# was missing on stderr when SECS pass.
ft_wait_for() {
  local what=$1 end=$((SECONDS + $2))
  shift 2
  until "$@"; do
    ((SECONDS < end)) || { echo "timed out waiting for $what" >&2; return 1; }
    sleep 0.5
  done
}

# ft_sweep PATTERN: kills processes whose command line matches PATTERN (a run folder) and
# prints their pids on stdout; returns 1 when there were any (they were leftovers).
ft_sweep() {
  local left
  left=$(pgrep -f -- "$1" | grep -vx "$$" | tr '\n' ' ')
  [[ -n $left ]] || return 0
  # shellcheck disable=SC2086  # a list of pids
  kill -9 $left 2>/dev/null
  echo "$left"
  return 1
}
