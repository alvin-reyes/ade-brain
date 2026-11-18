#!/bin/bash
# Token limits (.ade/context/model-defaults.md, "Context and output limits"): focus sessions and the hub root compact
# around 200k and cap inline Bash output; the hub root defaults to the root model; a focus session on another Claude
# account gets the hub's memory links there; the scheduled monitor refreshes the brain index.
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"; . bin/lib.sh
js() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2], "<none>"))' "$1" "$2"; }

# --- the hub root settings (the template's own .claude/settings.json): the two limits, no model, no env ---
assert_eq "$(js "$REPO/.claude/settings.json" autoCompactWindow)" "200000" "hub root compacts around 200k"
assert_eq "$(js "$REPO/.claude/settings.json" bashOutputMaxChars)" "8000" "hub root caps inline Bash output"
assert_eq "$(js "$REPO/.claude/settings.json" model)" "<none>" "the template itself names no model"

# --- bin/init: the root model, and the limits in hub.conf and the hub root settings ---
D="$(mktemp -d)/h1"; bin/init --persona tech-lead --client A --owner B --dest "$D" >/dev/null || fail "init defaults"
assert_eq "$(js "$D/.claude/settings.json" model)" "sonnet" "the hub root defaults to sonnet"
assert_eq "$(. "$D/hub.conf"; echo "$HUB_ROOT_MODEL/$HUB_COMPACT_WINDOW/$HUB_BASH_MAX_CHARS")" "sonnet/200000/8000" "hub.conf defaults"
D2="$(mktemp -d)/h2"; bin/init --persona tech-lead --client A --owner B --dest "$D2" --root-model opus --compact-window 300000 --bash-max-chars 12000 >/dev/null || fail "init with values"
assert_eq "$(js "$D2/.claude/settings.json" model)/$(js "$D2/.claude/settings.json" autoCompactWindow)/$(js "$D2/.claude/settings.json" bashOutputMaxChars)" "opus/300000/12000" "init writes the given values"
assert_eq "$(. "$D2/hub.conf"; echo "$HUB_ROOT_MODEL/$HUB_COMPACT_WINDOW/$HUB_BASH_MAX_CHARS")" "opus/300000/12000" "hub.conf keeps the given values"
D3="$(mktemp -d)/h3"; bin/init --persona tech-lead --client A --owner B --dest "$D3" --root-model "" --compact-window 0 --bash-max-chars 0 >/dev/null || fail "init with limits off"
assert_eq "$(js "$D3/.claude/settings.json" model)/$(js "$D3/.claude/settings.json" autoCompactWindow)/$(js "$D3/.claude/settings.json" bashOutputMaxChars)" "<none>/<none>/<none>" "empty root model and 0 limits leave Claude's defaults"
python3 -c 'import json,sys; sys.exit("env" in json.load(open(sys.argv[1])))' "$D2/.claude/settings.json" || fail "init wrote an env block"
assert_contains "$D2/.claude/settings.json" '"PreCompact"' "init keeps the hub root hooks"
for bad in "--compact-window 50000" "--compact-window 2000000" "--compact-window 20k" "--bash-max-chars 500" "--bash-max-chars 200000" "--root-model x;y"; do
  # shellcheck disable=SC2086
  bin/init --persona tech-lead --client A --owner B --dest "$(mktemp -d)/bad" $bad >/dev/null 2>&1; assert_eq "$?" "2" "init refuses $bad"; done

# --- bin/work: the launcher exports the limits unless the session inherits them (ADE's win) ---
bin/new projects/demo >/dev/null
lch() { local o; o=$(WORK_NO_OPEN=1 "$@" bin/work --no-remote projects/demo) || return $?
  o=$(printf '%s\n' "$o" | sed -n 's/^launcher: //p'); cat "$o"; rm -f "$o"; }
out=$(lch env -u CLAUDE_CODE_AUTO_COMPACT_WINDOW -u BASH_MAX_OUTPUT_LENGTH) || fail "launcher"
echo "$out" | grep -qxF 'export CLAUDE_CODE_AUTO_COMPACT_WINDOW="${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-200000}"' || fail "launcher sets the compact window [$out]"
echo "$out" | grep -qxF 'export BASH_MAX_OUTPUT_LENGTH="${BASH_MAX_OUTPUT_LENGTH:-8000}"' || fail "launcher caps Bash output [$out]"
x=$(echo "$out" | grep -E '^export (CLAUDE_CODE_AUTO_COMPACT_WINDOW|BASH_MAX_OUTPUT_LENGTH)=')
assert_eq "$(env -u CLAUDE_CODE_AUTO_COMPACT_WINDOW -u BASH_MAX_OUTPUT_LENGTH bash -c "$x; echo \$CLAUDE_CODE_AUTO_COMPACT_WINDOW/\$BASH_MAX_OUTPUT_LENGTH")" "200000/8000" "the launcher's defaults"
assert_eq "$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=500000 BASH_MAX_OUTPUT_LENGTH=30000 bash -c "$x; echo \$CLAUDE_CODE_AUTO_COMPACT_WINDOW/\$BASH_MAX_OUTPUT_LENGTH")" "500000/30000" "an inherited value wins"
printf 'HUB_COMPACT_WINDOW=400000\nHUB_BASH_MAX_CHARS=0\n' > hub.conf
out=$(lch env -u CLAUDE_CODE_AUTO_COMPACT_WINDOW) || fail "launcher with hub.conf"
echo "$out" | grep -qF ':-400000}' || fail "launcher uses HUB_COMPACT_WINDOW [$out]"
echo "$out" | grep -q 'BASH_MAX_OUTPUT_LENGTH' && fail "HUB_BASH_MAX_CHARS=0 leaves Claude's default [$out]"
printf 'HUB_COMPACT_WINDOW="1;x"\n' > hub.conf; lch >/dev/null 2>&1; assert_eq "$?" "2" "a bad HUB_COMPACT_WINDOW is refused"
printf 'HUB_BASH_MAX_CHARS=lots\n' > hub.conf; lch >/dev/null 2>&1; assert_eq "$?" "2" "a bad HUB_BASH_MAX_CHARS is refused"
rm -f hub.conf

