#!/bin/bash
# Story W1: bin/work opens sub-terminals in ADE (docs/stories/W1-bin-work-opens-sub-terminals-in-ade.md). One function
# per acceptance check; bash tests/test_ade_open.sh [check ...] runs only the named checks (all of them by default).
# Hermetic: a fake $ADE_HOOK_BIN (records its argv, answers with ADE_FAKE_RC), and stub `osascript` (records its argv,
# never runs the launcher), `security` and `claude` sit first on PATH. Real ADE, osascript, claude and the Keychain
# are never reached.
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"
unset CLAUDE_CONFIG_DIR HUB_CLAUDE_CONFIG_DIR AGENT_TERMINAL ADE_HOOK_BIN ADE_HOOK_PORT ADE_HOOK_TOKEN ADE_PTY_ID
S="$(mktemp -d)"; mkdir -p "$S/tmp" "$S/home"; export TMPDIR="$S/tmp" HOME="$S/home"   # never the tester's HOME
trap 'rm -rf "$S" "$(dirname "$HUB")" "$CLAUDE_HOME" "$(dirname "$AGENT_SYNC_LOG")" "$(dirname "$AGENT_SYNC_LOCK")"' EXIT
CUR=""; fail() { echo "FAIL: ${CUR:-setup}: $*" >&2; exit 1; }
CAP="$S/cap"; KEY="sk-W1TEST-$RANDOM$RANDOM-c0ffee"; export CAP W1_KEY="$KEY" W1_ROOT="$S"
# the fake ADE helper. ADE_FAKE_MODE=cli (default) is an ADE with story 9: `help` prints the usage and the line
# `capabilities: command`; =cli-split prints `capabilities: command split` (a later build). =cli-4c is stories 4a/4c
# without 9: the usage only. =cli-near prints only near misses (`capabilities: commands split`, an indented copy). =hook is a build without `ade open`: every
# call is hook mode, which reads stdin to its end, prints {} and exits 0. =hang: `help` never answers. An `open` call
# records its argv, a copy of the launcher (its last word) and answers with ADE_FAKE_RC
cat > "$S/ade-hook" <<'STUB'
#!/bin/bash
mkdir -p "$CAP"
M="${ADE_FAKE_MODE:-cli}"
if [ "$M" = hook ]; then [ "${1:-}" = help ] && echo help >> "$CAP/ade.help" || echo call >> "$CAP/ade.calls"; cat > /dev/null; echo '{}'; exit 0; fi
if [ "${1:-}" = help ]; then echo help >> "$CAP/ade.help"
  [ "$M" = hang ] && exec sleep 60
  echo "usage: ade open [--cwd DIR] [--split right|down] [--name NAME] [--focus] [-- COMMAND [ARG...]]"; echo "       ade help"
  case "$M" in cli) printf '%s\n' "" "capabilities: command" ;; cli-split) printf '%s\n' "" "capabilities: command split" ;;
    cli-near) printf '%s\n' "" "capabilities: commands split" "  capabilities: command" ;; esac
  exit 0; fi
