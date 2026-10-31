#!/bin/bash
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"; . bin/lib.sh
# --- the hub's Claude install pins its config dir (memory and skills go there, whatever the shell has) ---
W="$(mktemp -d)"; CD="$(mktemp -d)/.claude-work"
printf '#!/bin/bash\nexport CLAUDE_CONFIG_DIR="%s"\nexec claude "$@"\n' "$CD" > "$W/claude-work"; chmod +x "$W/claude-work"
D="$(mktemp -d)/h1"
PATH="$W:$PATH" bin/init --persona tech-lead --client "Acme" --owner "Sam" --dest "$D" --claude claude-work \
  --model opus --effort high --agent-model sonnet --briefing-model sonnet >/dev/null || fail "init with models failed"
. "$D/hub.conf"
assert_eq "$HUB_CLAUDE_CONFIG_DIR" "$CD" "config dir read from the wrapper"
assert_eq "$HUB_MODEL/$HUB_EFFORT/$HUB_AGENT_MODEL/$HUB_BRIEFING_MODEL" "opus/high/sonnet/sonnet" "model defaults"
assert_contains "$D/.claude/agents/planning.md" "model: sonnet" "folder agents use the agent model"
assert_contains "$D/.claude/agents/tech-lead.md" "model: opus" "the persona agent uses the hub model"
# setup links into the hub's install, even when the shell points at another one
(cd "$D" && env -u HUB -u CLAUDE_HOME CLAUDE_CONFIG_DIR=/tmp/elsewhere bin/setup >/dev/null 2>&1) || fail "setup failed"
[ -L "$CD/projects/$(encode_path "$D")/memory" ] || fail "memory not linked into the hub's install"
[ -e "/tmp/elsewhere/projects/$(encode_path "$D")" ] && fail "linked into the shell's install"
out=$(cd "$D" && env -u HUB -u CLAUDE_HOME DOCTOR_OFFLINE=1 bin/doctor); echo "$out" | grep -qE "^OK +hub memory link" || fail "doctor: link ok [$out]"
rm "$CD/projects/$(encode_path "$D")/memory"
out=$(cd "$D" && env -u HUB -u CLAUDE_HOME DOCTOR_OFFLINE=1 bin/doctor); echo "$out" | grep -qE "^MISSING +hub memory link .*bin/setup" || fail "doctor: missing link"
echo "$out" | grep -qE "claude install +claude-work \($CD\)" || fail "doctor names the install"
# an explicit --claude-config-dir wins; a plain claude command means ~/.claude
D2="$(mktemp -d)/h2"; bin/init --persona qa-test-engineer --client B --owner C --dest "$D2" --claude-config-dir /x/cfg >/dev/null || fail "init 2"
assert_eq "$(. "$D2/hub.conf"; echo "$HUB_CLAUDE_CONFIG_DIR")" "/x/cfg" "explicit config dir"
D3="$(mktemp -d)/h3"; bin/init --persona qa-test-engineer --client B --owner C --dest "$D3" >/dev/null || fail "init 3"
assert_eq "$(. "$D3/hub.conf"; echo "$HUB_CLAUDE_CONFIG_DIR")" "$HOME/.claude" "plain claude uses ~/.claude"
bin/init --persona tech-lead --client B --owner C --model 'opus;rm' --dest "$(mktemp -d)/bad" >/dev/null 2>&1; assert_eq "$?" "2" "unsafe model refused"
bin/init --persona tech-lead --client B --owner C --effort huge --dest "$(mktemp -d)/bad" >/dev/null 2>&1; assert_eq "$?" "2" "bad effort refused"
# --- persona model suggestion: the default when --model is not given ---
grep -q "^model: opus" personas/fractional-cto.md || fail "fractional CTO suggests opus"
assert_eq "$(. "$D3/hub.conf"; echo "$HUB_MODEL")" "$(awk -F': ' '$1=="model"{print $2; exit}' personas/qa-test-engineer.md)" "persona model is the default"
# --- bin/work uses the defaults; the command line wins ---
cd "$D"; R="$(mktemp -d)/code"; mkdir -p "$R"; printf '| acme/code | %s | main | Sam | none |\n' "$R" >> projects/planning/ACCESS.md
mkdir -p projects/planning/.claude/agents; printf -- '---\nname: rev\ndescription: r\n---\nreview\n' > projects/planning/.claude/agents/rev.md
out=$(env -u HUB -u CLAUDE_HOME WORK_DRY=1 bin/work projects/planning)
echo "$out" | grep -q "' claude-work --settings" || fail "work runs the hub's install"
echo "$out" | grep -q -- "--model opus" || fail "work uses HUB_MODEL"; echo "$out" | grep -q -- "--effort high" || fail "work uses HUB_EFFORT"
echo "$out" | grep -q '\\"model\\":\\"sonnet\\"' || fail "agents use HUB_AGENT_MODEL [$out]"
out=$(env -u HUB -u CLAUDE_HOME WORK_DRY=1 bin/work --model haiku --agent-model rev=opus projects/planning)
echo "$out" | grep -q -- "--model haiku" || fail "--model wins"; echo "$out" | grep -q -- "--model opus" && fail "default model also passed"
echo "$out" | grep -q '\\"model\\":\\"opus\\"' || fail "--agent-model name=M wins"
# --- the briefing uses HUB_BRIEFING_MODEL ---
S="$(mktemp -d)"; printf '#!/bin/bash\necho "$@" > "%s/args"; echo ok-brief\n' "$S" > "$S/fc"; chmod +x "$S/fc"
env -u HUB MONITOR_QUIET=1 AGENT_CLAUDE="$S/fc" bin/briefing >/dev/null || fail "briefing failed"
assert_contains "$S/args" "--model sonnet" "briefing model from hub.conf"
echo ok