# --- a focus session on another Claude account gets the hub's memory links there (a real open; the window is stubbed) ---
S="$(mktemp -d)"; printf '#!/bin/bash\necho "$@" >> "%s/osa.log"\n' "$S" > "$S/osascript"; chmod +x "$S/osascript"
A="$(mktemp -d)/hub-account"; B="$(mktemp -d)/session-account"
printf 'HUB_CLAUDE_CONFIG_DIR=%q\n' "$A" > hub.conf
mkdir -p "$B/projects/$(encode_path "$HUB/projects/demo")/memory"; echo "a fact" > "$B/projects/$(encode_path "$HUB/projects/demo")/memory/fact.md"
err=$(env -u CLAUDE_HOME PATH="$S:$PATH" AGENT_TERMINAL=terminal CLAUDE_CONFIG_DIR="$B" bin/work --no-remote projects/demo 2>&1 >/dev/null) || fail "work on another account [$err]"
mB="$B/projects/$(encode_path "$HUB/projects/demo")/memory"
[ -L "$mB" ] && [ "$(readlink "$mB")" = "$HUB/projects/demo/memory" ] || fail "the session's account has the folder's memory link"
[ -L "$B/projects/$(encode_path "$HUB")/memory" ] || fail "the session's account has the hub memory link"
assert_eq "$(cat projects/demo/memory/fact.md 2>/dev/null)" "a fact" "memory already in the session's account is kept in the hub"
echo "$err" | grep -q "^work: .*runs as $B.*linked" || fail "work says it linked the hub's memory into the other account [$err]"
[ -e "$A/projects" ] && fail "work wrote into the hub's account"
err=$(env -u CLAUDE_HOME PATH="$S:$PATH" AGENT_TERMINAL=terminal CLAUDE_CONFIG_DIR="$A" bin/work --no-remote --force projects/demo 2>&1 >/dev/null) || fail "work on the hub's account"
echo "$err" | grep -q "runs as" && fail "no notice on the hub's own account [$err]"
C="$(mktemp -d)/dry-account"; env -u CLAUDE_HOME WORK_DRY=1 CLAUDE_CONFIG_DIR="$C" bin/work --no-remote projects/demo >/dev/null 2>&1
[ -e "$C" ] && fail "a dry run wrote memory links"
rm -f hub.conf

# --- bin/setup --config-dir links into another account; doctor names a shell account without the link ---
rm -f "$CLAUDE_HOME/projects/$(encode_path "$HUB")/memory"   # bin/new ran bin/setup into the hub's account
E="$(mktemp -d)/other"; bin/setup --config-dir "$E" >/dev/null || fail "setup --config-dir"
[ -L "$E/projects/$(encode_path "$HUB")/memory" ] || fail "setup --config-dir links the hub memory there"
[ -L "$CLAUDE_HOME/projects/$(encode_path "$HUB")/memory" ] && fail "setup --config-dir also linked into the hub's account"
F2="$(mktemp -d)/unlinked"; printf 'HUB_CLAUDE_CONFIG_DIR=%q\n' "$A" > hub.conf
out=$(env -u CLAUDE_HOME CLAUDE_CONFIG_DIR="$F2" DOCTOR_OFFLINE=1 bin/doctor)
echo "$out" | grep -qE "^MISSING +hub memory link, this shell's account .*bin/setup --config-dir $F2" || fail "doctor names the shell's account without the link [$out]"
out=$(env -u CLAUDE_HOME CLAUDE_CONFIG_DIR="$E" DOCTOR_OFFLINE=1 bin/doctor)
echo "$out" | grep -qE "^OK +hub memory link, this shell's account" || fail "doctor: the shell's account is linked [$out]"
rm -f hub.conf

# --- bin/monitor refreshes the brain index (incremental), quietly, and still exits 0 when it fails ---
export MONITOR_QUIET=1 AGENT_STATE="$(mktemp -d)"; cp bin/brain bin/brain.real
printf '#!/bin/bash\necho "$@" >> "%s/brain.log"\n' "$AGENT_STATE" > bin/brain; chmod +x bin/brain
out=$(bin/monitor); assert_eq "$?" "0" "monitor with the brain stub"
assert_eq "$(cat "$AGENT_STATE/brain.log" 2>/dev/null)" "index" "monitor runs bin/brain index"
assert_eq "$out" "" "the refresh prints nothing"
printf '#!/bin/bash\nexit 1\n' > bin/brain; bin/monitor >/dev/null 2>&1; assert_eq "$?" "0" "a failed refresh never fails the monitor"
mv bin/brain.real bin/brain
echo ok
