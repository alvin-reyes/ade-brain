#!/bin/bash
# bin/session-end run without Claude Code's hook: bounded stdin, --since, the sync lock, the session-end log.
. "$(dirname "$0")/helpers.sh"
export AGENT_LOCK_WAIT=3
KIDS=""; trap 'for k in $KIDS; do kill "$k" 2>/dev/null; done' EXIT
f() { fail "$CHECK: $*"; }
# a fresh hub per check: projects/demo with one code checkout, everything committed
setup() {
  make_hub; cd "$HUB"; export AGENT_STATE="$(mktemp -d)" AGENT_SESSION_END_LOG="$(mktemp -d)/session-end.log"
  K="$AGENT_SYNC_LOCK"; J="journal/$(date -u +%Y-%m-%d).md"; NOW=$(date +%s)
  bin/new projects/demo >/dev/null
  R="$(mktemp -d)/demo-code"; mkdir -p "$R" && git -C "$R" init -q && git -C "$R" config user.email t@t && git -C "$R" config user.name t
  printf '| demo-code | %s | main | Alvin | none |\n' "$R" >> projects/demo/ACCESS.md
  git add -A >/dev/null 2>&1; git commit -q --no-verify -m base >/dev/null 2>&1
}
# code_commit <message> <epoch>: a commit in the demo checkout dated <epoch>
code_commit() { echo "$1" >> "$R/f"; git -C "$R" add f; GIT_AUTHOR_DATE="$2 +0000" GIT_COMMITTER_DATE="$2 +0000" git -C "$R" commit -qm "$1"; }
iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%S.000Z; }
# run_held <secs> <cmd...>: cmd's stdin is a pipe whose writer never closes; killed after <secs>. RC = its status, 124 = killed.
run_held() {
  local s="$1" p w i=0 wp; shift; wp="$(mktemp -d)/writer"   # a real pipe: script(1) refuses a fifo as stdin
  { sleep 60 2>/dev/null & echo $! > "$wp"; wait; } | "$@" > "$AGENT_STATE/out" 2> "$AGENT_STATE/err" & p=$!
  while [ ! -s "$wp" ]; do sleep 0.1; done; w=$(cat "$wp"); KIDS="$KIDS $w"
  while kill -0 "$p" 2>/dev/null && [ $i -lt $((s * 5)) ]; do sleep 0.2; i=$((i + 1)); done
  RC=; kill -0 "$p" 2>/dev/null && { pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null; RC=124; }
  kill "$w" 2>/dev/null   # bash waits for the whole pipeline, so the writer goes first
  wait "$p" 2>/dev/null; i=$?; [ -n "$RC" ] || RC=$i
}
# hold_lock: the sync lock held by a live process (pid in $SP)
hold_lock() { mkdir "$K"; sleep 30 & SP=$!; KIDS="$KIDS $SP"; echo "$SP" > "$K/pid"; }
committed() { git log -1 --pretty=%s | grep -q "^session projects/demo "; }
hook() { echo '{"transcript_path":""}' | bin/session-end "$@"; }

CHECK=held_pipe_under_script_finishes; setup
echo more >> projects/demo/STATE.md
run_held 20 script -q /dev/null "$HUB/bin/session-end" projects/demo
[ "$RC" != 124 ] || f "still running after 20 s (stdin read never returned)"
committed || f "folder not committed"

CHECK=never_closing_pipe_finishes; setup
echo more >> projects/demo/STATE.md
run_held 20 bin/session-end projects/demo
[ "$RC" != 124 ] || f "still running after 20 s"
assert_eq "$RC" 0 "$CHECK: exit"
committed || f "folder not committed"
assert_eq "$(cat "$AGENT_STATE/out")" "" "$CHECK: the hook path prints nothing"

CHECK=hook_start_from_transcript; setup
code_commit oldfix $((NOW - 3*3600)); code_commit newfix $((NOW - 600))
printf '{"timestamp":"%s"}\n' "$(iso $((NOW - 3600)))" > "$AGENT_STATE/t.jsonl"
echo "{\"transcript_path\":\"$AGENT_STATE/t.jsonl\"}" | bin/session-end projects/demo
grep -q newfix "$J" 2>/dev/null || f "commit after the transcript start not journaled"
grep -q oldfix "$J" && f "commit before the transcript start journaled"