echo call >> "$CAP/ade.calls"
printf '%s\n' "$@" > "$CAP/ade.argv"
last="${@: -1}"; [ -f "$last" ] && cp "$last" "$CAP/ade.launcher"
# the contract's word rule (printable ASCII): anything else is 422, which the CLI reports as exit 1
if printf '%s' "$*" | LC_ALL=C grep -q '[^ -~]'; then echo "ade: command words must be printable ASCII" >&2; exit 1; fi
# like the real CLI: the reason on the first stderr line, then a usage block (bin/work keeps only the first line)
[ -z "${ADE_FAKE_MSG:-}" ] || printf '%s\n' "ade: $ADE_FAKE_MSG" "usage: ade open [--cwd DIR] [--name NAME] [--focus] [-- COMMAND [ARG...]]" "       ade help" >&2
exit "${ADE_FAKE_RC:-0}"
STUB
# stub osascript: records its argv (one per line, then a separator) and the launcher it names; never runs it
cat > "$S/osascript" <<'STUB'
#!/bin/bash
mkdir -p "$CAP"; echo call >> "$CAP/osa.calls"; { printf '%s\n' "$@"; echo ---; } >> "$CAP/osa.argv"
L=$(printf '%s\n' "$@" | grep -o 'bash -l [^"]*' | head -1); L="${L#bash -l }"
[ -f "$L" ] && cp "$L" "$CAP/osa.launcher"
exit 0
STUB
# stub security: one stored account, deepseek-api-key, whose value is the test key
cat > "$S/security" <<'STUB'
#!/bin/bash
op="$1"; shift; acct=""; w=0
while [ $# -gt 0 ]; do case "$1" in -a) acct="$2"; shift 2;; -w) w=1; shift;; *) shift;; esac; done
case "$op" in find-generic-password) [ "$acct" = deepseek-api-key ] || exit 44; [ "$w" = 1 ] && printf '%s' "$W1_KEY"; exit 0;; esac
exit 1
STUB
# the fake engine: a marker and its argv, nothing else written
cat > "$S/claude" <<'STUB'
#!/bin/bash
mkdir -p "$CAP"; echo "FAKE-CLAUDE" > "$CAP/claude.ran"; printf '%s\n' "$@" > "$CAP/claude.argv"
STUB
printf '#!/bin/bash\nexit 0\n' > "$S/not-exec"
chmod +x "$S/ade-hook" "$S/osascript" "$S/security" "$S/claude"
export PATH="$S:$PATH" AGENT_CLAUDE=claude
printf '%s\n' 'HUB_PROVIDERS_ALLOWED="anthropic deepseek"' 'HUB_OWNED_BY_OWNER=1' > hub.conf
bin/new projects/demo >/dev/null; bin/new projects/bare >/dev/null
R="$(mktemp -d "$S/code.XXXXXX")/demo-code"; mkdir -p "$R" && git -C "$R" init -q
printf '| demo-code | %s | main | Alvin | none |\n' "$R" >> projects/demo/ACCESS.md

# inade CMD...: run CMD with the four ADE variables set (the fake helper)
inade() { env ADE_HOOK_BIN="$S/ade-hook" ADE_HOOK_PORT=4711 ADE_HOOK_TOKEN=00ff00ff ADE_PTY_ID=7 "$@"; }
# work CMD...: a fresh capture dir, then CMD with stdout and stderr captured; sets rc
work() { rm -rf "$CAP"; mkdir -p "$CAP"; "$@" > "$S/out" 2> "$S/err"; rc=$?; }
n() { [ -f "$CAP/$1.calls" ] && grep -c . "$CAP/$1.calls" || echo 0; }
argv_L() { tail -1 "$CAP/ade.argv"; }   # the launcher the helper was given
lines() { grep -c . "$1"; }
settings_in() { grep -o -- "--settings '[^']*'" "$1" | head -1 | sed "s/^--settings '//; s/'\$//"; }
osa_terminal() { printf '%s\n' -e "tell application \"Terminal\" to do script \"bash -l $1\"" -e 'tell application "Terminal" to activate' ---; }
osa_iterm() { printf '%s\n' -e "tell application \"iTerm\" to create window with default profile command \"bash -l $1\"" ---; }
osa_L() { grep -o 'bash -l [^"]*' "$CAP/osa.argv" | head -1 | sed 's/^bash -l //'; }
# only_reason FILE WHAT: bin/work printed one work: line carrying ADE's first stderr line and none of its usage block
only_reason() { assert_eq "$(lines "$1")" 1 "$2: stderr lines ($(cat "$1"))"; grep -q '^work: ' "$1" || fail "$2: the line does not start with work:"
  grep -qF "usage: ade" "$1" && fail "$2: ADE's usage block was printed: $(cat "$1")"; grep -qF "ade help" "$1" && fail "$2: ADE's usage block was printed"; return 0; }
no_leftovers() { [ -z "$(ls "$TMPDIR" | grep -E '^agent-(work|settings)\.')" ] || fail "$1: left $(ls "$TMPDIR")"; }
clean_tmp() { rm -f "$TMPDIR"/agent-work.* "$TMPDIR"/agent-settings.*; }

