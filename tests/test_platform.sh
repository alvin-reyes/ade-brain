#!/bin/bash
# The platform layer (story V1, .ade/context/platform.md): the same hub on macOS and Linux (Ubuntu).
# bash tests/test_platform.sh [check ...] runs only the named checks (all of them by default).
# Linux cases run anywhere with AGENT_PLATFORM=linux and fakes (pass, systemctl, loginctl, tmux) first on PATH; the
# suite also runs on ubuntu-latest in CI. No real secret store, scheduler or terminal is ever touched.
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"
S="$(mktemp -d)"; S="$(cd "$S" && pwd -P)"; mkdir -p "$S/bin" "$S/home" "$S/state" "$S/tmp"
export HOME="$S/home" AGENT_STATE="$S/state" TMPDIR="$S/tmp"
trap 'tmux_kill; rm -rf "$S" "$(dirname "$HUB")" "$CLAUDE_HOME" "$(dirname "$AGENT_SYNC_LOG")" "$(dirname "$AGENT_SYNC_LOCK")"' EXIT
VAL="pl-VALUE-$RANDOM$RANDOM-beef"
# fake pass: a store of plain files under $PASSWORD_STORE_DIR (<name>.gpg), every argv and environment logged
cat > "$S/bin/pass" <<'STUB'
#!/bin/bash
echo "$*" >> "$S/pass.argv"; env >> "$S/pass.env"
D="${PASSWORD_STORE_DIR:-$HOME/.password-store}"
case "$1" in
  insert) shift; f=0; m=0; while [ $# -gt 1 ]; do case "$1" in -m) m=1;; -f) f=1;; esac; shift; done
    mkdir -p "$(dirname "$D/$1")"; cat > "$D/$1.gpg" ;;
  show) [ -f "$D/$2.gpg" ] || { echo "Error: $2 is not in the password store." >&2; exit 1; }; cat "$D/$2.gpg" ;;
  rm) shift; while [ "${1#-}" != "$1" ]; do shift; done; [ -f "$D/$1.gpg" ] || exit 1; rm -f "$D/$1.gpg" ;;
  *) exit 1 ;;
esac
STUB
# fake systemctl / loginctl: argv logged; is-active answers from $S/active
printf '#!/bin/bash\necho "$*" >> "$S/systemctl.argv"\ncase " $* " in *" is-active "*) for a; do u="$a"; done; grep -qx "$u" "$S/active" 2>/dev/null; exit;; esac\nexit 0\n' > "$S/bin/systemctl"
printf '#!/bin/bash\necho "$*" >> "$S/loginctl.argv"\ncase "$1" in show-user) echo "Linger=no";; esac\nexit 0\n' > "$S/bin/loginctl"
# fake tmux: sessions and windows in $S/tmux (one "session window" per line); new-session/new-window run the command in
# the background, as tmux would in its server, and record its pid
cat > "$S/bin/tmux" <<'STUB'
#!/bin/bash
echo "$*" >> "$S/tmux.argv"; T="$S/tmux"; touch "$T"
tgt() { local t="$1"; t="${t#=}"; t="${t%%:*}"; echo "$t"; }
case "$1" in
  has-session) shift; [ "$1" = -t ] && grep -q "^$(tgt "$2") " "$T" ;;
  list-windows) shift; s=""; while [ $# -gt 0 ]; do [ "$1" = -t ] && s="$(tgt "$2")"; shift; done; grep -q "^$s " "$T" || exit 1; awk -v s="$s" '$1==s {print $2}' "$T" ;;
  new-session) shift; n=""; c=""; while [ $# -gt 1 ]; do case "$1" in -s) n="$2"; shift;; -c) c="$2"; shift;; -n) shift;; esac; shift; done
    echo "$n $n" >> "$T"; { (cd "$c" && exec sh -c "$1") >/dev/null 2>&1 </dev/null & echo $! >> "$S/tmux.pids"; } ;;
  new-window) shift; s=""; n=""; c=""; while [ $# -gt 1 ]; do case "$1" in -t) s="$(tgt "$2")"; shift;; -n) n="$2"; shift;; -c) c="$2"; shift;; esac; shift; done
    grep -q "^$s " "$T" || { echo "can't find session: $s" >&2; exit 1; }; echo "$s $n" >> "$T"; { (cd "$c" && exec sh -c "$1") >/dev/null 2>&1 </dev/null & echo $! >> "$S/tmux.pids"; } ;;
  *) exit 0 ;;
