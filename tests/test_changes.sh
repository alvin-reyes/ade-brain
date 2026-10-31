#!/bin/bash
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"; export AGENT_STATE="$(mktemp -d)"
bin/new projects/demo >/dev/null; bin/new ops/box >/dev/null
assert_eq "$(bin/changes)" "" "first run only records a baseline"
assert_eq "$(bin/changes)" "" "nothing changed, nothing printed"
touch -t 209901010000 projects/demo/STATE.md
bin/journal projects/demo "did a thing"; bin/journal projects/demo "did another"
out=$(bin/changes)
echo "$out" | grep -q "^projects/demo: STATE.md updated .*2 journal lines" || fail "reports the folder's STATE and journal: [$out]"
echo "$out" | grep -q "ops/box" && fail "unchanged folder is reported"
assert_eq "$(bin/changes)" "" "reported once"
bin/journal ops/box "disk ok"
out=$(bin/changes); echo "$out" | grep -q "^ops/box: 1 journal line$" || fail "journal-only change: [$out]"
bin/journal hub "root note"; assert_eq "$(bin/changes)" "" "hub-root journal lines are not folder changes"
echo ok
