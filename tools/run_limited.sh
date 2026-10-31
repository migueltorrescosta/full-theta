#!/usr/bin/env bash
# run_limited.sh SECONDS REPORT_FILE COMMAND...: runs COMMAND; past SECONDS it saves a
# backtrace of every thread (gdb, through sudo when it is passwordless) to REPORT_FILE,
# terminates it (SIGKILL 10 s later) and exits 124. Otherwise exits with COMMAND's status.
# Used by tools/gate.sh so a hung L1 shard fails in minutes with its stack (#33).
limit=$1 report=$2
shift 2
"$@" &
pid=$!
deadline=$((SECONDS + limit))
while kill -0 "$pid" 2>/dev/null && ((SECONDS < deadline)); do sleep 1; done
if kill -0 "$pid" 2>/dev/null; then
  if command -v gdb >/dev/null; then
    # (ptrace_scope 1 stops a plain gdb from attaching to a non-child, and exits 0 anyway.)
    sudo=$(sudo -n true 2>/dev/null && echo "sudo -n")
    $sudo gdb -p "$pid" -batch -ex "thread apply all bt 30" >"$report" 2>&1
  fi
  kill -TERM "$pid"
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  kill -KILL "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  exit 124
fi
wait "$pid"
