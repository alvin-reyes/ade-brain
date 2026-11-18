#!/bin/bash
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"
bin/new projects/demo >/dev/null; bin/new ops/backups >/dev/null; rm ops/backups/STATE.md
out=$(bin/context); echo "$out" | grep -q "projects/demo" || fail "root lists folders"
echo "$out" | grep -q "(no STATE.md)" || fail "missing STATE.md tolerated"
bin/journal projects/demo "shipped #79" || fail "journal failed"
f="journal/$(date -u +%Y-%m-%d).md"; assert_contains "$f" "· projects/demo" "entry header"; assert_contains "$f" "shipped #79" "entry text"
bin/context projects/demo | grep -q "shipped #79" || fail "folder mode shows its journal"
bin/context projects/demo | grep -q "## Live" || fail "folder mode shows STATE"
# --rules: the shared rules, the Tools section and the hub memory index (a checkout session loads neither itself)
out=$(bin/context projects/demo --rules); echo "$out" | grep -q '^## Tools' || fail "--rules prints the Tools section"
echo "$out" | grep -q "^## Hub memory" && fail "an empty memory index prints a header"
echo '- [Deploy steps](deploy-steps.md) — staging first, then prod' >> memory/MEMORY.md
out=$(bin/context projects/demo --rules); echo "$out" | grep -q "^## Hub memory (read a file from $HUB/memory/" || fail "--rules names the hub memory dir: [$out]"
echo "$out" | grep -qxF -- '- [Deploy steps](deploy-steps.md) — staging first, then prod' || fail "--rules prints the memory index lines"
bin/context projects/demo | grep -q "Deploy steps" && fail "memory index printed without --rules"
# coordination: every focus session gets it (a checkout session does not load the hub CLAUDE.md); the main-agent section stays at the hub root
out=$(bin/context projects/demo --rules); echo "$out" | grep -q '^## Coordination' || fail "--rules prints the Coordination section"
echo "$out" | grep -q '^## The main agent' && fail "--rules leaves out the main-agent section"
bin/context projects/demo | grep -q '^## Coordination' && fail "Coordination printed without --rules"
# everything a focus session or its subagents produce reports to the main session
echo "$out" | grep -q "Report to the main session" || fail "--rules tells focus sessions to report to the main session"
echo "$out" | grep -q "subagents you start" || fail "--rules covers the subagents a focus session starts"
bin/journal >/dev/null 2>&1; assert_eq "$?" "2" "journal needs args"
touch -t 202001010000 projects/demo/STATE.md
bin/stop-check projects/demo | grep -q "STATE.md" || fail "stop-check reminds"
echo ok