# C1
ade_is_detected_only_with_all_four() {
  local v
  for v in ADE_HOOK_BIN ADE_HOOK_PORT ADE_HOOK_TOKEN ADE_PTY_ID; do
    work inade env -u "$v" bin/work projects/demo; assert_eq "$rc" 0 "$v unset: exit"
    assert_eq "$(n ade)" 0 "$v unset: helper called"; assert_eq "$(n osa)" 1 "$v unset: one window"
    work inade env "$v=" bin/work projects/demo; assert_eq "$rc" 0 "$v empty: exit"
    assert_eq "$(n ade)" 0 "$v empty: helper called"; assert_eq "$(n osa)" 1 "$v empty: one window"
  done
  work inade env ADE_HOOK_BIN="$S/not-exec" bin/work projects/demo
  assert_eq "$(n ade)" 0 "non-executable helper: helper called"; assert_eq "$(n osa)" 1 "non-executable helper: one window"
  work inade env ADE_HOOK_BIN="$S" bin/work projects/demo
  assert_eq "$(n osa)" 1 "a directory as the helper: one window"
  work inade bin/work projects/demo; assert_eq "$(n ade)" 1 "all four set: the helper"; assert_eq "$(n osa)" 0 "all four set: no window"
  clean_tmp
}
# C2
inside_ade_opens_one_sub_terminal_and_no_window() {
  work inade bin/work projects/demo; assert_eq "$rc" 0 "exit"
  assert_eq "$(n ade)" 1 "helper called once"; assert_eq "$(n osa)" 0 "osascript called"
  assert_eq "$(cat "$CAP/ade.help" 2>/dev/null | grep -c .)" 1 "one help probe before the open"
  local L; L="$(argv_L)"
  case "$L" in "$TMPDIR"/agent-work.*) ;; *) fail "the launcher is not bin/work's: [$L]" ;; esac
  assert_eq "$(cat "$CAP/ade.argv")" "$(printf '%s\n' open --cwd "$R" --name demo --focus -- bash -l "$L")" "helper argv"
  clean_tmp
}
# C3
name_is_the_folder_and_cwd_is_the_checkout() {
  work inade bin/work projects/demo/; assert_eq "$rc" 0 "trailing slash: exit"
  assert_eq "$(sed -n 3p "$CAP/ade.argv")" "$R" "--cwd is the checkout"
  assert_eq "$(sed -n 4,5p "$CAP/ade.argv" | tr '\n' ' ')" "--name demo " "trailing slash: --name is the folder"
  work inade bin/work projects/bare; assert_eq "$rc" 0 "no repo: exit"
  assert_eq "$(sed -n 2,5p "$CAP/ade.argv" | tr '\n' '|')" "--cwd|$HUB/projects/bare|--name|bare|" "no repo: the hub folder"
  clean_tmp
}
# C4
ade_and_window_launchers_are_identical() {
  work inade bin/work projects/demo --model opus --prompt "go"; cp "$CAP/ade.launcher" "$S/l.ade" || fail "no ADE launcher"
  work bin/work projects/demo --model opus --prompt "go"; cp "$CAP/osa.launcher" "$S/l.win" || fail "no window launcher"
  cmp -s "$S/l.ade" "$S/l.win" || fail "the launchers differ: $(diff "$S/l.ade" "$S/l.win")"
  bash -n "$S/l.ade" || fail "the launcher is not valid bash"
  assert_eq "$(head -1 "$S/l.ade")" "#!/bin/bash" "shebang"
  assert_eq "$(sed -n 2p "$S/l.ade")" "trap 'rm -f \"\$0\" \"\$R\"' EXIT" "the launcher's trap (itself and its session record)"
  clean_tmp
}
# C5
exit_0_keeps_the_launcher_until_the_shell_runs_it() {
  local L M
  work inade bin/work projects/demo; assert_eq "$rc" 0 "exit"; L="$(argv_L)"
  [ -f "$L" ] || fail "exit 0 deleted the launcher"
  bash "$L" > /dev/null 2>&1; [ -f "$CAP/claude.ran" ] || fail "the launcher did not run the fake claude"
  [ ! -e "$L" ] || fail "the launcher did not remove itself"
  work inade bin/work --provider deepseek projects/demo; assert_eq "$rc" 0 "provider: exit ($(cat "$S/err"))"
  L="$(argv_L)"; M="$(settings_in "$L")"
  [ -f "$L" ] && [ -n "$M" ] && [ -f "$M" ] || fail "provider: exit 0 deleted the launcher [$L] or the settings [$M]"
  rm -f "$CAP/claude.ran"; bash "$L" > /dev/null 2>&1; [ -f "$CAP/claude.ran" ] || fail "provider: the fake claude did not run"
  [ ! -e "$L" ] && [ ! -e "$M" ] || fail "provider: the launcher left itself or the settings behind"
  no_leftovers "after the launchers ran"
}
# C6a (owner, 2026-11-09): ADE refused, so no window outside ADE
exit_1_refuses_with_a_hint_and_opens_no_window() {
  work inade env ADE_FAKE_RC=1 ADE_FAKE_MSG="refused 1" bin/work projects/demo
  assert_eq "$rc" 1 "exit"; assert_eq "$(n ade)" 1 "helper called once"; assert_eq "$(n osa)" 0 "osascript called"
  only_reason "$S/err" "exit 1"
  grep -qF "refused 1" "$S/err" || fail "the line does not carry ADE's error"
  grep -qF "AGENT_TERMINAL=terminal bin/work projects/demo" "$S/err" || fail "no window hint: $(cat "$S/err")"
  no_leftovers "exit 1"
  # a non-ASCII TMPDIR: ADE answers 422 (exit 1), so bin/work refuses too, with no window
  local T="$S/tmp/caf"$'\xc3\xa9'; mkdir -p "$T"
  work inade env TMPDIR="$T" bin/work projects/demo; assert_eq "$rc" 1 "non-ASCII TMPDIR: exit"
  assert_eq "$(n ade)" 1 "non-ASCII TMPDIR: helper called"; assert_eq "$(n osa)" 0 "non-ASCII TMPDIR: osascript called"
  assert_eq "$(lines "$S/err")" 1 "non-ASCII TMPDIR: one line"
  rm -rf "$T"
}
# C6b: ADE unreachable (stale variables, connection refused): one warning line and a window
exit_3_4_fall_back_to_one_window_with_one_warning_line() {
  local c L
  for c in 3 4; do
    work inade env ADE_FAKE_RC=$c ADE_FAKE_MSG="refused $c" bin/work projects/demo
    assert_eq "$rc" 0 "exit $c: bin/work exit"; assert_eq "$(n ade)" 1 "exit $c: helper called once"
    assert_eq "$(n osa)" 1 "exit $c: one window"; L="$(argv_L)"
    assert_eq "$(cat "$CAP/osa.argv")" "$(osa_terminal "$L")" "exit $c: the window runs the same launcher"
    only_reason "$S/err" "exit $c"
    grep -qF "refused $c" "$S/err" || fail "exit $c: the warning does not carry ADE's reason"
    [ -f "$L" ] || fail "exit $c: the launcher handed to the window was deleted"
  done
  clean_tmp
}
# C18: ADE takes the sub-terminal only when its `help` has a line starting `capabilities:` with the word `command`
# (story 9); hook mode (no `ade open`), 4a/4c without 9, near misses and a helper that never answers get the window
an_ade_without_typed_commands_uses_the_window() {
  local m L t0
  for m in hook cli-4c cli-near hang; do
    t0=$SECONDS; work inade env ADE_FAKE_MODE=$m bin/work projects/demo; assert_eq "$rc" 0 "$m: exit ($(cat "$S/err"))"
    [ $((SECONDS - t0)) -lt 15 ] || fail "$m: the probe took $((SECONDS - t0))s"
    assert_eq "$(n ade)" 0 "$m: open was called"; assert_eq "$(n osa)" 1 "$m: one window"
    assert_eq "$(cat "$CAP/ade.help" | grep -c .)" 1 "$m: one help probe"
    L="$(osa_L)"; assert_eq "$(cat "$CAP/osa.argv")" "$(osa_terminal "$L")" "$m: the window argv"
    assert_eq "$(lines "$S/err")" 1 "$m: one info line ($(cat "$S/err"))"; grep -q '^work: ' "$S/err" || fail "$m: the line does not start with work:"
    clean_tmp
    work inade env ADE_FAKE_MODE=$m AGENT_TERMINAL=ade bin/work projects/demo; assert_eq "$rc" 2 "$m, forced ade: exit"
    assert_eq "$(n ade)" 0 "$m, forced ade: open called"; assert_eq "$(n osa)" 0 "$m, forced ade: a window opened"
    grep -qF "capabilities:" "$S/err" || fail "$m, forced ade: the message does not name the capability"
    no_leftovers "$m, forced ade"
  done
  for m in cli cli-split; do
    work inade env ADE_FAKE_MODE=$m bin/work projects/demo; assert_eq "$rc" 0 "$m: exit"
    assert_eq "$(n ade)" 1 "$m: open called"; assert_eq "$(n osa)" 0 "$m: a window opened"
  done
  clean_tmp
  # hook mode reads stdin to its end. With a GNU-style timeout (a fake on PATH that runs the command in the foreground,
  # so it inherits stdin, unlike lib.sh's fallback) and stdin on a pipe that never closes (a Claude Code Bash tool),
  # the probe must not wait on bin/work's stdin
  local T="$S/gnu"; mkdir -p "$T"; printf '#!/bin/bash\nshift\nexec "$@"\n' > "$T/timeout"; chmod +x "$T/timeout"
  rm -rf "$CAP"; mkdir -p "$CAP"; rm -f "$S/w.pid" "$S/w.res"
  { sleep 30 & echo $! > "$S/w.pid"; wait; } | { t0=$SECONDS
    inade env PATH="$T:$PATH" ADE_FAKE_MODE=hook bin/work projects/demo > "$S/out" 2> "$S/err"; echo "$? $((SECONDS - t0))" > "$S/w.res"; } &
  local p=$! i=0; while [ ! -s "$S/w.res" ] && [ $i -lt 150 ]; do sleep 0.1; i=$((i + 1)); done
  kill "$(cat "$S/w.pid")" 2>/dev/null; wait "$p" 2>/dev/null
  [ -s "$S/w.res" ] || fail "hook on an open pipe: bin/work had not finished after 15s"
  set -- $(cat "$S/w.res"); assert_eq "$1" 0 "hook on an open pipe: exit ($(cat "$S/err"))"
  [ "$2" -lt 4 ] || fail "hook on an open pipe: the probe took ${2}s (it read bin/work's stdin)"
  assert_eq "$(n ade)" 0 "hook on an open pipe: open was called"; assert_eq "$(n osa)" 1 "hook on an open pipe: one window"
  clean_tmp
}
# C19: the probe runs only after the folder is checked, so a typo'd folder fails at once (a helper that never answers
# would cost the full 5 s), forced ADE or not
a_bad_folder_fails_before_the_probe() {
  local t0 f
  for f in "" AGENT_TERMINAL=ade; do
    t0=$SECONDS; work inade env $f ADE_FAKE_MODE=hang bin/work projects/no-such-folder
    assert_eq "$rc" 2 "${f:-auto}: exit"; [ $((SECONDS - t0)) -lt 4 ] || fail "${f:-auto}: took $((SECONDS - t0))s"
    [ ! -e "$CAP/ade.help" ] || fail "${f:-auto}: the helper was probed before the folder was checked"
    assert_eq "$(n ade)" 0 "${f:-auto}: open called"; assert_eq "$(n osa)" 0 "${f:-auto}: a window opened"
    grep -qF "usage: bin/work" "$S/err" || fail "${f:-auto}: no usage line: $(cat "$S/err")"
  done
}
# C7
exit_5_prints_the_command_and_keeps_the_launcher() {
  local L M
  work inade env ADE_FAKE_RC=5 ADE_FAKE_MSG="the shell was not ready" bin/work --provider deepseek projects/demo
  assert_eq "$rc" 5 "exit"; assert_eq "$(n osa)" 0 "no window"; L="$(argv_L)"; M="$(settings_in "$L")"
  assert_eq "$(lines "$S/err")" 1 "one stderr line ($(cat "$S/err"))"
  grep -q '^work: ' "$S/err" || fail "the line does not start with work:"
  grep -qF "the shell was not ready" "$S/err" || fail "the line does not name the reason"
  grep -qF "bash -l $L" "$S/err" || fail "the line does not hold the command to run"
  [ -f "$L" ] && [ -f "$M" ] || fail "exit 5 deleted the launcher or the settings"
  clean_tmp
}
# C8
exit_2_fails_and_opens_nothing() {
  local L
  work inade env ADE_FAKE_RC=2 ADE_FAKE_MSG="usage" bin/work --provider deepseek projects/demo
  assert_eq "$rc" 2 "exit"; assert_eq "$(n osa)" 0 "no window"; L="$(argv_L)"
  only_reason "$S/err" "exit 2"; grep -qF "ade: usage" "$S/err" || fail "exit 2: ADE's reason is not shown: $(cat "$S/err")"
  [ ! -e "$L" ] || fail "the launcher was left behind"; no_leftovers "exit 2"
  # an answer outside the contract is a failure too, never a second session
  work inade env ADE_FAKE_RC=7 ADE_FAKE_MSG="odd" bin/work projects/demo
  assert_eq "$rc" 7 "unknown code: exit"; only_reason "$S/err" "unknown code"; assert_eq "$(n osa)" 0 "unknown code: no window"; no_leftovers "unknown code"
}
# C9
a_forced_window_never_calls_ade() {
  local L
  work inade env AGENT_TERMINAL=terminal bin/work projects/demo; assert_eq "$rc" 0 "terminal: exit"
  assert_eq "$(n ade)" 0 "terminal: helper called"; L="$(osa_L)"; assert_eq "$(cat "$CAP/osa.argv")" "$(osa_terminal "$L")" "terminal argv"
  work inade env AGENT_TERMINAL=iterm bin/work projects/demo; assert_eq "$rc" 0 "iterm: exit"
  assert_eq "$(n ade)" 0 "iterm: helper called"; L="$(osa_L)"; assert_eq "$(cat "$CAP/osa.argv")" "$(osa_iterm "$L")" "iterm argv"
  clean_tmp
}
# C9b: an unrecognised AGENT_TERMINAL value inside ADE is auto, so the ADE path
an_unrecognised_value_inside_ade_is_auto() {
  work inade env AGENT_TERMINAL=something-else bin/work projects/demo; assert_eq "$rc" 0 "exit ($(cat "$S/err"))"
  assert_eq "$(n ade)" 1 "the helper's open"; assert_eq "$(n osa)" 0 "a window opened"
  assert_eq "$(cat "$CAP/ade.argv")" "$(printf '%s\n' open --cwd "$R" --name demo --focus -- bash -l "$(argv_L)")" "helper argv"
  clean_tmp
}
# C10
forced_ade_never_falls_back() {
  local c
  for c in 1 3 4; do
    work inade env AGENT_TERMINAL=ade ADE_FAKE_RC=$c ADE_FAKE_MSG="refused $c" bin/work projects/demo
    assert_eq "$rc" "$c" "forced ade, exit $c"; assert_eq "$(n osa)" 0 "forced ade, exit $c: a window opened"
    grep -qF "refused $c" "$S/err" || fail "forced ade, exit $c: no message ($(cat "$S/err"))"
    no_leftovers "forced ade, exit $c"
  done
}
forced_ade_outside_ade_is_exit_2() {
  work env AGENT_TERMINAL=ade bin/work projects/demo; assert_eq "$rc" 2 "exit"
  assert_eq "$(n osa)" 0 "a window opened"; assert_eq "$(n ade)" 0 "helper called"
  local v; for v in ADE_HOOK_BIN ADE_HOOK_PORT ADE_HOOK_TOKEN ADE_PTY_ID; do grep -qF "$v" "$S/err" || fail "the message does not name $v"; done
  no_leftovers "forced ade outside"
}
# C11
outside_ade_is_the_window_path_unchanged() {
  local L
  work bin/work projects/demo; assert_eq "$rc" 0 "exit"; assert_eq "$(n ade)" 0 "helper called"
  L="$(osa_L)"; assert_eq "$(cat "$CAP/osa.argv")" "$(osa_terminal "$L")" "Terminal argv"
  [ -s "$S/err" ] && fail "outside ADE wrote to stderr: $(cat "$S/err")"
  work env AGENT_TERMINAL=iterm bin/work projects/demo; L="$(osa_L)"; assert_eq "$(cat "$CAP/osa.argv")" "$(osa_iterm "$L")" "iTerm argv"
  work env AGENT_TERMINAL=something-else bin/work projects/demo; L="$(osa_L)"; assert_eq "$(cat "$CAP/osa.argv")" "$(osa_terminal "$L")" "unrecognised value outside ADE"
  clean_tmp
}
# C12
dry_run_inside_ade_calls_nothing() {
  local want
  want="$(WORK_DRY=1 bin/work projects/demo --prompt "go")"
  work inade env WORK_DRY=1 bin/work projects/demo --prompt "go"; assert_eq "$rc" 0 "exit"
  assert_eq "$(cat "$S/out")" "$want" "the dry-run command line"
  assert_eq "$(n ade)" 0 "helper called"; assert_eq "$(n osa)" 0 "osascript called"
  [ ! -e "$CAP/ade.help" ] || fail "a dry run probed the helper"
  grep -qF -- "work: if this ADE lists capabilities: command, this runs: $S/ade-hook open --cwd $R --name demo --focus -- bash -l " "$S/err" || fail "the ADE argv is not shown: $(cat "$S/err")"
  no_leftovers "dry run"
}
# C13
provider_session_under_ade_passes_only_the_launcher_path() {
  local L M
  work inade bin/work --provider deepseek projects/demo --prompt "secret plan"; assert_eq "$rc" 0 "exit ($(cat "$S/err"))"
  L="$(argv_L)"; M="$(settings_in "$L")"; [ -n "$M" ] || fail "no settings file in the launcher"
  assert_eq "$(cat "$CAP/ade.argv")" "$(printf '%s\n' open --cwd "$R" --name demo --focus -- bash -l "$L")" "helper argv"
  grep -qF -- "$KEY" "$CAP/ade.argv" && fail "the key is in the helper argv"
  grep -qF -- "$M" "$CAP/ade.argv" && fail "the settings path is in the helper argv"
  grep -qF -- "secret plan" "$CAP/ade.argv" && fail "the prompt is in the helper argv"
  grep -qF -- "ANTHROPIC_" "$CAP/ade.argv" && fail "ANTHROPIC_ is in the helper argv"
  grep -qF -- "$KEY" "$L" "$M" "$S/out" "$S/err" && fail "the key was written or printed"
  grep -qF -- "env -u " "$L" || fail "the launcher has no env -u scrub"
  grep -qF -- "CLAUDE_CONFIG_DIR=" "$L" || fail "the launcher has no CLAUDE_CONFIG_DIR"
  clean_tmp
}
# C14
runs_from_a_non_interactive_shell_without_a_tty() {
  rm -rf "$CAP"; mkdir -p "$CAP"
  inade bash --noprofile --norc bin/work projects/demo < /dev/null 2> "$S/err" | cat > "$S/out"; rc=${PIPESTATUS[0]}
  assert_eq "$rc" 0 "exit ($(cat "$S/err"))"; assert_eq "$(n ade)" 1 "helper called once"; assert_eq "$(n osa)" 0 "osascript called"
  grep -nE '(^|[^a-z_])tty([^a-z_]|$)|\[ -t [0-9]|(^|[;&|] *)read ' bin/work && fail "bin/work needs a terminal"
  clean_tmp
}
# C15: the prompt is in the launcher file only, never in the helper's argv or bin/work's stderr. stdout is not checked on
# purpose: it keeps today's full-command echo, prompt included (owner decision 2026-11-09)
prompt_stays_out_of_the_typed_command() {
  local P=$'Don\'t "say" $HOME `id` W1-MARK\n--second line' L
  work inade bin/work projects/demo --prompt "$P"; assert_eq "$rc" 0 "exit"; L="$(argv_L)"
  grep -qF -- "-- $(printf %q "$P")" "$CAP/ade.launcher" || fail "the prompt is not in the launcher"
  grep -qF W1-MARK "$CAP/ade.argv" && fail "the prompt is in the helper argv"
  assert_eq "$(lines "$CAP/ade.argv")" 10 "the helper argv has exactly ten words"
  grep -qF W1-MARK "$S/err" && fail "the prompt is in bin/work's stderr"
  clean_tmp
}
# C16
the_checks_use_only_stubs() {
  assert_eq "$(command -v osascript)" "$S/osascript" "osascript"
  assert_eq "$(command -v security)" "$S/security" "security"
  assert_eq "$(command -v claude)" "$S/claude" "claude"
  assert_eq "$(inade sh -c 'echo "$ADE_HOOK_BIN"')" "$S/ade-hook" "ADE_HOOK_BIN"
  # make_hub drops a tester's ADE terminal and AGENT_TERMINAL, so no test reaches a real ADE
  local got; got="$(env ADE_HOOK_BIN=/x ADE_HOOK_PORT=1 ADE_HOOK_TOKEN=t ADE_PTY_ID=1 AGENT_TERMINAL=ade \
    bash -c '. "$1/tests/helpers.sh"; make_hub; rm -rf "$(dirname "$HUB")" "$CLAUDE_HOME" "$(dirname "$AGENT_SYNC_LOG")" "$(dirname "$AGENT_SYNC_LOCK")"
    echo "${ADE_HOOK_BIN-}|${ADE_HOOK_PORT-}|${ADE_HOOK_TOKEN-}|${ADE_PTY_ID-}|${AGENT_TERMINAL-}"' _ "$REPO")"
  assert_eq "$got" "||||" "make_hub clears the ADE variables and AGENT_TERMINAL"
}
# C17
readme_documents_the_ade_path() {
  local sec; sec="$(awk '/^## /{p=($0=="## Deep work inside ADE")} p' README.md)"
  [ -n "$sec" ] || fail "README has no 'Deep work inside ADE' section"
  local w; for w in ADE_HOOK_BIN ADE_HOOK_PORT ADE_HOOK_TOKEN ADE_PTY_ID AGENT_TERMINAL=ade "ade open" "--focus" "story 9"; do
    printf '%s\n' "$sec" | grep -qF -- "$w" || fail "the section does not mention $w"; done
  local rows; rows="$(printf '%s\n' "$sec" | grep -E '^\| (`[0-9]|any other )')"
  assert_eq "$(printf '%s\n' "$rows" | grep -c .)" 6 "exit-code rows"
  printf '%s\n' "$rows" | grep -q '^| `0` ' || fail "no row for 0"
  printf '%s\n' "$rows" | grep -q '^| `1` .*AGENT_TERMINAL=terminal bin/work' || fail "no row for 1 with the hint"
  printf '%s\n' "$rows" | grep -q '^| `3`, `4` ' || fail "no row for 3, 4"
  printf '%s\n' "$sec" | grep -qF 'ade help' || fail "the section does not explain the ade help probe"
  printf '%s\n' "$sec" | grep -qF 'capabilities: command' || fail "the section does not name the capability line"
  printf '%s\n' "$rows" | grep -q '^| `2` ' || fail "no row for 2"
  printf '%s\n' "$rows" | grep -q '^| `5` ' || fail "no row for 5"
  printf '%s\n' "$rows" | grep -q '^| any other ' || fail "no row for any other code"
}

ALL="ade_is_detected_only_with_all_four inside_ade_opens_one_sub_terminal_and_no_window name_is_the_folder_and_cwd_is_the_checkout
ade_and_window_launchers_are_identical exit_0_keeps_the_launcher_until_the_shell_runs_it
exit_1_refuses_with_a_hint_and_opens_no_window exit_3_4_fall_back_to_one_window_with_one_warning_line
an_ade_without_typed_commands_uses_the_window exit_5_prints_the_command_and_keeps_the_launcher
exit_2_fails_and_opens_nothing a_forced_window_never_calls_ade an_unrecognised_value_inside_ade_is_auto
a_bad_folder_fails_before_the_probe forced_ade_never_falls_back forced_ade_outside_ade_is_exit_2
outside_ade_is_the_window_path_unchanged dry_run_inside_ade_calls_nothing provider_session_under_ade_passes_only_the_launcher_path
runs_from_a_non_interactive_shell_without_a_tty prompt_stays_out_of_the_typed_command the_checks_use_only_stubs
readme_documents_the_ade_path"
for c in ${*:-$ALL}; do CUR="$c"; "$c"; echo "pass: $c"; done
echo ok
