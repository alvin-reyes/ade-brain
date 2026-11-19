#!/bin/bash
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"; . bin/lib.sh
bin/new projects/demo >/dev/null
R="$(mktemp -d)/demo-code"   # checkouts live outside the hub
mkdir -p "$R" && git -C "$R" init -q
printf '| demo-code | %s | main | Owner | none |\n' "$R" >> projects/demo/ACCESS.md
bin/setup >/dev/null
mem="$CLAUDE_HOME/projects/$(encode_path "$R")/memory"
assert_eq "$(readlink "$mem")" "$HUB/projects/demo/memory" "the repo session shares the folder memory"
out=$(WORK_DRY=1 bin/work projects/demo)
echo "$out" | grep -q "cd '$R'" || fail "work starts in the repo"
echo "$out" | grep -q -- "--settings '$HUB/projects/demo/.claude/settings.json'" || fail "work loads the folder hooks"
grep -qF "$HUB" projects/demo/.claude/settings.json && grep -qF "/bin/session-end" projects/demo/.claude/settings.json && ! grep -q CLAUDE_PROJECT_DIR projects/demo/.claude/settings.json || fail "hooks use the absolute hub path"
grep -q -- "--rules" projects/demo/.claude/settings.json || fail "SessionStart hook loads the shared rules"
grep -qF "/bin/changes projects/demo" projects/demo/.claude/settings.json && grep -q "UserPromptSubmit" projects/demo/.claude/settings.json || fail "new folders hear hub changes (UserPromptSubmit bin/changes <folder>)"
bin/context projects/demo --rules | grep -q '^## Shared rules' || fail "--rules prints Shared rules"
bin/context projects/demo --rules | grep -q '^## Git boundaries' || fail "--rules prints Git boundaries"
bin/context projects/demo --rules | grep -q '^# Context: projects/demo' || fail "--rules ends with the folder context"
bin/context projects/demo | grep -q '^## Shared rules' && fail "plain context has no rules"
[ -z "$(git -C "$R" status --porcelain)" ] || fail "nothing written into the client repo"
[ ! -e repos ] || fail "nothing created under the hub repos/"
# named repo, and a repo that is not in ACCESS.md
WORK_DRY=1 bin/work projects/demo demo-code | grep -q "cd '$R'" || fail "named repo"
WORK_DRY=1 bin/work projects/demo nope >/dev/null 2>&1; assert_eq "$?" "2" "unknown repo name"
# a checkout path with a single quote: the launch command still cds into it
Q="$(mktemp -d)/o'brien-code"; mkdir -p "$Q" && git -C "$Q" init -q
bin/new projects/quote >/dev/null; printf '| quote-code | %s | main | Owner | none |\n' "$Q" >> projects/quote/ACCESS.md
out=$(WORK_DRY=1 bin/work projects/quote) || fail "work with a quote in the checkout path"
assert_eq "$(eval "${out%% && *}" && pwd)" "$(cd "$Q" && pwd)" "launch command cds into a path with a quote"
# negatives
WORK_DRY=1 bin/work projects/nope >/dev/null 2>&1; assert_eq "$?" "2" "unknown folder"
bin/new projects/bare >/dev/null
# a folder with no repo opens in the hub folder itself; a named repo it lacks is still refused
out=$(WORK_DRY=1 bin/work projects/bare); assert_eq "$?" "0" "folder with no repo opens"
echo "$out" | grep -q "^cd '$HUB/projects/bare' && " || fail "no-repo folder starts in the hub folder"
WORK_DRY=1 bin/work projects/bare nope >/dev/null 2>&1; assert_eq "$?" "2" "no-repo folder with a repo name"
# a placeholder row ("(none of its own; ...)") is not a repo: gh is never called, hub folder
bin/new ops/watch >/dev/null
printf '| (none of its own; fixes go to the owning folder'"'"'s repo) | | | | |\n' >> ops/watch/ACCESS.md
G="$(mktemp -d)"; printf '#!/bin/bash\necho called > "%s/gh.called"; exit 1\n' "$G" > "$G/gh"; chmod +x "$G/gh"
out=$(PATH="$G:$PATH" WORK_DRY=1 bin/work ops/watch 2>&1); assert_eq "$?" "0" "placeholder row opens"
[ ! -e "$G/gh.called" ] || fail "placeholder row never clones"
echo "$out" | grep -q "^cd '$HUB/ops/watch' && " || fail "placeholder row starts in the hub folder"
# a missing checkout is cloned to AGENT_CODE_DIR (gh stubbed) and recorded in ACCESS.md
S="$(mktemp -d)"; C="$(mktemp -d)"
printf '#!/bin/bash\necho "$@" > "%s/gh.args"; mkdir -p "$4"\n' "$S" > "$S/gh"; chmod +x "$S/gh"
printf '| ghost | /nonexistent/ghost | main | Owner | none |\n' >> projects/bare/ACCESS.md
out=$(PATH="$S:$PATH" AGENT_CODE_DIR="$C" AGENT_CODE_OWNER=ardata-tech WORK_DRY=1 bin/work projects/bare ghost)
[ -d "$C/ghost" ] || fail "clone created the checkout"
assert_contains "$S/gh.args" "repo clone ardata-tech/ghost $C/ghost" "gh clone args"
assert_contains projects/bare/ACCESS.md "| $C/ghost |" "checkout path recorded in ACCESS.md"
echo "$out" | grep -q "cd '$C/ghost'" || fail "work starts in the cloned repo"
# a non-owner row (empty Checkout, "checkout owned by <folder>") is refused, never cloned
awk '{print} /^\|---/ && !d {print "| shared-code |  | main | Owner | checkout owned by projects/demo |"; d=1}' projects/bare/ACCESS.md > a.tmp && mv a.tmp projects/bare/ACCESS.md
out=$(PATH="$S:$PATH" AGENT_CODE_DIR="$C" WORK_DRY=1 bin/work projects/bare shared-code 2>&1); assert_eq "$?" "2" "non-owner is refused"
echo "$out" | grep -q "owned by projects/demo" || fail "refusal names the owner"
[ ! -d "$C/shared-code" ] || fail "non-owner cloned a duplicate checkout"
# owner/repo names: matched by full name or basename; the clone uses the given owner and the basename dir
awk '{print} /^\|---/ && !d {print "| acme/widget | /nonexistent/widget | main | Owner | none |"; d=1}' projects/bare/ACCESS.md > a.tmp && mv a.tmp projects/bare/ACCESS.md
for w in widget acme/widget; do
  rm -rf "$C/widget"
  out=$(PATH="$S:$PATH" AGENT_CODE_DIR="$C" WORK_DRY=1 bin/work projects/bare "$w" 2>&1) || fail "owner/name row did not resolve by [$w]: $out"
  assert_contains "$S/gh.args" "repo clone acme/widget $C/widget" "owner/name clone args ($w)"
  echo "$out" | grep -q "cd '$C/widget'" || fail "work starts in the cloned owner/name repo"
  # the clone recorded its path; put the missing one back for the next round
  sed -i.bak 's#^| acme/widget | [^|]* |#| acme/widget | /nonexistent/widget |#' projects/bare/ACCESS.md; rm -f projects/bare/ACCESS.md.bak
