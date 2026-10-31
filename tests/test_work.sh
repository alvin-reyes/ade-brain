#!/bin/bash
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"; . bin/lib.sh
bin/new projects/demo >/dev/null
R="$(mktemp -d)/demo-code"   # checkouts live outside the hub
mkdir -p "$R" && git -C "$R" init -q
printf '| demo-code | %s | main | Alvin | none |\n' "$R" >> projects/demo/ACCESS.md
bin/setup >/dev/null
mem="$CLAUDE_HOME/projects/$(encode_path "$R")/memory"
assert_eq "$(readlink "$mem")" "$HUB/projects/demo/memory" "the repo session shares the folder memory"
out=$(WORK_DRY=1 bin/work projects/demo)
echo "$out" | grep -q "cd '$R'" || fail "work starts in the repo"
echo "$out" | grep -q -- "--settings '$HUB/projects/demo/.claude/settings.json'" || fail "work loads the folder hooks"
grep -qF "$HUB" projects/demo/.claude/settings.json && grep -qF "/bin/session-end" projects/demo/.claude/settings.json && ! grep -q CLAUDE_PROJECT_DIR projects/demo/.claude/settings.json || fail "hooks use the absolute hub path"
grep -q -- "--rules" projects/demo/.claude/settings.json || fail "SessionStart hook loads the shared rules"
bin/context projects/demo --rules | grep -q '^## Shared rules' || fail "--rules prints Shared rules"
bin/context projects/demo --rules | grep -q '^## Git boundaries' || fail "--rules prints Git boundaries"
bin/context projects/demo --rules | grep -q '^# Context: projects/demo' || fail "--rules ends with the folder context"
bin/context projects/demo | grep -q '^## Shared rules' && fail "plain context has no rules"
[ -z "$(git -C "$R" status --porcelain)" ] || fail "nothing written into the client repo"
[ ! -e repos ] || fail "nothing created under the hub repos/"
# named repo, and a repo that is not in ACCESS.md
WORK_DRY=1 bin/work projects/demo demo-code | grep -q "cd '$R'" || fail "named repo"
WORK_DRY=1 bin/work projects/demo nope >/dev/null 2>&1; assert_eq "$?" "2" "unknown repo name"
# negatives
WORK_DRY=1 bin/work projects/nope >/dev/null 2>&1; assert_eq "$?" "2" "unknown folder"
bin/new projects/bare >/dev/null
WORK_DRY=1 bin/work projects/bare >/dev/null 2>&1; assert_eq "$?" "2" "folder with no repo"
# a missing checkout is cloned to AGENT_CODE_DIR (gh stubbed) and recorded in ACCESS.md
S="$(mktemp -d)"; C="$(mktemp -d)"
printf '#!/bin/bash\necho "$@" > "%s/gh.args"; mkdir -p "$4"\n' "$S" > "$S/gh"; chmod +x "$S/gh"
printf '| ghost | /nonexistent/ghost | main | Alvin | none |\n' >> projects/bare/ACCESS.md
out=$(PATH="$S:$PATH" AGENT_CODE_DIR="$C" AGENT_CODE_OWNER=ardata-tech WORK_DRY=1 bin/work projects/bare ghost)
[ -d "$C/ghost" ] || fail "clone created the checkout"
assert_contains "$S/gh.args" "repo clone ardata-tech/ghost $C/ghost" "gh clone args"
assert_contains projects/bare/ACCESS.md "| $C/ghost |" "checkout path recorded in ACCESS.md"
echo "$out" | grep -q "cd '$C/ghost'" || fail "work starts in the cloned repo"
# a non-owner row (empty Checkout, "checkout owned by <folder>") is refused, never cloned
awk '{print} /^\|---/ && !d {print "| shared-code |  | main | Alvin | checkout owned by projects/demo |"; d=1}' projects/bare/ACCESS.md > a.tmp && mv a.tmp projects/bare/ACCESS.md
out=$(PATH="$S:$PATH" AGENT_CODE_DIR="$C" WORK_DRY=1 bin/work projects/bare shared-code 2>&1); assert_eq "$?" "2" "non-owner is refused"
echo "$out" | grep -q "owned by projects/demo" || fail "refusal names the owner"
[ ! -d "$C/shared-code" ] || fail "non-owner cloned a duplicate checkout"
# owner/repo names: matched by full name or basename; the clone uses the given owner and the basename dir
awk '{print} /^\|---/ && !d {print "| acme/widget | /nonexistent/widget | main | Alvin | none |"; d=1}' projects/bare/ACCESS.md > a.tmp && mv a.tmp projects/bare/ACCESS.md
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
j=$(eval "$(printf '%s\n' "$out" | sed -E 's/^cd .* && AGENT_FOLDER=[^ ]* [^ ]* --settings [^ ]* --agents /printf %s /')")
assert_eq "$(echo "$j" | python3 -c 'import json,sys; d=json.load(sys.stdin)["tester"]; print(d["description"]+"|"+d["prompt"].splitlines()[0]+"|"+",".join(d["tools"]) if isinstance(d["tools"],list) else d["tools"])')" 'Runs "tests"|You test things.|Read,Bash' "agents json"
# apostrophes and double quotes in an agent body must not break the command
printf -- '---\nname: quoty\ndescription: Jared'"'"'s helper\n---\nDon'"'"'t say "hi" \\ there.\n' > projects/demo/.claude/agents/quoty.md
out=$(WORK_DRY=1 bin/work projects/demo)
printf '%s\n' "$out" | bash -n || fail "command with quotes is not valid bash"
chk=$(printf '%s\n' "$out" | sed -E 's/^cd .* && AGENT_FOLDER=[^ ]* [^ ]* --settings [^ ]* --agents /printf %s /'); [ "$(eval "$chk" | python3 -c 'import json,sys; print(json.load(sys.stdin)["quoty"]["prompt"])')" = "Don't say \"hi\" \\ there." ] || fail "quoted JSON round trip"
# per-task subagent model/effort: bare value = every agent, name=value = one agent (wins over bare)
aj() { printf '%s\n' "$1" | sed -E 's/^cd .* && AGENT_FOLDER=[^ ]* [^ ]* --settings [^ ]* --agents /printf %s /; s/ --(model|effort) [^ ]*//g'; }
field() { eval "$(aj "$1")" | python3 -c "import json,sys; print(json.load(sys.stdin)['$2'].get('$3',''))"; }
out=$(WORK_DRY=1 bin/work projects/demo --agent-model haiku --agent-model quoty=opus --agent-effort tester=low)
assert_eq "$(field "$out" tester model)" "haiku" "bare --agent-model sets every agent"
assert_eq "$(field "$out" quoty model)" "opus" "name=model wins for that agent"
assert_eq "$(field "$out" tester effort)" "low" "name=effort sets that agent"
assert_eq "$(field "$out" quoty effort)" "" "effort not set elsewhere"
out=$(WORK_DRY=1 bin/work projects/demo); assert_eq "$(field "$out" tester model)" "" "inherit stays unset without options"
out=$(WORK_DRY=1 bin/work projects/demo --model qwen/qwen3-coder --agent-model tester=qwen3:32b) || fail "OpenRouter/Ollama model names"
echo "$out" | grep -q -- "--model qwen/qwen3-coder$" || fail "slash model name passes through"
assert_eq "$(field "$out" tester model)" "qwen3:32b" "colon model name for an agent"
WORK_DRY=1 bin/work projects/demo --agent-model nobody=opus >/dev/null 2>&1; assert_eq "$?" "2" "unknown agent name"
WORK_DRY=1 bin/work projects/demo --agent-effort huge >/dev/null 2>&1; assert_eq "$?" "2" "bad agent effort"
WORK_DRY=1 bin/work projects/demo --agent-model 'x;y' >/dev/null 2>&1; assert_eq "$?" "2" "unsafe agent model"
rm -rf projects/demo/.claude/agents
WORK_DRY=1 bin/work projects/demo | grep -q -- "--agents" && fail "no agents dir, no --agents"
WORK_DRY=1 bin/work projects/demo --agent-model haiku >/dev/null 2>&1; assert_eq "$?" "2" "--agent-model with no agents"
# per-task model and effort, before or after the folder
out=$(WORK_DRY=1 bin/work --model opus --effort high projects/demo)
echo "$out" | grep -q -- "--model opus --effort high$" || fail "work passes --model and --effort"
echo "$out" | grep -q "cd '$R'" || fail "options do not shift the folder"
WORK_DRY=1 bin/work projects/demo demo-code --effort low | grep -q -- "--effort low$" || fail "options after the repo"
WORK_DRY=1 bin/work projects/demo | grep -qE -- "--model|--effort" && fail "no options, no --model/--effort"
# negatives
WORK_DRY=1 bin/work --effort huge projects/demo >/dev/null 2>&1; assert_eq "$?" "2" "unknown effort level"
WORK_DRY=1 bin/work --model 'opus;rm' projects/demo >/dev/null 2>&1; assert_eq "$?" "2" "unsafe model name"
WORK_DRY=1 bin/work projects/demo --model >/dev/null 2>&1; assert_eq "$?" "2" "option without a value"
# which claude install: HUB_CLAUDE from hub.conf, else claude; AGENT_CLAUDE or --claude picks another
WORK_DRY=1 bin/work projects/demo | grep -q "' claude --settings" || fail "default is claude"
echo 'HUB_CLAUDE=claude-personal' > hub.conf
WORK_DRY=1 bin/work projects/demo | grep -q "' claude-personal --settings" || fail "hub.conf HUB_CLAUDE picks the install"
rm hub.conf
AGENT_CLAUDE=claude-other WORK_DRY=1 bin/work projects/demo | grep -q "' claude-other --settings" || fail "AGENT_CLAUDE picks the install"
WORK_DRY=1 bin/work --claude claude-koneksi projects/demo | grep -q "' claude-koneksi --settings" || fail "--claude picks the install"
WORK_DRY=1 bin/work --claude 'x;rm' projects/demo >/dev/null 2>&1; assert_eq "$?" "2" "unsafe claude command name"
echo ok
