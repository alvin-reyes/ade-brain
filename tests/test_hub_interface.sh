#!/bin/bash
# The hub commands ade-cli calls (story H1, .ade/context/hub-interface.md): bin/agent --live-test, the anthropic key
# path, bin/chat logs and test, bin/inbox --count, bin/dispatch --list.
# bash tests/test_hub_interface.sh [check ...] runs only the named checks (all of them by default).
# Hermetic: a fake claude, curl and node first on PATH, a stub bin/secret in the hub copy; no network, no real key.
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"
unset CLAUDE_CONFIG_DIR HUB_CLAUDE_CONFIG_DIR AGENT_CLAUDE AGENT_FOLDER AGENT_TIMEOUT TELEGRAM_BOT_TOKEN HUB_CHANNELS HUB_ORCHESTRATOR
S="$(mktemp -d)"; S="$(cd "$S" && pwd -P)"; mkdir -p "$S/tmp" "$S/home" "$S/bin" "$S/val"; export HI="$S" TMPDIR="$S/tmp" HOME="$S/home"
ST="$S/state"; mkdir -p "$ST"; export AGENT_STATE="$ST"
BG=""
trap '[ -z "$BG" ] || kill "$BG" 2>/dev/null; rm -rf "$S" "$(dirname "$HUB")" "$CLAUDE_HOME" "$(dirname "$AGENT_SYNC_LOG")" "$(dirname "$AGENT_SYNC_LOCK")" "$(dirname "$METHOD_FIXTURE")"' EXIT
bin/new projects/demo >/dev/null; bin/new projects/other >/dev/null
C="$S/cap"; KEY="sk-LIVETEST-$RANDOM$RANDOM-c0ffee0123"; TOK="123456789:AAH-TEST-telegram-token-VALUE-abcdefghi"
# the fake engine sees only what bin/agent lets through; it prints $S/reply (default READY) and exits $S/rc (default 0)
cat > "$S/bin/claude" <<STUB
#!/bin/bash
C="$C"; mkdir -p "\$C"; echo run >> "\$C/runs"; printf '%s\n' "\$@" > "\$C/argv"; env > "\$C/env"; pwd -P > "\$C/cwd"; cat > "\$C/stdin"
p=""; for a in "\$@"; do [ "\$p" = --settings ] && cp "\$a" "\$C/settings.json"; p="\$a"; done
if [ -f "$S/reply" ]; then cat "$S/reply"; else echo READY; fi
exit "\$(cat "$S/rc" 2>/dev/null || echo 0)"
STUB
# stub bin/secret: a name is stored when $S/val/<name> exists, and that file holds its value
cat > bin/secret <<'STUB'
#!/bin/bash
echo "secret $*" >> "$HI/secret.calls"
case "$1" in --has) [ -f "$HI/val/$2" ]; exit;; --set) [ -n "${2:-}" ] || exit 2; IFS= read -r v; [ -n "$v" ] || exit 1; printf '%s' "$v" > "$HI/val/$2"; exit 0;; --forget) rm -f "$HI/val/$2"; exit;; esac
[ -f "$HI/val/$1" ] || exit 1; cat "$HI/val/$1"
STUB
# fake curl: the config comes on stdin (-K -); it answers like the Telegram Bot API from fixture files
cat > "$S/bin/curl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$HI/curl.argv"; cfg="$(cat)"; printf '%s\n' "$cfg" >> "$HI/curl.cfg"
url="$(printf '%s\n' "$cfg" | sed -n 's/^url = "\(.*\)"$/\1/p')"
case "${url##*/}" in
  sendMessage) printf '%s\n' "$cfg" > "$HI/sent"; cat "$HI/send.json" 2>/dev/null || echo '{"ok":true,"result":{"message_id":5}}' ;;
  getUpdates)
    if printf '%s\n' "$cfg" | grep -q 'offset=-1'; then echo '{"ok":true,"result":[{"update_id":40,"message":{"chat":{"id":99887766},"text":"old"}}]}'
    elif [ -f "$HI/sent" ] && [ -f "$HI/reply.json" ]; then cat "$HI/reply.json"; rm -f "$HI/reply.json"
    else sleep 0.3; echo '{"ok":true,"result":[]}'; fi ;;
  *) echo '{"ok":false,"description":"unknown method"}' ;;
