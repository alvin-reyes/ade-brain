#!/bin/bash
# bin/chat (story C5): the hub's orchestrator with its channels (Telegram first). Fake claude, fake security, no network.
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"; stub_security; export AGENT_STATE="$(mktemp -d)"
K="123456789:TEST-telegram-token-VALUE-abc"
export AGENT_LAUNCHAGENTS="$(mktemp -d)"; FAKE="$(mktemp -d)"; mkdir -p "$FAKE/bin" "$FAKE/rec"; export FAKE_REC="$FAKE/rec"
# the fake claude records its folder, argv and environment (outside the hub and its state dir). Like the plugin, it
# reads the token from its state folder's .env and writes bot.pid (not with FAKE_NOBOT); a child prints its environment.
cat > "$FAKE/bin/claude" <<'STUB'
#!/bin/bash
pwd -P > "$FAKE_REC/pwd"; printf '%s\n' "$@" > "$FAKE_REC/argv"
printf '%s' "${TELEGRAM_BOT_TOKEN:-}" > "$FAKE_REC/envtoken"; printf '%s' "${TELEGRAM_STATE_DIR:-}" > "$FAKE_REC/statedir"
printf '%s' "${CLAUDE_CONFIG_DIR:-}" > "$FAKE_REC/configdir"; d="${TELEGRAM_STATE_DIR:-/nonexistent}"
if [ -f "$d/.env" ]; then stat -f %Lp "$d/.env" > "$FAKE_REC/envmode"; sed -n 's/^TELEGRAM_BOT_TOKEN=//p' "$d/.env" > "$FAKE_REC/filetoken"; fi
bash -c env > "$FAKE_REC/childenv"
[ -n "${FAKE_NOBOT:-}" ] || echo $$ > "$d/bot.pid"
echo SESSION-OUTPUT-MARKER
[ -z "${FAKE_SLEEP:-}" ] || sleep "$FAKE_SLEEP"
exit 0
STUB
printf '#!/bin/bash\nexit 0\n' > "$FAKE/bin/bun"
printf '#!/bin/bash\necho "$*" >> "$FAKE/launchctl.log"\nexit 0\n' > "$FAKE/bin/launchctl"
chmod +x "$FAKE/bin/claude" "$FAKE/bin/bun" "$FAKE/bin/launchctl"; export FAKE PATH="$FAKE/bin:$PATH"
unset TELEGRAM_BOT_TOKEN TELEGRAM_STATE_DIR HUB_CHAT HUB_CHANNELS CLAUDE_CONFIG_DIR
CH="$AGENT_STATE/channels/telegram"
# access state as the plugin keeps it after pairing; a start without a terminal needs allowlist and no groups
# (the groups default is set apart: Bash 3.2 keeps the backslash in "${3:-{\}}", Bash 5 drops it)
access() { local g="${3:-}"; [ -n "$g" ] || g='{}'; mkdir -p "$1"
  printf '{"dmPolicy": "%s", "allowFrom": ["99887766"], "groups": %s}\n' "$2" "$g" > "$1/access.json"
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$1/access.json" 2>/dev/null || fail "the access.json fixture is not JSON [$(cat "$1/access.json")]"; }
access "$CH" allowlist
reset_rec() { rm -f "$FAKE_REC"/*; }
launched() { [ -f "$FAKE_REC/argv" ]; }
arg_after() { awk -v f="$1" 'p{print; exit} $0==f{p=1}' "$FAKE_REC/argv"; }
wait_for() { local i=0; while ! eval "$1"; do i=$((i+1)); [ $i -lt 100 ] || return 1; sleep 0.1; done; }
PIDF="$AGENT_STATE/chat/chat.pid"

start_launches_channel_session() {
  printf '%s\n' "$K" | bin/keys set telegram >/dev/null 2>&1 || fail "bin/keys set telegram"
  bin/secret --has telegram-bot-token || fail "the token is stored as telegram-bot-token"
  bin/keys | grep -E '^telegram ' | grep -q stored || fail "bin/keys lists telegram as stored [$(bin/keys)]"
  reset_rec; bin/chat start </dev/null >"$FAKE/out" 2>&1 || fail "start [$(cat "$FAKE/out")]"
  launched || fail "start launched nothing"
  assert_eq "$(arg_after --channels)" "plugin:telegram@claude-plugins-official" "the telegram channel is attached"
  assert_eq "$(cat "$FAKE_REC/pwd")" "$(cd "$HUB" && pwd -P)" "runs at the hub root"
  assert_eq "$(arg_after --permission-mode)" "manual" "the chat session asks for every permission by default"
  assert_eq "$(cat "$FAKE_REC/configdir")" "$CLAUDE_HOME" "the hub's Claude config dir (not ~/.claude) is passed on"
  assert_eq "$(arg_after --remote-control)" "hub" "Remote Control on, named after the orchestrator"
  grep -q dangerously "$FAKE_REC/argv" && fail "skip-permissions reached claude"
  echo 'HUB_WORK_MODE=acceptEdits' > hub.conf; reset_rec; bin/chat start </dev/null >/dev/null 2>&1 || fail "start, work mode set"
  assert_eq "$(arg_after --permission-mode)" "manual" "HUB_WORK_MODE is not the chat mode"
  echo 'HUB_CHAT_MODE=plan' > hub.conf; reset_rec; bin/chat start </dev/null >/dev/null 2>&1 || fail "start in plan mode"
  assert_eq "$(arg_after --permission-mode)" "plan" "HUB_CHAT_MODE sets the mode"
  printf 'HUB_ORCHESTRATOR=desk\n' > hub.conf; reset_rec; bin/chat start </dev/null >/dev/null 2>&1 || fail "start named"
  assert_eq "$(arg_after --remote-control)" "desk" "HUB_ORCHESTRATOR names the session"
  printf 'HUB_ORCHESTRATOR="-x"\n' > hub.conf; reset_rec; bin/chat start </dev/null >/dev/null 2>&1; assert_eq "$?" "2" "a bad orchestrator name"
  launched && fail "a bad orchestrator name launched"; rm -f hub.conf
  # the plugin runs on bun: none on PATH refuses before launch
  NS="$(mktemp -d)"; for c in bash sh dirname basename sed grep awk tr cat python3 git ps date mkdir chmod rm wc id sleep stat script env cut head; do
    ln -s "$(command -v "$c")" "$NS/$c"; done; ln -s "$FAKE/bin/claude" "$NS/claude"; ln -s "$(dirname "$STORE")/security" "$NS/security"
  reset_rec; out=$(PATH="$NS" bin/chat start </dev/null 2>&1); assert_eq "$?" "1" "no bun"
  echo "$out" | grep -q bun || fail "the refusal names bun [$out]"; launched && fail "launched without bun"
  # the session's own output never reaches the log without a terminal; bin/chat's own lines do
  reset_rec; bin/chat start </dev/null >"$FAKE/log" 2>&1 || fail "start, logged"
  grep -q SESSION-OUTPUT-MARKER "$FAKE/log" && fail "the session's output is in the log"; grep -q "^chat:" "$FAKE/log" || fail "bin/chat's line is in the log"
  true
}

token_short_lived_file() {
  reset_rec; rm -f "$CH/.env"; bin/chat start </dev/null >"$FAKE/out" 2>&1 || fail "start"
  assert_eq "$(cat "$FAKE_REC/filetoken")" "$K" "the plugin reads the token from its state folder's .env"
  assert_eq "$(cat "$FAKE_REC/envmode")" "600" "the .env is 0600"
  assert_eq "$(cat "$FAKE_REC/envtoken")" "" "the token is not in the session's environment"
  grep -qF "$K" "$FAKE_REC/childenv" && fail "a child of the session sees the token"
  grep -qF "$K" "$FAKE_REC/argv" && fail "the token is in claude's argv"
  grep -qF "$K" "$STORE.argv" && fail "the token is in a security argument"
  grep -qF "$K" "$FAKE/out" && fail "bin/chat printed the token"
  wait_for "[ ! -e '$CH/.env' ]" || fail "the .env was not deleted once the plugin wrote bot.pid"
  grep -rqF --exclude-dir=tests "$K" "$HUB" "$AGENT_STATE" "$CLAUDE_HOME" && fail "the token is left in a file (outside this test)"
  # no bot.pid: deleted after the time limit anyway
  reset_rec; FAKE_NOBOT=1 AGENT_CHAT_ENV_TTL=1 bin/chat start </dev/null >/dev/null 2>&1 || fail "start, no bot.pid"
  wait_for "[ ! -e '$CH/.env' ]" || fail "the .env outlived its time limit"
  # while it runs: no process argument or environment carries it
  reset_rec; FAKE_SLEEP=20 bin/chat start </dev/null >/dev/null 2>&1 & bg=$!
  wait_for "[ -f '$FAKE_REC/argv' ]" || fail "the long session did not start"
  procs="$(ps -axwwe -o command=)"; case "$procs" in *"$K"*) fail "the token is in a running process's argv or environment" ;; esac
  bin/chat stop >/dev/null 2>&1; wait "$bg" 2>/dev/null; true
}

missing_token_refuses() {
  bin/keys forget telegram >/dev/null 2>&1; reset_rec
  out=$(TELEGRAM_BOT_TOKEN=from-shell bin/chat start </dev/null 2>&1); assert_eq "$?" "1" "no token in the Keychain"
  echo "$out" | grep -q "run bin/keys set telegram" || fail "the refusal says how [$out]"
  launched && fail "launched without a Keychain token (a shell token is never used)"
  [ -e "$AGENT_STATE/chat/lock" ] && fail "a refused start kept the lock"
  printf '%s\n' "$K" | bin/keys set telegram >/dev/null 2>&1
}

skip_permissions_refused() {
  reset_rec; bin/chat start --dangerously-skip-permissions </dev/null >/dev/null 2>&1; assert_eq "$?" "2" "the flag as an argument"
  bin/chat start --allow-dangerously-skip-permissions </dev/null >/dev/null 2>&1; assert_eq "$?" "2" "the allow flag as an argument"
  for s in HUB_CHAT_MODE=bypassPermissions HUB_WORK_MODE=bypassPermissions 'HUB_CLAUDE="claude --dangerously-skip-permissions"'; do
    echo "$s" > hub.conf; bin/chat start </dev/null >/dev/null 2>&1; assert_eq "$?" "2" "hub setting $s"; done
  printf '#!/bin/bash\nexec claude --dangerously-skip-permissions "$@"\n' > "$FAKE/bin/yolo"; chmod +x "$FAKE/bin/yolo"
  echo 'HUB_CLAUDE=yolo' > hub.conf; bin/chat start </dev/null >/dev/null 2>&1; assert_eq "$?" "2" "a wrapper that skips permissions"
  echo 'HUB_CHAT_MODE=nonsense' > hub.conf; bin/chat start </dev/null >/dev/null 2>&1; assert_eq "$?" "2" "an unknown mode"
  rm -f hub.conf; launched && fail "a refused start launched claude"; true
}

single_instance() {
  reset_rec; FAKE_SLEEP=30 bin/chat start </dev/null >/dev/null 2>&1 &
  wait_for "[ -f '$FAKE_REC/argv' ] && [ -s '$PIDF' ]" || fail "the session did not start"
  pid=$(awk '{print $1}' "$PIDF"); reset_rec
  out=$(bin/chat start </dev/null 2>&1); assert_eq "$?" "1" "a second start"
  echo "$out" | grep -qw "$pid" || fail "the refusal names the running pid $pid [$out]"
  launched && fail "a second session was launched"; true
}

stop_and_status() {
  pid=$(awk '{print $1}' "$PIDF"); : > "$AGENT_LAUNCHAGENTS/ai.agent-hub.hub.chat.plist"; rm -f "$FAKE/launchctl.log"
  out=$(bin/chat status 2>&1) || fail "status"
  echo "$out" | grep -q "not connected" && fail "a live bot.pid is a connected channel [$out]"
  echo "$out" | grep -q "groups: 0" || fail "status counts groups [$out]"
  echo "$out" | grep -q "running" || fail "status: running [$out]"; echo "$out" | grep -qw "$pid" || fail "status names the pid [$out]"
  echo "$out" | grep -q "since" || fail "status says since when [$out]"
  echo "$out" | grep -q "allowlist" || fail "status names the policy [$out]"
  echo "$out" | grep -qF "99887766" && fail "status showed a Telegram id"; echo "$out" | grep -qF "$K" && fail "status showed the token"
  bin/chat stop >/dev/null 2>&1 || fail "stop"
  kill -0 "$pid" 2>/dev/null && fail "stop returned while pid $pid still runs"; [ -e "$PIDF" ] && fail "stop left the pid file"
  grep -q "disable gui/$(id -u)/ai.agent-hub.hub.chat" "$FAKE/launchctl.log" || fail "stop disables the launchd job [$(cat "$FAKE/launchctl.log")]"
  rm -f "$AGENT_LAUNCHAGENTS/ai.agent-hub.hub.chat.plist"
  out=$(bin/chat status 2>&1); echo "$out" | grep -q "stopped" || fail "status after stop [$out]"
  bin/chat stop >/dev/null 2>&1 || fail "stop when stopped is fine"
  printf '{"dmPolicy": "123456 secret"}\n' > "$CH/access.json"
  out=$(bin/chat status 2>&1); echo "$out" | grep -q "123456" && fail "status repeated an unknown policy value [$out]"
  rm -f "$CH/access.json"; out=$(bin/chat status 2>&1)
  echo "$out" | grep -q "not paired" || fail "status without access state [$out]"
  access "$CH" allowlist '{"-100123": {}, "-100456": {}}'; out=$(bin/chat status 2>&1)
  echo "$out" | grep -q "groups: 2" || fail "status counts 2 groups [$out]"; echo "$out" | grep -q "100123" && fail "status showed a group id"
  access "$CH" allowlist
  # running, but the plugin has not connected (no live bot.pid newer than the session)
  reset_rec; rm -f "$CH/bot.pid"; FAKE_NOBOT=1 FAKE_SLEEP=30 bin/chat start </dev/null >/dev/null 2>&1 &
  wait_for "[ -f '$FAKE_REC/argv' ] && [ -s '$PIDF' ]" || fail "the session did not start"
  out=$(bin/chat status 2>&1); echo "$out" | grep -q "running, channel not connected" || fail "status without bot.pid [$out]"
  bin/chat stop >/dev/null 2>&1
  # a stale pid file (no such process, or not this hub's channel session) is not a running session, and stop spares it
  echo "1 2026-01-01T00:00Z" > "$PIDF"; bin/chat status | grep -q stopped || fail "pid 1 is not the chat session"
  sh -c 'sleep 30; :' x --channels y --remote-control other & f=$!; sleep 0.3; echo "$f 2026-01-01T00:00Z" > "$PIDF"
  bin/chat status | grep -q stopped || fail "another hub's channel session is not this one"
  bin/chat stop >/dev/null 2>&1; kill -0 "$f" 2>/dev/null || fail "stop killed another hub's process"; kill "$f" 2>/dev/null; rm -f "$PIDF"
}

start_lock_and_access() {
  L="$AGENT_STATE/chat/lock"; mkdir -p "$L"; sh -c 'sleep 30; :' bin/chat & f=$!; sleep 0.3; echo "$f" > "$L/pid"
  reset_rec; out=$(bin/chat start </dev/null 2>&1); assert_eq "$?" "1" "a start while another holds the lock"
  echo "$out" | grep -q "lock" || fail "the refusal names the lock [$out]"; launched && fail "launched past a held lock"
  [ -d "$L" ] || fail "a refused start removed another's lock"; kill "$f"; wait "$f" 2>/dev/null
  echo 999999 > "$L/pid"; reset_rec; bin/chat start </dev/null >/dev/null 2>&1 || fail "a stale lock is taken over"; launched || fail "stale lock: nothing launched"
  # without a terminal (launchd) only an allowlist with no groups starts; in a terminal pairing may run
  for a in "pairing" "allowlist|{\"-100123\": {}}" "disabled"; do g=""; case "$a" in *"|"*) g="${a#*|}" ;; esac; access "$CH" "${a%%|*}" "$g"
    reset_rec; out=$(bin/chat start </dev/null 2>&1); assert_eq "$?" "1" "no terminal, access [$a]"
    echo "$out" | grep -qi "allowlist" || fail "the refusal says allowlist [$out]"; launched && fail "launched with access [$a]"; done
  rm -f "$CH/access.json"; reset_rec; bin/chat start </dev/null >/dev/null 2>&1; assert_eq "$?" "1" "no terminal, not paired"
  access "$CH" pairing; reset_rec; script -q /dev/null bin/chat start </dev/null >/dev/null 2>&1; launched || fail "a terminal start while pairing"
  access "$CH" allowlist; rm -rf "$L"
}

same_folder_name() {
  # two hubs whose folders are both named "hub", no HUB_NAME: the second may not share the first's state, Keychain or job
  H1="$HUB"; NH="$(mktemp -d)"; make_hub; H2="$HUB"; access "$NH/.agent-hub/hub/channels/telegram" allowlist
  reset_rec; (unset AGENT_STATE; cd "$H1" && HOME="$NH" HUB="$H1" bin/chat start </dev/null >/dev/null 2>&1) || fail "start, first hub"
  reset_rec; out=$(unset AGENT_STATE; cd "$H2" && HOME="$NH" HUB="$H2" bin/chat start </dev/null 2>&1); assert_eq "$?" "2" "a second hub of the same name"
  echo "$out" | grep -q "HUB_NAME" || fail "the refusal says set HUB_NAME [$out]"; launched && fail "the second hub launched"
  L2="$(mktemp -d)"; echo HUB_CHAT=telegram > "$H2/hub.conf"
  out=$(unset AGENT_STATE; cd "$H2" && HOME="$NH" HUB="$H2" AGENT_LAUNCHAGENTS="$L2" SCHEDULE_DRY=1 bin/schedule install 2>&1)
  [ -f "$L2/ai.agent-hub.hub.chat.plist" ] && fail "the second hub installed a chat job under the first's label [$out]"
  HUB="$H1"; cd "$H1"
}

schedule_installs_chat_job() {
  L="$(mktemp -d)"; C="$L/ai.agent-hub.hub.chat.plist"
  AGENT_LAUNCHAGENTS="$L" SCHEDULE_DRY=1 bin/schedule install >/dev/null || fail "install"
  [ -f "$C" ] && fail "chat job installed without HUB_CHAT=telegram"
  echo HUB_CHAT=telegram > hub.conf
  out=$(AGENT_LAUNCHAGENTS="$L" SCHEDULE_DRY=1 bin/schedule install) || fail "install with chat"
  [ -f "$C" ] || fail "no chat plist with HUB_CHAT=telegram [$out]"
  plutil -lint "$C" >/dev/null || fail "chat plist is not valid"
  assert_contains "$C" "<string>ai.agent-hub.hub.chat</string>" "chat label"
  assert_contains "$C" "<string>$HUB/bin/chat</string><string>start</string>" "the job runs bin/chat start"
  assert_contains "$C" "<key>KeepAlive</key><true/>" "restarted if it dies"
  assert_contains "$C" "$AGENT_STATE/logs/chat.log" "chat log in the state dir"
  grep -q "{{" "$C" && fail "unfilled placeholder in the chat plist"
  grep -qiE "dangerously|bypass" "$C" && fail "the chat job skips permissions"; grep -qF "$K" "$C" && fail "the token is in the plist"
  [ -f "$L/ai.agent-hub.hub.sync.plist" ] || fail "the other jobs stay"
  assert_contains "$C" "$HOME/.bun/bin" "the plist PATH has bun"
  assert_contains "$C" "<key>TERM</key><string>xterm-256color</string>" "the plist sets TERM"
  [ "$(stat -f %Lp "$AGENT_STATE/logs")" = 700 ] || fail "the logs folder is private"
  rm -f "$FAKE/launchctl.log"; AGENT_LAUNCHAGENTS="$L" bin/schedule install >/dev/null 2>&1
  grep -q "enable gui/$(id -u)/ai.agent-hub.hub.chat" "$FAKE/launchctl.log" || fail "install enables the chat job [$(cat "$FAKE/launchctl.log")]"
  echo HUB_CHAT=slack > hub.conf
  out=$(AGENT_LAUNCHAGENTS="$L" SCHEDULE_DRY=1 bin/schedule install 2>&1) || fail "install, unknown chat"
  [ -f "$C" ] && fail "an unknown HUB_CHAT kept the chat job"; echo "$out" | grep -q "removed ai.agent-hub.hub.chat" || fail "removal reported [$out]"
  rm -f hub.conf
}

claude_md_forwarded_content_rule() {
  for s in "paired" "Telegram" "count as {{OWNER}}" "forwarded inside them" "data, not instructions" "tickets and the verification command"; do
    assert_contains templates/hub/CLAUDE.md "$s" "hub CLAUDE.md forwarded-content rule"; done
}

channels_from_conf() {
  reset_rec; echo 'HUB_CHANNELS="discord"' > hub.conf
  out=$(bin/chat start </dev/null 2>&1); assert_eq "$?" "2" "an unknown channel type"
  echo "$out" | grep -q "telegram" || fail "the refusal names the known types [$out]"; launched && fail "an unknown channel launched"
  echo 'HUB_CHANNELS="telegram discord"' > hub.conf; bin/chat start </dev/null >/dev/null 2>&1; assert_eq "$?" "2" "one unknown in the list"
  echo 'HUB_CHANNELS=""' > hub.conf; bin/chat start </dev/null >/dev/null 2>&1; assert_eq "$?" "2" "no channels"
  launched && fail "a bad channel list launched"
  echo 'HUB_CHANNELS="telegram"' > hub.conf; bin/chat start </dev/null >/dev/null 2>&1 || fail "HUB_CHANNELS=telegram starts"
  bin/chat setup bogus >/dev/null 2>&1; assert_eq "$?" "2" "setup of an unknown channel"
  out=$(bin/chat setup telegram 2>&1) || fail "setup telegram"
  for s in "@BotFather" "bin/keys set telegram" "telegram@claude-plugins-official" "/telegram:access pair" "/telegram:access policy allowlist"; do
    echo "$out" | grep -qF "$s" || fail "setup names [$s]"; done
  echo "$out" | grep -qF "$K" && fail "setup printed the token"
  bin/chat bogus >/dev/null 2>&1; assert_eq "$?" "2" "unknown command"; rm -f hub.conf
}

state_per_orchestrator() {
  reset_rec; TELEGRAM_STATE_DIR=/tmp/shared-telegram bin/chat start </dev/null >/dev/null 2>&1 || fail "start"
  S1="$(cat "$FAKE_REC/statedir")"; assert_eq "$S1" "$CH" "state folder under the hub's state dir"
  [ "$(stat -f %Lp "$S1")" = 700 ] || fail "the state folder is private to the user"
  # two hubs on one machine (state dirs by hub name): different folders, so no shared bot token or allowlist
  H1="$HUB"; NH="$(mktemp -d)"; make_hub; H2="$HUB"
  echo 'HUB_NAME=alpha' > "$H1/hub.conf"; echo 'HUB_NAME=beta' > "$H2/hub.conf"
  access "$NH/.agent-hub/alpha/channels/telegram" allowlist; access "$NH/.agent-hub/beta/channels/telegram" allowlist
  reset_rec; (unset AGENT_STATE; cd "$H1" && HOME="$NH" HUB="$H1" bin/chat start </dev/null >/dev/null 2>&1) || fail "start alpha"
  a="$(cat "$FAKE_REC/statedir")"
  reset_rec; (unset AGENT_STATE; cd "$H2" && HOME="$NH" HUB="$H2" bin/chat start </dev/null >/dev/null 2>&1) || fail "start beta"
  b="$(cat "$FAKE_REC/statedir")"
  assert_eq "$a" "$NH/.agent-hub/alpha/channels/telegram" "hub alpha's own state folder"
  assert_eq "$b" "$NH/.agent-hub/beta/channels/telegram" "hub beta's own state folder"
  HUB="$H1"; cd "$H1"; rm -f hub.conf
}

# bash tests/test_chat.sh <check>: run the checks up to and including one (to see each fail on its own)
if [ $# -gt 0 ]; then for c in start_launches_channel_session token_short_lived_file missing_token_refuses skip_permissions_refused \
  single_instance stop_and_status start_lock_and_access same_folder_name schedule_installs_chat_job claude_md_forwarded_content_rule channels_from_conf state_per_orchestrator; do
  [ "$c" = "$1" ] && { "$c"; echo ok; exit 0; }; ( "$c" ) >/dev/null 2>&1; done; fi
start_launches_channel_session; token_short_lived_file; missing_token_refuses; skip_permissions_refused
single_instance; stop_and_status; start_lock_and_access; same_folder_name; schedule_installs_chat_job; claude_md_forwarded_content_rule; channels_from_conf
state_per_orchestrator
echo ok
