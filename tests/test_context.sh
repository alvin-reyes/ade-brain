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
bin/journal >/dev/null 2>&1; assert_eq "$?" "2" "journal needs args"
touch -t 202001010000 projects/demo/STATE.md
bin/stop-check projects/demo | grep -q "STATE.md" || fail "stop-check reminds"
echo ok