CHECK=since_sets_exact_start; setup
code_commit oldfix $((NOW - 3*3600)); code_commit newfix $((NOW - 600))
printf '{"timestamp":"%s"}\n' "$(iso $((NOW - 4*3600)))" > "$AGENT_STATE/t.jsonl"   # earlier than --since: --since wins
echo "{\"transcript_path\":\"$AGENT_STATE/t.jsonl\"}" | bin/session-end projects/demo --since $((NOW - 3600)); assert_eq "$?" 0 "$CHECK: exit"
grep -q newfix "$J" 2>/dev/null || f "commit after --since not journaled"
grep -q oldfix "$J" && f "commit before --since journaled"

CHECK=since_rejects_non_epoch; setup
echo more >> projects/demo/STATE.md; h=$(git rev-parse HEAD)
bin/session-end projects/demo --since abc < /dev/null 2> "$AGENT_STATE/err"; assert_eq "$?" 2 "$CHECK: exit"
[ -s "$AGENT_STATE/err" ] || f "no message on stderr"
assert_eq "$(git rev-parse HEAD)" "$h" "$CHECK: committed anyway"
bin/session-end projects/demo --since < /dev/null 2>/dev/null; assert_eq "$?" 2 "$CHECK: --since without a value"

CHECK=unknown_argument_refused; setup
echo more >> projects/demo/STATE.md; h=$(git rev-parse HEAD)
for a in "--launch x" "--bogus" "projects/demo extra"; do
  bin/session-end projects/demo $a < /dev/null 2> "$AGENT_STATE/err"; assert_eq "$?" 2 "$CHECK: [$a] exit"
  grep -q "unknown argument" "$AGENT_STATE/err" || f "[$a]: no 'unknown argument' on stderr"
done
bin/session-end projects/demo --launch x < /dev/null 2>&1 | grep -q -- "--launch" || f "message does not name --launch"
assert_eq "$(git rev-parse HEAD)" "$h" "$CHECK: committed anyway"

CHECK=waits_for_lock_then_commits; setup
echo more >> projects/demo/STATE.md; hold_lock; (sleep 2; date +%s > "$AGENT_STATE/released"; rm -rf "$K") & r=$!
hook projects/demo; rc=$?; wait $r
assert_eq "$rc" 0 "$CHECK: exit"; committed || f "folder not committed"
[ "$(git log -1 --format=%ct)" -ge "$(cat "$AGENT_STATE/released")" ] || f "committed before the lock was released"
[ -d "$K" ] && f "lock left behind"

CHECK=busy_lock_skips_and_journals; setup
code_commit newfix $((NOW - 600)); echo more >> projects/demo/STATE.md; h=$(git rev-parse HEAD); hold_lock
hook projects/demo; assert_eq "$?" 0 "$CHECK: exit"
assert_eq "$(git rev-parse HEAD)" "$h" "$CHECK: committed under a busy lock"
git status --porcelain | grep -q "projects/demo/STATE.md" || f "hub file not left uncommitted"
assert_eq "$(grep -c "sync lock busy" "$J" 2>/dev/null)" 1 "$CHECK: journal lines about the busy lock"
grep "sync lock busy" "$J" | grep -q newfix || f "skip line does not list the commits"
[ -d "$K" ] || f "other process's lock removed"; assert_eq "$(cat "$K/pid")" "$SP" "$CHECK: lock owner"

CHECK=stale_lock_removed; setup
echo more >> projects/demo/STATE.md; mkdir "$K"; sh -c 'echo $$ > '"$K"'/pid'   # owner gone
hook projects/demo; committed || f "dead owner: not committed"; [ -d "$K" ] && f "dead owner's lock kept"
echo more >> projects/demo/STATE.md; h=$(git rev-parse HEAD)
hold_lock; touch -t 202001010000 "$K"                                          # over 120 minutes old
hook projects/demo; [ "$(git rev-parse HEAD)" != "$h" ] || f "old lock: not committed"; [ -d "$K" ] && f "old lock kept"
assert_eq "$(grep -c "removed stale lock" "$AGENT_SESSION_END_LOG" 2>/dev/null)" 2 "$CHECK: stale locks logged"

