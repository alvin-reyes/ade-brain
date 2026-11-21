#!/bin/bash
# bin/recover (story R1): each crash scenario is simulated, bin/recover runs, the recovery and its journal line are
# checked. Fakes for claude, launchctl, node (BMAD tickets) and the chat channel (AGENT_CHAT_SEND); no network.
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"; stub_security; export AGENT_STATE="$(mktemp -d)"; ST="$AGENT_STATE"
FAKE="$(mktemp -d)"; mkdir -p "$FAKE/bin"; export FAKE
cat > "$FAKE/bin/send" <<'STUB'
#!/bin/bash
[ -z "${FAKE_SEND_FAIL:-}" ] || exit 1
cat >> "$FAKE/sent"; echo >> "$FAKE/sent"
STUB
printf '#!/bin/bash\necho "$*" >> "$FAKE/launchctl.log"\nexit 0\n' > "$FAKE/bin/launchctl"
printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$FAKE/node.argv"\nexit 0\n' > "$FAKE/bin/node"
cat > "$FAKE/bin/claude" <<'STUB'
#!/bin/bash
echo started >> "$FAKE/claude.log"; exit 0
STUB
printf '#!/bin/bash\nexit 0\n' > "$FAKE/bin/bun"
chmod +x "$FAKE"/bin/*; export PATH="$FAKE/bin:$PATH" AGENT_CHAT_SEND="$FAKE/bin/send" AGENT_LAUNCHAGENTS="$(mktemp -d)"
export AGENT_CHAT_FORWARD_EVERY=0
unset TELEGRAM_BOT_TOKEN TELEGRAM_STATE_DIR HUB_CHAT HUB_CHANNELS CLAUDE_CONFIG_DIR
CH="$ST/channels/telegram"; mkdir -p "$CH"
printf '{"dmPolicy": "allowlist", "allowFrom": ["99887766"], "groups": {}}\n' > "$CH/access.json"
printf '%s\n' "123456789:TEST-telegram-token-VALUE-abc" | bin/keys set telegram >/dev/null 2>&1
bin/new projects/demo >/dev/null
CK="$(mktemp -d)/demo-code"; mkdir -p "$CK/_bmad" && : > "$CK/_bmad/ade-runtime.mjs"
git -C "$CK" init -q && git -C "$CK" config user.name t && git -C "$CK" config user.email t@t
echo one > "$CK/a.txt"; git -C "$CK" add -A && git -C "$CK" commit -qm init
J() { cat journal/*.md 2>/dev/null; }
sent_texts() { python3 -c 'import json,sys
for l in open(sys.argv[1]):
    l=l.strip()
    if l: print(json.loads(l)["text"])' "$FAKE/sent" 2>/dev/null; }
dead_pid() { sleep 0 & local p=$!; wait "$p" 2>/dev/null; echo "$p"; }
# a live stand-in for a bin/work launcher (its command holds "-work.", as bin/sessions checks)
live_launcher() { local f; f="$(mktemp -d)/agent-work.live"; printf '#!/bin/bash\nsleep 60\n' > "$f"; chmod +x "$f"; "$f" </dev/null >/dev/null 2>&1 & echo $!; }
entry() { mkdir -p "$ST/sessions"; printf 'name=%s\nfolder=%s\nlauncher=%s\nparent=-\nstarted=2026-11-21T10:00:00Z\ncwd=%s\nrole=%s\n' \
  "$1" "$2" "$3" "$4" "$5" > "$ST/sessions/$1.$3"; }
reset() { rm -rf journal/*.md "$ST/recover" "$ST/sessions" "$ST/sessions-dead" "$ST/chat" "$ST/events.jsonl" "$ST/events-seen" \
  "$ST/dispatch.lock" "$AGENT_SYNC_LOCK"; : > "$FAKE/sent"; : > "$FAKE/node.argv"; : > "$FAKE/launchctl.log"; : > "$FAKE/claude.log"; }

orchestrator_died_restarts() {   # row 1
  reset; entry api projects/demo "$(live_launcher)" "$CK" builder; mkdir -p "$ST/chat"
  echo "$(dead_pid) 2026-11-21T09:00Z" > "$ST/chat/chat.pid"
  mkdir -p "$ST/chat/asks"; echo "Deploy?" > "$ST/chat/asks/abcde"
  out="$(bin/recover 2>&1)" || fail "recover [$out]"
  [ -e "$ST/chat/chat.pid" ] && fail "the dead orchestrator's pid file was kept"
  J | grep -q "orchestrator died" || fail "journal line [$(J)]"
  sent_texts | grep -qx "restarted, 1 agent running, 1 waiting" || fail "the restart message [$(sent_texts)]"
  for s in "After a restart" "STATE.md" "bin/work --continue"; do assert_contains templates/hub/CLAUDE.md "$s" "hub rule: what to read after a restart"; done
}

reboot_runs_recover_first() {   # row 2
  reset; SCHEDULE_DRY=1 bin/schedule install >/dev/null 2>&1
  p="$AGENT_LAUNCHAGENTS/ai.agent-hub.hub.recover.plist"; [ -f "$p" ] || fail "no recover job at login"
  assert_contains "$p" "bin/recover" "the job runs bin/recover"; assert_contains "$p" "<key>RunAtLoad</key><true/>" "at login"
  # the orchestrator's service runs bin/recover before it starts the session
  mkdir -p "$ST/chat"; echo "$(dead_pid) 2026-11-21T09:00Z" > "$ST/chat/chat.pid"
  bin/chat start </dev/null >/dev/null 2>&1 || fail "chat start"
  J | grep -q "orchestrator died" || fail "chat start ran no recover first [$(J)]"
  [ -s "$FAKE/claude.log" ] || fail "the session started after recover"
}

agent_died_blocked_not_done() {   # row 3
  reset; head0="$(git -C "$CK" rev-parse HEAD)"; entry T-1.2 projects/demo "$(dead_pid)" "$CK" builder
  out="$(bin/recover 2>&1)" || fail "recover [$out]"
  J | grep -q "agent T-1.2 died" || fail "journal line [$(J)]"
  grep -q "tickets --project-root $CK mark T-1.2 blocked --blocked agent died" "$FAKE/node.argv" || fail "ticket marked blocked [$(cat "$FAKE/node.argv")]"
  grep -qi "done" "$FAKE/node.argv" && fail "a ticket was marked done"
  assert_eq "$(git -C "$CK" rev-parse HEAD)" "$head0" "nothing committed on its behalf"
  grep -q '"from":"projects/demo","to":"main","kind":"note","text":"blocked: agent T-1.2 died' "$ST/events.jsonl" || fail "main notified [$(cat "$ST/events.jsonl")]"
  grep -q -- "bin/work --continue --role builder --name T-1.2 projects/demo" "$ST/recover/"*.md || fail "the note says how to restart it"
  ls "$ST/sessions/" 2>/dev/null | grep -q T-1.2 && fail "the dead entry is still listed"
  # bin/sessions keeps a dead entry for recover (it used to delete it)
  reset; entry web projects/demo "$(dead_pid)" "$CK" -; bin/sessions >/dev/null
  bin/recover >/dev/null 2>&1; J | grep -q "agent web died" || fail "an entry bin/sessions pruned is still recovered"
  # bin/work can continue the conversation in the same folder
  out="$(WORK_DRY=1 bin/work --continue --force --claude claude projects/demo 2>&1)"; echo "$out" | grep -q -- "--continue" || fail "bin/work --continue [$out]"
}

uncommitted_work_kept() {   # row 4
  reset; echo changed >> "$CK/a.txt"; echo new > "$CK/b.txt"; before="$(git -C "$CK" status --porcelain; git -C "$CK" diff)"
  entry T-1.3 projects/demo "$(dead_pid)" "$CK" builder; bin/recover >/dev/null 2>&1
  assert_eq "$(git -C "$CK" status --porcelain; git -C "$CK" diff)" "$before" "uncommitted work kept as-is"
  git -C "$CK" stash list | grep -q . && fail "work was stashed"
  grep -q "a.txt" "$ST/recover/"*.md && grep -q "1 file changed" "$ST/recover/"*.md || fail "the note lists the diff stat [$(cat "$ST/recover/"*.md)]"
  grep -q "b.txt" "$ST/recover/"*.md || fail "the note lists the untracked file"
  J | grep -q "uncommitted work kept in $CK" || fail "journal line [$(J)]"
  git -C "$CK" checkout -q a.txt; rm -f "$CK/b.txt"
}

stale_locks_removed() {   # row 5
  reset; d="$(dead_pid)"; mkdir -p "$ST/chat/lock" "$ST/chat/forward.lock" "$ST/dispatch.lock" "$AGENT_SYNC_LOCK"
  for l in "$ST/chat/lock" "$ST/chat/forward.lock" "$ST/dispatch.lock" "$AGENT_SYNC_LOCK"; do echo "$d" > "$l/pid"; done
  sleep 60 </dev/null >/dev/null 2>&1 & live=$!
  bin/recover >"$FAKE/out" 2>&1
  for l in "$ST/chat/lock" "$ST/chat/forward.lock" "$ST/dispatch.lock" "$AGENT_SYNC_LOCK"; do
    [ -e "$l" ] && fail "stale lock kept: $l"; J | grep -q "removed stale lock $l" || fail "journaled: $l [$(J)] [$(cat "$FAKE/out")]"; done
  # a live owner's lock is kept
  mkdir -p "$ST/dispatch.lock"; echo "$live" > "$ST/dispatch.lock/pid"; bin/recover >/dev/null 2>&1
  [ -d "$ST/dispatch.lock" ] || fail "a live owner's lock was removed"; kill "$live" 2>/dev/null; rm -rf "$ST/dispatch.lock"
}

torn_log_and_cursor() {   # row 6
  reset; H="$HUB" ST="$ST" python3 -I bin/events.py write --from main --to all --kind note --text "whole line" || fail "write"
  printf '{"time":"2026-11-21T10:00:00Z","from":"main","to":"all","ki' >> "$ST/events.jsonl"
  size="$(wc -c < "$ST/events.jsonl")"; ino="$(ls -i "$ST/events.jsonl" | awk '{print $1}')"
  mkdir -p "$ST/events-seen" "$ST/chat"; echo "$ino $((size + 500))" > "$ST/events-seen/sess1"; echo "$ino 999999" > "$ST/chat/forward.cursor"
  bin/recover >/dev/null 2>&1
  [ "$(tail -c 1 "$ST/events.jsonl" | od -An -c | tr -d ' ')" = '\n' ] || fail "the torn last line is still there"
  python3 -c 'import json,sys; [json.loads(l) for l in open(sys.argv[1])]' "$ST/events.jsonl" || fail "the log is not whole lines"
  grep -q "whole line" "$ST/events.jsonl" || fail "a whole line was lost"
  ns="$(wc -c < "$ST/events.jsonl" | tr -d ' ')"
  assert_eq "$(cat "$ST/events-seen/sess1")" "$ino $ns" "a cursor past the end is reset to the end"
  assert_eq "$(cat "$ST/chat/forward.cursor")" "$ino $ns" "the forward cursor too"
  J | grep -q "event log: dropped a torn last line" || fail "journal line [$(J)]"
}

network_down_nothing_lost() {   # row 7
  reset; mkdir -p "$ST/chat"; echo "$(dead_pid) 2026-11-21T09:00Z" > "$ST/chat/chat.pid"
  FAKE_SEND_FAIL=1 bin/recover >/dev/null 2>&1
  [ -s "$FAKE/sent" ] && fail "sent while the network is down"
  J | grep -q "chat unreachable: the message is kept" || fail "journal line [$(J)]"
  ls "$ST/chat/pending/" | grep -q . || fail "the message is kept to send later"
  bin/chat forward >/dev/null 2>&1 || fail "forward once the network is back"
  sent_texts | grep -q "^restarted, " || fail "the kept message was sent [$(sent_texts)]"
  ls "$ST/chat/pending/" | grep -q . && fail "a sent message was kept"
  : > "$FAKE/sent"; bin/chat forward >/dev/null 2>&1; [ -s "$FAKE/sent" ] && fail "sent twice"
  # the forwarder backs off while sending fails: 15, 30, 60, 120 s, then back to 15 once it works
  . bin/lib.sh; assert_eq "$(chat_backoff 15 1) $(chat_backoff 30 1) $(chat_backoff 120 1) $(chat_backoff 120 0)" "30 60 120 15" "backoff"
}

disk_full_one_alert() {   # row 8
  reset; AGENT_DISK_MIN_MB=999999999 bin/recover >"$FAKE/out" 2>&1 || fail "recover, disk full"
  grep -q "disk full" "$FAKE/out" || fail "reported [$(cat "$FAKE/out")]"
  J | grep -q "disk full" || fail "journal line"
  assert_eq "$(sent_texts | grep -c 'disk full')" "1" "one alert to the channel"
  AGENT_DISK_MIN_MB=999999999 bin/recover >/dev/null 2>&1; assert_eq "$(sent_texts | grep -c 'disk full')" "1" "still one alert"
  AGENT_DISK_MIN_MB=999999999 DOCTOR_OFFLINE=1 bin/doctor | grep -q "disk full" || fail "doctor shows it"
  # space back: the alert is armed again
  bin/recover >/dev/null 2>&1; [ -e "$ST/recover/disk-alert" ] && fail "the alert marker outlived the full disk"; true
}

agents_survive_ui_close() {   # row 9
  reset; lp="$(live_launcher)"; entry api projects/demo "$lp" "$CK" builder
  out="$(bin/recover 2>&1)"; kill -0 "$lp" 2>/dev/null || fail "recover stopped a running agent"
  [ -f "$ST/sessions/api.$lp" ] || fail "a running agent's entry was touched"
  J | grep -q "died" && fail "a running agent was reported dead"
  bin/sessions | grep -q "^api " || fail "the agent is still listed"; kill "$lp" 2>/dev/null; true
}

login_expired_stops_retrying() {   # row 10
  reset; export AGENT_CHAT_SERVICE=1
  for i in 1 2 3; do bin/chat start </dev/null >/dev/null 2>&1 || fail "service start $i"; done
  assert_eq "$(grep -c started "$FAKE/claude.log")" "3" "three starts"
  out="$(bin/chat start </dev/null 2>&1)"; assert_eq "$?" "1" "the fourth start in 10 min gives up"
  assert_eq "$(grep -c started "$FAKE/claude.log")" "3" "no fourth launch"
  grep -q "disable gui/.*ai.agent-hub.hub.chat" "$FAKE/launchctl.log" || fail "the job is disabled so launchd stops [$(cat "$FAKE/launchctl.log")]"
  sent_texts | grep -q 'login expired: run `claude` once' || fail "the channel is told [$(sent_texts)]"
  J | grep -q "login expired" || fail "journal line"
  unset AGENT_CHAT_SERVICE
}

idempotent() {   # AC 11
  reset; mkdir -p "$ST/chat"; echo "$(dead_pid) x" > "$ST/chat/chat.pid"; entry T-9 projects/demo "$(dead_pid)" "$CK" builder
  bin/recover >/dev/null 2>&1; j1="$(J)"; n1="$(ls "$ST/recover" | wc -l)"
  out="$(bin/recover 2>&1)" || fail "second run"; assert_eq "$out" "nothing to recover" "a second run"
  assert_eq "$(J)" "$j1" "a second run journals nothing"; assert_eq "$(ls "$ST/recover" | wc -l)" "$n1" "no second note"
}

doctor_read_only() {   # AC 12
  reset; mkdir -p "$ST/chat" "$ST/dispatch.lock"; echo "$(dead_pid) x" > "$ST/chat/chat.pid"; echo "$(dead_pid)" > "$ST/dispatch.lock/pid"
  entry T-8 projects/demo "$(dead_pid)" "$CK" builder
  printf '{"a":1}\n{"tor' > "$ST/events.jsonl"
  snap() { (cd "$ST" && find . -print | sort; cat events.jsonl; find . -type f -exec cat {} + 2>/dev/null) | shasum; }
  s0="$(snap)"; j0="$(J)"
  out="$(DOCTOR_OFFLINE=1 bin/doctor)"
  for c in "orchestrator" "agent T-8" "lock" "event log" "disk"; do echo "$out" | grep "^[A-Z]* *recover" | grep -q "$c" || fail "doctor lists [$c] [$out]"; done
  assert_eq "$(snap)" "$s0" "doctor changed the state"; assert_eq "$(J)" "$j0" "doctor journaled"
  grep -q " mark " "$FAKE/node.argv" && fail "doctor marked a ticket"; true
}

checks="orchestrator_died_restarts reboot_runs_recover_first agent_died_blocked_not_done uncommitted_work_kept stale_locks_removed
  torn_log_and_cursor network_down_nothing_lost disk_full_one_alert agents_survive_ui_close login_expired_stops_retrying idempotent doctor_read_only"
if [ $# -gt 0 ]; then "$1"; echo ok; exit 0; fi
for c in $checks; do "$c"; done
echo ok