esac
STUB
# fake node: `tickets next` prints $S/tickets.json (fails when $S/nodefail exists)
cat > "$S/bin/node" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$HI/node.argv"; [ -e "$HI/nodefail" ] && { echo "tickets: error"; exit 2; }; cat "$HI/tickets.json"
STUB
chmod +x "$S/bin/claude" "$S/bin/curl" "$S/bin/node" bin/secret; export PATH="$S/bin:$PATH"
# the demo folder has one BMAD checkout; projects/other has none
CK="$S/demo-code"; mkdir -p "$CK/_bmad" && : > "$CK/_bmad/ade-runtime.mjs"
printf '| demo-code | %s | main | Owner | none |\n' "$CK" >> projects/demo/ACCESS.md
printf '#!/bin/bash\necho "$*" >> "$HI/work.log"\n' > bin/work
printf '#!/bin/bash\necho "NAME FOLDER PID PARENT STARTED ROLE STATUS LAST"\ncat "$HI/sessions" 2>/dev/null; exit 0\n' > bin/sessions
chmod +x bin/work bin/sessions

conf() { printf '%s\n' "$@" > hub.conf; }
reset() { rm -rf "$C" "$S/reply" "$S/rc" "$S/val" "$S/secret.calls" "$S/curl.argv" "$S/curl.cfg" "$S/sent" "$S/send.json" "$S/reply.json" \
  "$S/live" "$S/out" "$S/err" "$ST"; mkdir -p "$S/val" "$ST"; rm -f hub.conf; }
live() { printf '%s\n' "${TASK:-Reply with the word READY and nothing else.}" | bin/agent --live-test "$@" > "$S/out" 2> "$S/err"; rc=$?; }
ran() { [ -e "$C/runs" ]; }
last_line() { cat "$S/out" "$S/err" | grep -v '^[[:space:]]*$' | tail -1; }
no_value_in() { local f v; for v in "$KEY" "$TOK"; do for f in "$@"; do [ ! -e "$f" ] || ! grep -qF -- "$v" "$f" || fail "a secret value is in $f"; done; done; }

