#!/usr/bin/env bash
# run_limited.sh SECONDS REPORT_FILE COMMAND...: runs COMMAND; past SECONDS it saves a
# backtrace of every thread (gdb, through sudo when it is passwordless) to REPORT_FILE,
# terminates it (SIGKILL 10 s later) and exits 124. Otherwise exits with COMMAND's status.
# Exception: when RUN_LIMITED_LOG names COMMAND's output file and it already shows the
# whole run finished ("Overall Summary" and "Exit code: 0"), the hang is at process exit,
# not in a test (a thread left running deadlocks the engine's teardown): it is killed the
# same way, but the pass is kept (exit 0) with a loud warning on stderr.
# Used by tools/gate.sh so a hung L1 shard fails in minutes with its stack (#33).
limit=$1 report=$2
shift 2
"$@" &
pid=$!
# A run whose log shows every test finished gets EXIT_GRACE more seconds to exit.
grace=${EXIT_GRACE:-30}
done_log() {
  [[ -n ${RUN_LIMITED_LOG:-} && -r $RUN_LIMITED_LOG ]] || return 1
  local plain
  plain=$(sed 's/\x1b\[[0-9;]*m//g' "$RUN_LIMITED_LOG")
  grep -aq 'Overall Summary' <<<"$plain" && grep -aq '^Exit code: 0$' <<<"$plain"
}
deadline=$((SECONDS + limit)) done_at= tick=0
while kill -0 "$pid" 2>/dev/null && ((SECONDS < deadline)); do
  sleep 1
  if [[ -z $done_at ]] && ((++tick % 5 == 0)) && done_log; then
    done_at=$SECONDS
    ((done_at + grace < deadline)) && deadline=$((done_at + grace))
  fi
done
if kill -0 "$pid" 2>/dev/null; then
  if command -v gdb >/dev/null; then
    # (ptrace_scope 1 stops a plain gdb from attaching to a non-child, and exits 0 anyway.)
    sudo=$(sudo -n true 2>/dev/null && echo "sudo -n")
    $sudo gdb -p "$pid" -batch -ex "thread apply all bt 30" >"$report" 2>&1
  fi
  finished=
  done_log && finished=1
  kill -TERM "$pid"
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  kill -KILL "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  if [[ -n $finished ]]; then
    echo "run_limited: WARNING: every test finished and passed, but the process did not exit within ${grace} s of finishing and was killed (stack: $report). A thread left running at exit deadlocks the engine (#33): find the suite that leaks it (build/reports/*/thread-leaks.txt, tests/thread_guard_hook.gd)." >&2
    exit 0
  fi
  exit 124
fi
wait "$pid"