done
# the folder's specialist agents are passed as --agents JSON
mkdir -p projects/demo/.claude/agents
printf -- '---\nname: tester\ndescription: Runs "tests"\ntools: Read, Bash\nmodel: inherit\n---\nYou test things.\nSecond line.\n' > projects/demo/.claude/agents/tester.md
out=$(WORK_DRY=1 bin/work projects/demo)
echo "$out" | grep -q -- "--agents " || fail "work passes --agents"
j=$(eval "$(printf '%s\n' "$out" | sed -E 's/^cd .* && AGENT_FOLDER=[^ ]* [^ ]* --settings [^ ]* --agents /printf %s /; s/ --remote-control [^ ]*//')")
assert_eq "$(echo "$j" | python3 -c 'import json,sys; d=json.load(sys.stdin)["tester"]; print(d["description"]+"|"+d["prompt"].splitlines()[0]+"|"+",".join(d["tools"]) if isinstance(d["tools"],list) else d["tools"])')" 'Runs "tests"|You test things.|Read,Bash' "agents json"
# apostrophes and double quotes in an agent body must not break the command
printf -- '---\nname: quoty\ndescription: Jared'"'"'s helper\n---\nDon'"'"'t say "hi" \\ there.\n' > projects/demo/.claude/agents/quoty.md
out=$(WORK_DRY=1 bin/work projects/demo)
printf '%s\n' "$out" | bash -n || fail "command with quotes is not valid bash"
chk=$(printf '%s\n' "$out" | sed -E 's/^cd .* && AGENT_FOLDER=[^ ]* [^ ]* --settings [^ ]* --agents /printf %s /; s/ --remote-control [^ ]*//'); [ "$(eval "$chk" | python3 -c 'import json,sys; print(json.load(sys.stdin)["quoty"]["prompt"])')" = "Don't say \"hi\" \\ there." ] || fail "quoted JSON round trip"
# per-task subagent model/effort: bare value = every agent, name=value = one agent (wins over bare)
aj() { printf '%s\n' "$1" | sed -E 's/^cd .* && AGENT_FOLDER=[^ ]* [^ ]* --settings [^ ]* --agents /printf %s /; s/ --(model|effort|remote-control) [^ ]*//g'; }
field() { eval "$(aj "$1")" | python3 -c "import json,sys; print(json.load(sys.stdin)['$2'].get('$3',''))"; }
out=$(WORK_DRY=1 bin/work projects/demo --agent-model haiku --agent-model quoty=opus --agent-effort tester=low)
assert_eq "$(field "$out" tester model)" "haiku" "bare --agent-model sets every agent"
assert_eq "$(field "$out" quoty model)" "opus" "name=model wins for that agent"
assert_eq "$(field "$out" tester effort)" "low" "name=effort sets that agent"
assert_eq "$(field "$out" quoty effort)" "" "effort not set elsewhere"
out=$(WORK_DRY=1 bin/work projects/demo); assert_eq "$(field "$out" tester model)" "" "inherit stays unset without options"
out=$(WORK_DRY=1 bin/work projects/demo --model qwen/qwen3-coder --agent-model tester=qwen3:32b) || fail "OpenRouter/Ollama model names"
echo "$out" | grep -q -- "--model qwen/qwen3-coder --remote-control demo$" || fail "slash model name passes through"
assert_eq "$(field "$out" tester model)" "qwen3:32b" "colon model name for an agent"
WORK_DRY=1 bin/work projects/demo --agent-model nobody=opus >/dev/null 2>&1; assert_eq "$?" "2" "unknown agent name"
WORK_DRY=1 bin/work projects/demo --agent-effort huge >/dev/null 2>&1; assert_eq "$?" "2" "bad agent effort"
WORK_DRY=1 bin/work projects/demo --agent-model 'x;y' >/dev/null 2>&1; assert_eq "$?" "2" "unsafe agent model"
# --prompt with the agents JSON in front of it: still valid bash, still last
out=$(WORK_DRY=1 bin/work projects/demo --prompt 'go -- now')
printf '%s\n' "$out" | bash -n || fail "agents + prompt is not valid bash"
q=$(printf %q 'go -- now'); [[ "$out" == *" -- $q" ]] || fail "agents + prompt: the prompt is last"
rm -rf projects/demo/.claude/agents
WORK_DRY=1 bin/work projects/demo | grep -q -- "--agents" && fail "no agents dir, no --agents"
WORK_DRY=1 bin/work projects/demo --agent-model haiku >/dev/null 2>&1; assert_eq "$?" "2" "--agent-model with no agents"
# per-task model and effort, before or after the folder
out=$(WORK_DRY=1 bin/work --model opus --effort high projects/demo)
echo "$out" | grep -q -- "--model opus --effort high --remote-control demo$" || fail "work passes --model and --effort"
echo "$out" | grep -q "cd '$R'" || fail "options do not shift the folder"
WORK_DRY=1 bin/work projects/demo demo-code --effort low | grep -q -- "--effort low --remote-control demo$" || fail "options after the repo"
WORK_DRY=1 bin/work projects/demo | grep -qE -- "--model|--effort" && fail "no options, no --model/--effort"
# negatives
WORK_DRY=1 bin/work --effort huge projects/demo >/dev/null 2>&1; assert_eq "$?" "2" "unknown effort level"
WORK_DRY=1 bin/work --model 'opus;rm' projects/demo >/dev/null 2>&1; assert_eq "$?" "2" "unsafe model name"
WORK_DRY=1 bin/work projects/demo --model >/dev/null 2>&1; assert_eq "$?" "2" "option without a value"
# --prompt: the session's first message, last on the command after --, surviving quotes, newlines, $ and backticks
P0=$'Don\'t say "hi" $HOME `id`\n--second line'
out=$(WORK_DRY=1 bin/work projects/demo --prompt "$P0" --model opus)
printf '%s\n' "$out" | bash -n || fail "command with a prompt is not valid bash"
assert_eq "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "1" "the prompt stays on one command line"
echo "$out" | grep -q -- "--model opus --remote-control demo -- " || fail "the prompt comes last, after --"
assert_eq "${out%" -- $(printf %q "$P0")"}" "${out%% -- *}" "the command ends with exactly the quoted prompt"
got=$(eval "printf %s $(printf %q "$P0")"); assert_eq "$got" "$P0" "prompt round trip"
WORK_DRY=1 bin/work projects/demo | grep -q -- " -- " && fail "no --prompt, no positional prompt"
WORK_DRY=1 bin/work projects/demo --prompt >/dev/null 2>&1; assert_eq "$?" "2" "--prompt without a value"
WORK_DRY=1 bin/work projects/demo --prompt "" >/dev/null 2>&1; assert_eq "$?" "2" "empty --prompt"
# Remote Control on by default, named after the folder, before any prompt; --no-remote leaves it out
out=$(WORK_DRY=1 bin/work projects/demo)
echo "$out" | grep -q -- " --remote-control demo" || fail "remote control on, named after the folder"
out=$(WORK_DRY=1 bin/work projects/demo --prompt "go")
echo "$out" | grep -q -- " --remote-control demo .*-- go$" || fail "remote control comes before the prompt"
WORK_DRY=1 bin/work --no-remote projects/demo | grep -q -- "--remote-control" && fail "--no-remote leaves it out"
WORK_DRY=1 bin/work projects/demo --no-remote | grep -q -- "--remote-control" && fail "--no-remote after the folder leaves it out"
WORK_DRY=1 bin/work projects/demo/ | grep -q -- " --remote-control demo" || fail "a trailing slash still names the session after the folder"
out=$(WORK_DRY=1 bin/work projects/demo demo-code --no-remote); echo "$out" | grep -q "cd '$R'" || fail "--no-remote after the repo still finds the repo"
echo "$out" | grep -q -- "--remote-control" && fail "--no-remote after the repo leaves it out"
# which claude install: HUB_CLAUDE from hub.conf, else claude; AGENT_CLAUDE or --claude picks another
# (a bare name is resolved on the caller's PATH when it is found there, so allow a directory in front of it)
WORK_DRY=1 bin/work projects/demo | grep -qE "' (/[^ ]*/)?claude --settings" || fail "default is claude"
echo 'HUB_CLAUDE=claude-personal' > hub.conf
WORK_DRY=1 bin/work projects/demo | grep -qE "' (/[^ ]*/)?claude-personal --settings" || fail "hub.conf HUB_CLAUDE picks the install"
rm hub.conf
AGENT_CLAUDE=claude-other WORK_DRY=1 bin/work projects/demo | grep -qE "' (/[^ ]*/)?claude-other --settings" || fail "AGENT_CLAUDE picks the install"
WORK_DRY=1 bin/work --claude claude-acme projects/demo | grep -qE "' (/[^ ]*/)?claude-acme --settings" || fail "--claude picks the install"
# the same install and account as the caller: a bare name runs the claude the caller's PATH finds (a new window's login
# shell may find another install first), and the launcher carries the caller's CLAUDE_CONFIG_DIR, or its absence
C="$(mktemp -d)"; printf '#!/bin/bash\nexit 0\n' > "$C/claude"; chmod +x "$C/claude"; cp "$C/claude" "$C/claude-personal"
PATH="$C:$PATH" WORK_DRY=1 bin/work projects/demo | grep -qF "' $C/claude --settings" || fail "a bare claude runs the caller's install"
PATH="$C:$PATH" AGENT_CLAUDE=claude-personal WORK_DRY=1 bin/work projects/demo | grep -qF "' $C/claude-personal --settings" || fail "a bare wrapper name runs the caller's wrapper"
WORK_DRY=1 bin/work --claude "$C/claude" projects/demo | grep -qF "' $C/claude --settings" || fail "an explicit path is kept"
lch() { local o; o=$(WORK_NO_OPEN=1 "$@" bin/work --no-remote projects/demo) || return $?
  o=$(printf '%s\n' "$o" | sed -n 's/^launcher: //p'); cat "$o"; rm -f "$o"; }