esac
STUB
printf '#!/bin/bash\necho "$*" >> "%s/osa.log"\n' "$S" > "$S/bin/osascript"
# a fake claude that stays up a while, so bin/sessions sees the session
printf '#!/bin/bash\n[ "${1:-}" = --version ] && { echo fake; exit 0; }\necho "$*" > "%s/claude.argv"; pwd -P > "%s/claude.cwd"; sleep 20\n' "$S" "$S" > "$S/bin/claude"
chmod +x "$S"/bin/*; export S PATH="$S/bin:$PATH"
tmux_kill() { local p; for p in $(cat "$S/tmux.pids" 2>/dev/null); do pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null; done; : > "$S/tmux.pids" 2>/dev/null; return 0; }
linux() { export AGENT_PLATFORM=linux; }
passstore() { export PASSWORD_STORE_DIR="$S/pw"; mkdir -p "$S/pw"; echo FAKEKEYID > "$S/pw/.gpg-id"; }
filestore() { export PASSWORD_STORE_DIR="$S/no-pass"; }   # no .gpg-id: pass is not initialised, so the file store
. bin/lib.sh

platform_named() {   # AC1
  ( unset AGENT_PLATFORM; . bin/lib.sh; p="$(platform)"; case "$(uname -s)" in Darwin) assert_eq "$p" macos "platform on a Mac";; *) assert_eq "$p" linux "platform on Linux";; esac )
  assert_eq "$(AGENT_PLATFORM=linux bash -c '. bin/lib.sh; platform')" linux "AGENT_PLATFORM override"
  local f t hits=""
  for f in bin/*; do [ "$f" = bin/lib.sh ] && continue; [ -f "$f" ] || continue
    for t in 'security ' launchctl osascript 'stat -f' 'date -j'; do
      grep -v '^[[:space:]]*#' "$f" | grep -q -- "$t" && hits="$hits $f:$t"; done; done
  assert_eq "$hits" "" "macOS-only calls outside bin/lib.sh"
  assert_eq "$(utc_epoch 2026-01-02T03:04:05)" 1767323045 "utc_epoch"
  touch -t 202001020304 "$S/t"; assert_eq "$(file_mtime "$S/t")" "$(python3 -c 'import os,sys; print(int(os.stat(sys.argv[1]).st_mtime))' "$S/t")" "file_mtime"
  chmod 640 "$S/t"; assert_eq "$(file_mode "$S/t")" 640 "file_mode"
  assert_eq "$(file_inode "$S/t")" "$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_ino)' "$S/t")" "file_inode"
}
linux_secrets_pass() {   # AC2, AC3
  linux; passstore; rm -f "$S/pass.argv" "$S/pass.env"
  assert_eq "$(secret_store)" pass "pass when installed and initialised"
  printf '%s\n' "$VAL" | bin/secret --set api-token 2> "$S/err" || fail "set: $(cat "$S/err")"
  bin/secret --has api-token || fail "--has after set"
  assert_eq "$(bin/secret api-token)" "$VAL" "read back"
  bin/secret --list | grep -qx api-token || fail "--list names it"
  grep -qF -- "$VAL" "$S/pass.argv" && fail "the value reached a pass argument"
  grep -qF -- "$VAL" "$S/pass.env" && fail "the value is in pass's environment"
  grep -qF -- "$VAL" "$S/err" && fail "set printed the value"
  [ -f "$S/pw/ade/hub/api-token.gpg" ] || fail "stored under ade/<service>/<name>"
  bin/secret --forget api-token 2>/dev/null || fail "forget"; bin/secret --has api-token && fail "--has after forget"
  bin/secret api-token 2> "$S/err"; assert_eq "$?" 1 "missing"; assert_contains "$S/err" "not stored" "hint"
  unset AGENT_PLATFORM PASSWORD_STORE_DIR
}
linux_secrets_file() {   # AC2, AC3
  linux; filestore; local D="$HOME/.config/ade/secrets"
  assert_eq "$(secret_store)" file "the file store without pass"
  printf '%s\n' "$VAL" | bin/secret --set api-token 2> "$S/err" || fail "set: $(cat "$S/err")"
  assert_eq "$(file_mode "$D")" 700 "secrets dir 0700"; assert_eq "$(file_mode "$D/hub")" 700 "service dir 0700"
  assert_eq "$(file_mode "$D/hub/api-token")" 600 "value file 0600"
  bin/secret --has api-token || fail "--has"; assert_eq "$(bin/secret api-token)" "$VAL" "read back"
  bin/secret --list | grep -qx api-token || fail "--list"
  V='sk "quoted" back\\slash $HOME `x`'; printf '%s\n' "$V" | bin/secret --set odd 2>/dev/null; assert_eq "$(bin/secret odd)" "$V" "shell characters survive"
  printf '\n' | bin/secret --set empty 2>/dev/null; assert_eq "$?" 1 "empty refused"
  printf 'x\n' | bin/secret --set '../escape' 2>/dev/null; assert_eq "$?" 2 "a name with a path is refused"
  chmod 755 "$D"; bin/secret api-token > "$S/out" 2> "$S/err"; assert_eq "$?" 1 "a 0755 store refuses to run"
  assert_contains "$S/err" "0700" "it says why"; grep -qF -- "$VAL" "$S/out" && fail "a value was read from a loose store"
  printf 'y\n' | bin/secret --set other 2>/dev/null; assert_eq "$?" 1 "set refuses too"; chmod 700 "$D"
  chmod 644 "$D/hub/api-token"; bin/secret api-token >/dev/null 2>&1; assert_eq "$?" 1 "a 0644 value file is refused"; chmod 600 "$D/hub/api-token"
  bin/secret --forget api-token 2>/dev/null; bin/secret --has api-token && fail "--has after forget"
  DOCTOR_OFFLINE=1 bin/doctor | grep -i 'secrets' | grep -q 'weaker' || fail "doctor says the file store is the weaker one: $(DOCTOR_OFFLINE=1 bin/doctor | grep -i secret)"
  printf '%s\n' "$VAL" | bin/keys set gemini 2>/dev/null || fail "bin/keys set on Linux"; assert_eq "$(bin/secret gemini-api-key)" "$VAL" "keys through the store"
  bin/keys | grep -q '^gemini  *stored' || fail "bin/keys lists it"
  unset AGENT_PLATFORM PASSWORD_STORE_DIR
}
linux_schedule() {   # AC4
  linux; rm -f "$S/systemctl.argv" "$S/loginctl.argv"; local U="$S/units"; export AGENT_SYSTEMD_USER_DIR="$U"
  bin/schedule install > "$S/out" 2>&1 || fail "install: $(cat "$S/out")"
  local j; for j in briefing monitor sync; do
    [ -f "$U/ade-hub-$j.service" ] && [ -f "$U/ade-hub-$j.timer" ] || fail "$j units: $(ls "$U")"
    grep -q "^ExecStart=/bin/bash \"$HUB/bin/$j\"" "$U/ade-hub-$j.service" || fail "$j runs this hub's bin/$j: $(cat "$U/ade-hub-$j.service")"
    grep -q "enable --now ade-hub-$j.timer" "$S/systemctl.argv" || fail "$j timer enabled"; done
  grep -q 'ExecStart=.*bin/sync" --auto$' "$U/ade-hub-sync.service" || fail "sync --auto"
  grep -q '^OnCalendar=Mon..Fri \*-\*-\* 08:00:00$' "$U/ade-hub-briefing.timer" || fail "weekday briefing: $(cat "$U/ade-hub-briefing.timer")"
  grep -q '^OnCalendar=\*:0/30$' "$U/ade-hub-monitor.timer" || fail "monitor every 30 minutes"
  grep -q "$AGENT_STATE/logs/monitor.log" "$U/ade-hub-monitor.service" || fail "log in the state dir"
  grep -q -- "--user daemon-reload" "$S/systemctl.argv" || fail "daemon-reload"
  grep -q "enable-linger" "$S/loginctl.argv" || fail "linger, so the jobs run without a login"
  [ ! -e "$U/ade-hub-chat.service" ] || fail "no chat without HUB_CHAT"
  echo 'HUB_CHAT=telegram' > hub.conf; bin/schedule install >/dev/null 2>&1
  grep -q "^ExecStart=/bin/bash \"$HUB/bin/chat\" start$" "$U/ade-hub-chat.service" || fail "chat service"
  grep -q '^Restart=always' "$U/ade-hub-chat.service" || fail "chat restarts"
  grep -q "enable --now ade-hub-chat.service" "$S/systemctl.argv" || fail "chat enabled"
  printf 'HUB_AUTO_SYNC=0\n' > hub.conf; bin/schedule install > "$S/out" 2>&1
  [ ! -e "$U/ade-hub-sync.timer" ] && [ ! -e "$U/ade-hub-chat.service" ] || fail "sync and chat removed: $(ls "$U")"
  echo ade-hub-monitor.timer > "$S/active"; bin/schedule status > "$S/out"
  grep -q '^loaded  ade-hub-monitor.timer' "$S/out" && grep -q '^absent  ade-hub-briefing.timer' "$S/out" || fail "status: $(cat "$S/out")"
  bin/schedule uninstall > "$S/out" 2>&1; [ -z "$(ls "$U" 2>/dev/null)" ] || fail "uninstall left: $(ls "$U")"
  grep -q "disable --now ade-hub-monitor.timer" "$S/systemctl.argv" || fail "disabled on uninstall"
  rm -f hub.conf; unset AGENT_PLATFORM AGENT_SYSTEMD_USER_DIR
}
linux_work_tmux() {   # AC5, and AGENT_TERMINAL=tmux on either platform (ade-cli `ade ui`)
  linux; rm -f "$S/tmux" "$S/tmux.argv" "$S/osa.log"; bin/new projects/demo >/dev/null 2>&1
  bin/work --no-remote projects/demo > "$S/out" 2> "$S/err" || fail "work: $(cat "$S/err")"
  grep -q "^new-session -d -s demo -c $HUB/projects/demo bash -l " "$S/tmux.argv" || fail "a detached session named after the folder: $(cat "$S/tmux.argv")"
  grep -q "tmux attach -t demo" "$S/err" || fail "says how to attach: $(cat "$S/err")"
  [ ! -e "$S/osa.log" ] || fail "osascript on Linux"
  local i; for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do [ -e "$S/claude.argv" ] && break; sleep 0.25; done
  bin/sessions | awk 'NR>1 {print $1, $2}' | grep -qx 'demo projects/demo' || fail "bin/sessions lists it: $(bin/sessions)"
  bin/work --no-remote projects/demo > "$S/out" 2> "$S/err"; assert_eq "$?" 3 "a second session for the folder"
  assert_contains "$S/err" "already" "it says so"
  tmux_kill; rm -f "$S/tmux" "$S/claude.argv"
  echo "ade-hub orchestrator" > "$S/tmux"; : > "$S/tmux.argv"
  bin/work --no-remote --name t-1.1 projects/demo 2> "$S/err" >/dev/null || fail "work into the hub session: $(cat "$S/err")"
  grep -q "^new-window -d -t =ade-hub: -n t-1_1 -c $HUB/projects/demo bash -l " "$S/tmux.argv" || fail "a window in ade-<hub>: $(cat "$S/tmux.argv")"
  grep -q "new-session" "$S/tmux.argv" && fail "no new session when ade-<hub> exists"
  bin/work --no-remote --name t-1.1 projects/demo >/dev/null 2>&1; assert_eq "$?" 3 "the window name is taken"
  tmux_kill; unset AGENT_PLATFORM; rm -f "$S/tmux"; : > "$S/tmux.argv"
  AGENT_TERMINAL=tmux bin/work --no-remote projects/demo >/dev/null 2>&1 || fail "AGENT_TERMINAL=tmux on this platform"
  grep -q "^new-session -d -s demo " "$S/tmux.argv" || fail "tmux on request: $(cat "$S/tmux.argv")"
  [ ! -e "$S/osa.log" ] || fail "no window with AGENT_TERMINAL=tmux"
  tmux_kill; rm -f "$S/tmux"
  linux; AGENT_TERMINAL=iterm bin/work --no-remote projects/demo >/dev/null 2>&1; assert_eq "$?" 2 "no Terminal or iTerm on Linux"
  WORK_DRY=1 bin/work --no-remote projects/demo 2>&1 | grep -q "tmux new-session -d -s demo" || fail "a dry run says what it would open"
  unset AGENT_PLATFORM
}
linux_monitor_event() {   # AC6
  linux; rm -f "$S/osa.log"; mkdir -p ops/demo/monitors.d
  printf '#!/bin/bash\necho "disk"\necho "ALERT disk 97%%"\n' > ops/demo/monitors.d/d.sh; chmod +x ops/demo/monitors.d/d.sh
  bin/monitor; [ ! -e "$S/osa.log" ] || fail "osascript on Linux"
  python3 - "$AGENT_STATE/events.jsonl" <<'PY' || fail "an ALERT event in the hub log: $(cat "$AGENT_STATE/events.jsonl" 2>/dev/null)"
import json, sys
ev = [json.loads(l) for l in open(sys.argv[1])]
assert any(e.get("from") == "ops/demo" and e.get("to") == "main" and e.get("text", "").startswith("ALERT") and "disk 97%" in e["text"] for e in ev), ev
PY
  n="$(wc -l < "$AGENT_STATE/events.jsonl")"; bin/monitor; assert_eq "$(wc -l < "$AGENT_STATE/events.jsonl")" "$n" "a standing ALERT writes once"
  rm -rf ops/demo/monitors.d; unset AGENT_PLATFORM
}
ci_has_linux_job() {   # AC7
  python3 - "$REPO/.github/workflows/ci.yml" <<'PY' || fail "ci.yml runs the suite on ubuntu-latest: $(cat "$REPO/.github/workflows/ci.yml")"
import re, sys
t = open(sys.argv[1]).read()
jobs = re.findall(r"uses: better-ade/\.github/\.github/workflows/verify\.yml@\S+\s*\n\s*with: \{([^}]*)\}", t)
assert any("ubuntu-latest" in j and "bash tests/run.sh" in j for j in jobs), jobs
assert any("macos-latest" in j and "bash tests/run.sh" in j for j in jobs), jobs
PY
}

ALL="platform_named linux_secrets_pass linux_secrets_file linux_schedule linux_work_tmux linux_monitor_event ci_has_linux_job"
for t in ${@:-$ALL}; do "$t"; done
echo ok