live_test_ready_on_a_ready_line() {
  mkdir -p "$S/live"
  ANTHROPIC_API_KEY="$KEY" ANTHROPIC_AUTH_TOKEN="$KEY" ANTHROPIC_BASE_URL=https://other.example CLAUDE_CODE_OAUTH_TOKEN="$KEY" \
    DEEPSEEK_API_KEY="$KEY" GEMINI_API_KEY="$KEY" CLAUDE_CODE_USE_BEDROCK=1 live anthropic --dir "$S/live"
  assert_eq "$rc" 0 "ready exit: $(cat "$S/err")"; grep -qx READY "$S/out" || fail "the READY line is printed [$(cat "$S/out")]"
  assert_eq "$(cat "$C/cwd")" "$S/live" "runs from the throwaway folder"
  grep -qF "Reply with the word READY" "$C/stdin" || fail "the task reaches the engine on stdin"
  grep -qE '^(ANTHROPIC_|DEEPSEEK_|GEMINI_|CLAUDE_CODE_OAUTH|CLAUDE_CODE_USE_)' "$C/env" && fail "a key or backend variable reached the engine: $(grep -E '^(ANTHROPIC|DEEPSEEK|GEMINI|CLAUDE_CODE)' "$C/env")"
  assert_eq "$(awk 'p{print; exit} $0=="--model"{p=1}' "$C/argv")" haiku "the tiny default model"
  grep -qx -- --safe-mode "$C/argv" && grep -qx 'Read,Grep,Glob' "$C/argv" || fail "the read-only flags of a real run"
  grep -q 'role=live-test folder=- provider=anthropic model=haiku exit=0' journal/delegations-*.md || fail "journaled like a run"
  [ -d "$S/live" ] || fail "a caller's --dir is the caller's to remove"
  # spaces and a CR around READY still count; READY inside a longer line does not
  printf '  READY \r\n' > "$S/reply"; live anthropic; assert_eq "$rc" 0 "READY with spaces and CR"
  printf 'I am READY now\n' > "$S/reply"; live anthropic; assert_eq "$rc" 1 "READY inside a line is not ready"
  last_line | grep -q "no READY line" || fail "the reason is the last line [$(last_line)]"
  no_value_in "$C"/* "$S/out" "$S/err"
}
live_test_reason_hides_keys() {
  printf 'thinking\nerror: bad key %s for bot%s\n' "$KEY" "$TOK" > "$S/reply"; echo 3 > "$S/rc"
  live anthropic; assert_eq "$rc" 1 "engine failure exit"; no_value_in "$S/out" "$S/err"
  last_line | grep -q "live test" || fail "the last line says the live test failed [$(last_line)]"
  last_line | grep -q "hidden" || fail "the reason keeps the engine's last line, keys hidden [$(last_line)]"
}
live_test_folder_is_throwaway() {
  live anthropic; assert_eq "$rc" 0 "own folder: $(cat "$S/err")"; local d; d="$(cat "$C/cwd")"
  case "$d" in "$S/tmp"/*) ;; *) fail "the folder it makes is a temp folder [$d]" ;; esac
  [ ! -e "$d" ] || fail "the folder it made is left behind"
  rm -rf "$C"; live anthropic --dir "$HUB/projects/demo"; assert_eq "$rc" 2 "a hub folder is refused"
  mkdir -p "$S/co" && git -C "$S/co" init -q; live anthropic --dir "$S/co"; assert_eq "$rc" 2 "a checkout is refused"
  mkdir -p "$S/co/sub"; live anthropic --dir "$S/co/sub"; assert_eq "$rc" 2 "a folder inside a checkout is refused"
  live anthropic --dir "$S/none"; assert_eq "$rc" 2 "a missing folder is refused"
  live anthropic --dir relative; assert_eq "$rc" 2 "a relative folder is refused"
  live; assert_eq "$rc" 2 "no provider"; live anthropic extra; assert_eq "$rc" 2 "an extra argument"
  live 'anthropic:gpt-5'; assert_eq "$rc" 2 "not an Anthropic model"; live 'bad;name'; assert_eq "$rc" 2 "a bad provider id"
  ran && fail "the engine ran on bad input"; return 0
}
live_test_gates_but_not_the_allowlist() {
  echo "$KEY" > "$S/val/deepseek-api-key"; conf 'HUB_OWNED_BY_OWNER=1'
  live deepseek; assert_eq "$rc" 0 "deepseek not yet allowed is still tested: $(cat "$S/err")"
  python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); assert s["env"]["ANTHROPIC_BASE_URL"]=="https://api.deepseek.com/anthropic"; assert s["apiKeyHelper"].endswith(" deepseek-api-key")' "$C/settings.json" || fail "the provider settings of a real run"
  assert_eq "$(sed -n 's/^CLAUDE_CONFIG_DIR=//p' "$C/env")" "$HUB/.local/providers/deepseek" "the provider's own config dir"
  rm -rf "$C"; conf '# a client hub'; live deepseek; assert_eq "$rc" 1 "owner-only on a client hub"
  last_line | grep -q "owner's own hubs" || fail "the reason [$(last_line)]"; ran && fail "a refused provider ran"
  rm -f "$S/val/deepseek-api-key"; conf 'HUB_OWNED_BY_OWNER=1'; live deepseek; assert_eq "$rc" 1 "no key"
  last_line | grep -q "bin/secret --set deepseek-api-key" || fail "the missing key is named [$(last_line)]"
  live gemini; assert_eq "$rc" 1 "gemini has no engine yet"; last_line | grep -q "E1" || fail "gemini reason [$(last_line)]"
  live muse; assert_eq "$rc" 1 "muse has no row"; last_line | grep -q "not connected" || fail "muse reason [$(last_line)]"
  ran && fail "a refused provider ran"; return 0
}
anthropic_key_goes_through_the_helper() {
  printf '%s\n' "$KEY" | bin/keys set anthropic >/dev/null 2>&1 || fail "bin/keys set anthropic"
  assert_eq "$(cat "$S/val/anthropic-api-key")" "$KEY" "stored as anthropic-api-key"
  bin/keys | grep -Eq '^anthropic +stored' || fail "listed as stored [$(bin/keys)]"
  live anthropic; assert_eq "$rc" 0 "live test with the key: $(cat "$S/err")"
  python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); assert s["apiKeyHelper"].endswith("'"'"'%s/bin/secret'"'"' anthropic-api-key" % sys.argv[2]), s; assert "ANTHROPIC_BASE_URL" not in s.get("env", {})' "$C/settings.json" "$HUB" || fail "apiKeyHelper settings [$(cat "$C/settings.json")]"
  rm -rf "$C"; printf 'task\n' | bin/agent --role routine --folder projects/demo >/dev/null 2>"$S/err" || fail "a role run with the key: $(cat "$S/err")"
  [ -f "$C/settings.json" ] && grep -q anthropic-api-key "$C/settings.json" || fail "a role run uses the key the same way"
  grep -q '^ANTHROPIC_API_KEY=' "$C/env" && fail "the key is never an environment variable"
  no_value_in "$C"/* "$S/out" "$S/err"
  rm -rf "$C"; bin/keys forget anthropic >/dev/null 2>&1; live anthropic; assert_eq "$rc" 0 "the login without a key"
  [ ! -e "$C/settings.json" ] || fail "no key, no settings (the Claude login)"
}
chat_logs_tail_with_tokens_hidden() {
  bin/chat logs > "$S/out" 2>&1; assert_eq "$?" 0 "no log yet"; assert_eq "$(cat "$S/out")" "" "nothing printed without a log"
  mkdir -p "$ST/logs"; local i; for i in $(seq 1 60); do echo "chat: line $i"; done > "$ST/logs/chat.log"
  printf 'chat: token %s and key %s\n' "$TOK" "$KEY" >> "$ST/logs/chat.log"; echo "chat: last" >> "$ST/logs/chat.log"
  bin/chat logs -n 3 > "$S/out" || fail "logs -n 3"; assert_eq "$(wc -l < "$S/out" | tr -d ' ')" 3 "three lines"
  assert_eq "$(head -1 "$S/out")" "chat: line 60" "the last lines, in order"; assert_eq "$(tail -1 "$S/out")" "chat: last" "ends at the end"
  no_value_in "$S/out"; grep -q hidden "$S/out" || fail "secrets shown as hidden [$(cat "$S/out")]"
  bin/chat logs > "$S/out"; assert_eq "$(wc -l < "$S/out" | tr -d ' ')" 50 "50 lines by default"
  local n; for n in x 0 -1 100001 '3;id'; do bin/chat logs -n "$n" >/dev/null 2>&1; assert_eq "$?" 2 "bad -n [$n]"; done
  bin/chat logs -n >/dev/null 2>&1; assert_eq "$?" 2 "-n without a number"
}
pair() { mkdir -p "$ST/channels/telegram"; printf '{"dmPolicy":"allowlist","allowFrom":[%s],"groups":{}}\n' "$1" > "$ST/channels/telegram/access.json"; }
reply() { printf '{"ok":true,"result":[{"update_id":41,"message":{"chat":{"id":%s},"from":{"id":%s},"text":"hi"}}]}\n' "$1" "$1" > "$S/reply.json"; }
chat_test_waits_for_the_owner() {
  printf '%s' "$TOK" > "$S/val/telegram-bot-token"; pair '"99887766"'; reply 99887766
  AGENT_CHAT_TEST_TIMEOUT=10 bin/chat test telegram > "$S/out" 2>&1; assert_eq "$?" 0 "a reply: $(cat "$S/out")"
  grep -q 'chat_id=99887766' "$S/sent" || fail "sent to the paired owner [$(cat "$S/sent")]"
  assert_eq "$(grep -c 'sendMessage' "$S/curl.cfg")" 1 "one test message"
  grep -q "reply" "$S/out" || fail "says the reply came [$(cat "$S/out")]"
  no_value_in "$S/curl.argv" "$S/out"
  rm -f "$S/sent"; AGENT_CHAT_TEST_TIMEOUT=2 bin/chat test > "$S/out" 2>&1; assert_eq "$?" 1 "no reply in time"
  grep -q "no reply" "$S/out" || fail "the timeout is named [$(cat "$S/out")]"
  rm -f "$S/sent"; reply 555; AGENT_CHAT_TEST_TIMEOUT=2 bin/chat test >/dev/null 2>&1; assert_eq "$?" 1 "a stranger's message is not the reply"
  echo '{"ok":false,"description":"Forbidden: bot was blocked by the user"}' > "$S/send.json"; rm -f "$S/sent"
  AGENT_CHAT_TEST_TIMEOUT=2 bin/chat test > "$S/out" 2>&1; assert_eq "$?" 1 "a failed send"; grep -q "blocked" "$S/out" || fail "the API's reason [$(cat "$S/out")]"
  no_value_in "$S/curl.argv" "$S/out"
}
chat_test_refusals() {
  bin/chat test bogus >/dev/null 2>&1; assert_eq "$?" 2 "unknown channel"
  pair '"99887766"'; bin/chat test >"$S/out" 2>&1; assert_eq "$?" 1 "no token"; grep -q "bin/keys set telegram" "$S/out" || fail "names bin/keys [$(cat "$S/out")]"
  printf '%s' "$TOK" > "$S/val/telegram-bot-token"; rm -rf "$ST/channels"; bin/chat test >"$S/out" 2>&1; assert_eq "$?" 1 "not paired"
  pair '"1","2"'; bin/chat test >/dev/null 2>&1; assert_eq "$?" 1 "more than one owner id"
  pair '"99887766"'; printf 'bad token\n' > "$S/val/telegram-bot-token"; bin/chat test >/dev/null 2>&1; assert_eq "$?" 1 "a token of the wrong shape"
  printf '%s' "$TOK" > "$S/val/telegram-bot-token"; mkdir -p "$ST/chat"
  bash -c 'sleep 30; :' x --channels plugin:telegram --remote-control hub & BG=$!; sleep 0.3
  echo "$BG 2026-11-21T10:00Z" > "$ST/chat/chat.pid"; bin/chat test >"$S/out" 2>&1; assert_eq "$?" 1 "refused while the orchestrator runs"
  grep -q "bin/chat stop" "$S/out" || fail "says to stop it first [$(cat "$S/out")]"; kill "$BG" 2>/dev/null; wait "$BG" 2>/dev/null; BG=""
  [ ! -e "$S/curl.cfg" ] || fail "a refusal reached the Bot API"; return 0
}
snapshot() { (cd "$ST" && find . -print0 2>/dev/null | xargs -0 stat -f '%N %m %z' 2>/dev/null | sort); }
inbox_count_unread() {
  bin/inbox --count > "$S/out"; assert_eq "$?" 0 "no log yet"; assert_eq "$(cat "$S/out")" 0 "nothing unread"
  bin/notify projects/demo "hello demo" >/dev/null || fail "notify"; bin/notify --from projects/demo main "hi main" >/dev/null || fail "notify main"
  assert_eq "$(bin/inbox --count projects/demo)" 1 "one note to the folder"
  assert_eq "$(bin/inbox --count demo)" 1 "a bare folder name"
  assert_eq "$(bin/inbox --count main)" 1 "main: the note to main (its own note is not counted)"
  assert_eq "$(bin/inbox --count projects/other)" 0 "another folder has none"
  mkdir -p "$ST/sessions"; printf 'name=t-7\nfolder=projects/demo\nlauncher=1\n' > "$ST/sessions/t-7.4242"
  assert_eq "$(bin/inbox --count t-7)" 1 "a session name counts for its folder"
  local before; before="$(snapshot)"; bin/inbox --count projects/demo >/dev/null; bin/inbox --count main >/dev/null; bin/inbox --count t-7 >/dev/null
  assert_eq "$(snapshot)" "$before" "--count writes nothing"
  bin/inbox --count nobody >/dev/null 2>&1; assert_eq "$?" 2 "an unknown name"; bin/inbox --count a b >/dev/null 2>&1; assert_eq "$?" 2 "two names"
  # read: a delivery to the folder's session (hook), then 0; a new note, 1 again
  printf '{"session_id":"sess1","tool_name":"Read"}' | bin/inbox projects/demo | grep -q "hello demo" || fail "the hook delivers"
  assert_eq "$(bin/inbox --count projects/demo)" 0 "0 once read"
  bin/notify demo "again" >/dev/null; assert_eq "$(bin/inbox --count projects/demo)" 1 "a new note after reading"
  printf '{"session_id":"sess2","tool_name":"Read"}' | bin/inbox | grep -q "hi main" || fail "main's hook delivers"
  assert_eq "$(bin/inbox --count main)" 0 "main: 0 once read"
}
tickets() { printf '{"ready_to_refine":[{"ref":"3.1","risk":"low"}],"ready_to_start":[%s],"in_progress":[{"ref":"2.1","risk":"low"},{"ref":"2.2","risk":"low"}],"blocked":[]}\n' "$1" > "$S/tickets.json"; }
dispatch_list_is_read_only() {
  tickets '{"ref":"1.1","risk":"low"},{"ref":"1.2","risk":"high"},{"ref":"1.3","risk":"medium"},{"ref":"1.4","risk":"low"},{"ref":"1.5","risk":"low","hitl":true}'
  printf '1.3 projects/demo 1 - - builder busy -\n2.1 projects/demo 2 - - builder busy -\n' > "$S/sessions"
  mkdir -p "$ST/dispatch"; echo "$(date +%s) projects/demo" > "$ST/dispatch/1.4"; echo "1 projects/demo" > "$ST/dispatch/old"
  mkdir "$ST/dispatch.lock" && echo $$ > "$ST/dispatch.lock/pid"   # a running dispatch does not stop a listing
  local tab; tab="$(printf '\t')"; rm -f "$S/work.log" journal/[0-9]*.md
  bin/dispatch --list > "$S/out" 2> "$S/err"; assert_eq "$?" 0 "list exit: $(cat "$S/err")"
  assert_eq "$(cat "$S/out")" "ready${tab}1.1${tab}projects/demo
waiting${tab}1.2${tab}projects/demo
running${tab}1.3${tab}projects/demo
running${tab}1.4${tab}projects/demo
waiting${tab}1.5${tab}projects/demo
running${tab}2.1${tab}projects/demo" "the lines"
  bin/dispatch --list projects/demo > "$S/out2" || fail "one folder"; assert_eq "$(cat "$S/out2")" "$(cat "$S/out")" "the named folder"
  [ ! -e "$S/work.log" ] || fail "a listing started a ticket"; [ -f "$ST/dispatch/old" ] || fail "a listing removed a marker"
  assert_eq "$(cat "$ST/dispatch.lock/pid")" "$$" "a listing leaves the lock alone"; ls journal/[0-9]*.md >/dev/null 2>&1 && fail "a listing journaled"
  bin/dispatch --list projects/other >/dev/null 2>&1; assert_eq "$?" 1 "a folder without BMAD, named"
  bin/dispatch --list projects/none >/dev/null 2>&1; assert_eq "$?" 2 "no such folder"
  bin/dispatch --list a b >/dev/null 2>&1; assert_eq "$?" 2 "two folders"
  touch "$S/nodefail"; bin/dispatch --list >/dev/null 2>&1; assert_eq "$?" 1 "tickets next failing"; rm -f "$S/nodefail"
  rm -rf "$ST/dispatch" "$ST/dispatch.lock"; bin/dispatch --list >/dev/null; [ ! -e "$ST/dispatch" ] || fail "a listing made the marker folder"
}

ALL="live_test_ready_on_a_ready_line live_test_reason_hides_keys live_test_folder_is_throwaway live_test_gates_but_not_the_allowlist anthropic_key_goes_through_the_helper chat_logs_tail_with_tokens_hidden chat_test_waits_for_the_owner chat_test_refusals inbox_count_unread dispatch_list_is_read_only"
for t in ${@:-$ALL}; do reset; "$t" || fail "$t"; done
echo ok
