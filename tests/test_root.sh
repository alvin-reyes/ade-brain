#!/bin/bash
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"
for s in "## Shared rules" "## The main agent" "## Git boundaries" "## Token budget" "@memory/MEMORY.md" "{{PERSONA}}" "{{OWNER}}"; do assert_contains templates/hub/CLAUDE.md "$s" "hub CLAUDE.md template"; done
python3 -c "import json; d=json.load(open('.claude/settings.json')); assert 'bin/context' in d['hooks']['SessionStart'][0]['hooks'][0]['command']" || fail "root SessionStart hook"
grep -rqiE "(api[_-]?key|token|password)\s*[:=]\s*[A-Za-z0-9_-]{16,}" templates personas CLAUDE.md README.md && fail "something secret-looking in the template"
grep -rqi "orillia\|arjuns57\|jared" bin templates personas docs README.md CLAUDE.md && fail "a client-specific name is left in the template"
# bin/init copies the whole template into each hub: hub agents are rendered by bin/init, never shipped pre-made
[ -z "$(ls -A .claude/agents 2>/dev/null)" ] || fail "the template ships agents in .claude/agents (bin/init renders a hub's agents)"
# every relative link in an llms.txt index points at a file the hub actually has
[ ! -f llms.txt ] || for l in $(grep -oE '\]\([^)]+\)' llms.txt | sed -E 's/^\]\(//; s/\)$//' | grep -v '://'); do [ -e "$l" ] || fail "llms.txt links to missing $l"; done
python3 -c "import json; d=json.load(open('.claude/settings.json')); assert 'attribution' not in d and 'includeCoAuthoredBy' not in d" || fail "the template overrides commit attribution for every hub"
n=$(ls personas/*.md | wc -l | tr -d ' '); [ "$n" -ge 10 ] || fail "persona library has $n personas"
for p in personas/*.md; do for k in title folders briefing_focus; do grep -q "^$k: ." "$p" || fail "$p has no $k"; done
  grep -q "{{CLIENT}}" "$p" && grep -q "{{OWNER}}" "$p" || fail "$p does not name the client and owner"; done
echo ok