out=$(lch env CLAUDE_CONFIG_DIR="/x/o'cfg") || fail "launcher with a config dir"
assert_eq "$(eval "$(printf '%s\n' "$out" | grep '^export CLAUDE_CONFIG_DIR=')"; echo "$CLAUDE_CONFIG_DIR")" "/x/o'cfg" "the launcher keeps the caller's config dir (account)"
[ "$(printf '%s\n' "$out" | grep -n 'CLAUDE_CONFIG_DIR' | cut -d: -f1)" -lt "$(printf '%s\n' "$out" | grep -n -- '--settings' | cut -d: -f1)" ] || fail "config dir set before claude starts"
out=$(lch env -u CLAUDE_CONFIG_DIR) || fail "launcher without a config dir"
printf '%s\n' "$out" | grep -qx 'unset CLAUDE_CONFIG_DIR' || fail "no caller config dir: the launcher unsets one its login shell has [$out]"
printf '%s\n' "$out" | grep -q '^export CLAUDE_CONFIG_DIR' && fail "no caller config dir: none exported"
WORK_DRY=1 bin/work --claude 'x;rm' projects/demo >/dev/null 2>&1; assert_eq "$?" "2" "unsafe claude command name"
# one session per folder: a running --remote-control <name> process (full command line, as ps -axww shows it) is refused
P="$(mktemp -d)"; long="$(printf 'x%.0s' $(seq 1 3000))"   # a command line far longer than plain ps aux shows
fake_ps() { printf '#!/bin/bash\necho "$*" > "%s/ps.args"\nprintf "%%s\\n" %s\n' "$P" "$1" > "$P/ps"; chmod +x "$P/ps"; }
fake_ps "'  4242 /x/claude --settings s --agents $long --remote-control demo -- go'"
out=$(PATH="$P:$PATH" WORK_DRY=1 bin/work projects/demo 2>&1); assert_eq "$?" "3" "running session refused"
echo "$out" | grep -q "demo is already running (pid 4242)" || fail "refusal names the pid: $out"
echo "$out" | grep -q "^cd " && fail "nothing prepared for a running session"
assert_contains "$P/ps.args" "-axww" "ps shows full command lines"
# negatives: nothing running, a longer name, another folder, a non-claude mention, --force, --no-remote all proceed
for ps_out in "''" "'  7 /x/claude --remote-control demo-x'" "'  8 /x/claude --remote-control other'" "'  9 grep -q --remote-control demo'" "'  10 vim notes about --remote-control'"; do
  fake_ps "$ps_out"; PATH="$P:$PATH" WORK_DRY=1 bin/work projects/demo >/dev/null 2>&1; assert_eq "$?" "0" "proceeds with [$ps_out]"
done
fake_ps "'  4242 /x/claude --remote-control demo'"
for flag in --force --no-remote; do PATH="$P:$PATH" WORK_DRY=1 bin/work $flag projects/demo >/dev/null 2>&1; assert_eq "$?" "0" "$flag proceeds"; done
echo ok