CHECK=release_before_auto_sync; setup
S="$(mktemp -d)"; printf '#!/bin/bash\nexit 0\n' > "$S/gitleaks"; chmod +x "$S/gitleaks"
git config core.hooksPath .githooks; echo more >> projects/demo/STATE.md; echo m >> memory/MEMORY.md
PATH="$S:$PATH" AGENT_AUTO_SYNC=1 hook projects/demo; assert_eq "$?" 0 "$CHECK: exit"
for i in $(seq 1 50); do grep -qE "synced:|skipped:|failed:|refused:" "$AGENT_SYNC_LOG" 2>/dev/null && break; sleep 0.2; done
grep -q "skipped: another sync is running" "$AGENT_SYNC_LOG" 2>/dev/null && f "the follow-on sync found the lock held"
grep -q "synced:" "$AGENT_SYNC_LOG" 2>/dev/null || f "the follow-on sync did not sync: $(cat "$AGENT_SYNC_LOG" 2>/dev/null)"

CHECK=since_writes_session_end_log; setup
S0=$((NOW - 3600)); L="$AGENT_SESSION_END_LOG"
echo more >> projects/demo/STATE.md; bin/session-end projects/demo --since $S0 < /dev/null
bin/session-end projects/demo --since $S0 < /dev/null
hold_lock; echo more >> projects/demo/STATE.md; bin/session-end projects/demo --since $S0 < /dev/null; kill $SP; rm -rf "$K"
bin/session-end projects/demo --since 12x < /dev/null 2>/dev/null
assert_eq "$(wc -l < "$L" | tr -d ' ')" 4 "$CHECK: one line per run"
sed -n 1p "$L" | grep -q "projects/demo.*$S0.* committed$" || f "line 1: $(sed -n 1p "$L")"
sed -n 2p "$L" | grep -q "projects/demo.*$S0.* nothing to commit$" || f "line 2: $(sed -n 2p "$L")"
sed -n 3p "$L" | grep -q "projects/demo.*$S0.* skipped: sync lock busy$" || f "line 3: $(sed -n 3p "$L")"
sed -n 4p "$L" | grep -q "projects/demo.* refused: " || f "line 4: $(sed -n 4p "$L")"
sed -n 1p "$L" | grep -qE "^20[0-9]{2}-[01][0-9]-[0-3][0-9]T[0-9:]+Z " || f "no UTC timestamp: $(sed -n 1p "$L")"
before=$(wc -l < "$L"); hook projects/demo; assert_eq "$(wc -l < "$L")" "$before" "$CHECK: hook path wrote an outcome line"
unset AGENT_SESSION_END_LOG; bin/session-end projects/demo --since $S0 < /dev/null
grep -q "nothing to commit" "$AGENT_STATE/logs/session-end.log" 2>/dev/null || f "default log path not used"

CHECK=lock_wait_default_is_30; setup
assert_eq "$(env -u AGENT_LOCK_WAIT bash -c '. bin/lib.sh; sync_lock_wait')" 30 "$CHECK: default"
assert_eq "$(AGENT_LOCK_WAIT=7 bash -c '. bin/lib.sh; sync_lock_wait')" 7 "$CHECK: AGENT_LOCK_WAIT"

CHECK=hook_path_always_exits_zero; setup
echo more >> projects/demo/STATE.md; hold_lock
out=$(hook projects/demo); assert_eq "$?" 0 "$CHECK: busy"; assert_eq "$out" "" "$CHECK: busy is quiet"
kill $SP; wait $SP 2>/dev/null                                                   # now stale: owner gone
out=$(hook projects/demo); assert_eq "$?" 0 "$CHECK: stale"; assert_eq "$out" "" "$CHECK: stale is quiet"
out=$(hook projects/demo); assert_eq "$?" 0 "$CHECK: nothing to commit"; assert_eq "$out" "" "$CHECK: nothing to commit is quiet"
echo ok
