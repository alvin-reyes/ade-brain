#!/bin/bash
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"
for s in "## Shared rules" "## The main agent" "## Git boundaries" "## Token budget" "@memory/MEMORY.md" "{{PERSONA}}" "{{OWNER}}"; do assert_contains templates/hub/CLAUDE.md "$s" "hub CLAUDE.md template"; done
python3 -c "import json; d=json.load(open('.claude/settings.json')); assert 'bin/context' in d['hooks']['SessionStart'][0]['hooks'][0]['command']" || fail "root SessionStart hook"
grep -rqiE "(api[_-]?key|token|password)\s*[:=]\s*[A-Za-z0-9_-]{16,}" templates personas CLAUDE.md README.md && fail "something secret-looking in the template"
grep -rqi "orillia\|arjuns57\|jared" bin templates personas docs README.md CLAUDE.md && fail "a client-specific name is left in the template"
n=$(ls personas/*.md | wc -l | tr -d ' '); [ "$n" -ge 10 ] || fail "persona library has $n personas"
for p in personas/*.md; do for k in title folders briefing_focus; do grep -q "^$k: ." "$p" || fail "$p has no $k"; done
  grep -q "{{CLIENT}}" "$p" && grep -q "{{OWNER}}" "$p" || fail "$p does not name the client and owner"; done
echo ok
