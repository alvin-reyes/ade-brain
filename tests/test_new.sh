#!/bin/bash
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"
bin/new projects/demo >/dev/null || fail "bin/new failed"
for f in projects/demo/CLAUDE.md projects/demo/ACCESS.md projects/demo/STATE.md projects/demo/memory/MEMORY.md \
         projects/demo/.claude/settings.json .claude/agents/demo.md; do [ -f "$f" ] || fail "missing $f"; done
assert_contains .claude/agents/demo.md "projects/demo/STATE.md" "the agent reads its STATE.md"
assert_contains projects/demo/STATE.md "## Live" "STATE sections"
echo "custom" > projects/demo/STATE.md
bin/new projects/demo | grep -q "kept projects/demo/STATE.md" || fail "did not report kept"
assert_eq "$(cat projects/demo/STATE.md)" "custom" "never overwrites"
bin/new ops/backups >/dev/null && [ -f .claude/agents/ops-backups.md ] || fail "ops agent name"
bin/new projects/Bad_Name >/dev/null 2>&1; assert_eq "$?" "2" "bad name exits 2"
assert_contains projects/demo/CLAUDE.md "@memory/MEMORY.md" "new folder CLAUDE.md imports its memory"
echo ok
