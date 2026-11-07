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
# every session has its own snapshot (hook stdin session_id): two sessions both hear the same change
bin/new ops/alert >/dev/null; A='{"session_id":"sess-a","hook_event_name":"UserPromptSubmit"}'; Bj='{"session_id":"sess-b"}'
assert_eq "$(echo "$A" | bin/changes projects/demo)" "" "session a: first prompt only records a baseline"
assert_eq "$(echo "$Bj" | bin/changes ops/box)" "" "session b: first prompt only records a baseline"
bin/journal ops/alert "db upstream down; ticket needed"
oa=$(echo "$A" | bin/changes projects/demo); ob=$(echo "$Bj" | bin/changes ops/box)
echo "$oa" | grep -q "^ops/alert: 1 journal line$" || fail "session a: [$oa]"
echo "$ob" | grep -q "^ops/alert: 1 journal line$" || fail "session b did not hear it too: [$ob]"
echo "$oa" | grep -qF "  - db upstream down; ticket needed" || fail "journal text shown: [$oa]"
assert_eq "$(echo "$A" | bin/changes projects/demo)" "" "session a: reported once"
# a folder session does not hear its own STATE and journal, but hears the hub root's notes
bin/journal projects/demo "my own note"; touch -t 209901020000 projects/demo/STATE.md; bin/journal . "main: sender paused"
oa=$(echo "$A" | bin/changes projects/demo)
echo "$oa" | grep -q "projects/demo" && fail "own folder echoed back: [$oa]"
echo "$oa" | grep -q "^hub: 1 journal line$" || fail "hub-root note not reported to a folder session: [$oa]"
echo "$oa" | grep -qF "  - main: sender paused" || fail "hub-root note text: [$oa]"
ob=$(echo "$Bj" | bin/changes ops/box); echo "$ob" | grep -q "^projects/demo: STATE.md updated .*1 journal line$" || fail "other folder's STATE + journal: [$ob]"
# long text trimmed to 200 characters; more than 3 new entries: the last 3 and a count
long=$(printf 'x%.0s' $(seq 1 300)); bin/journal ops/alert "$long"
for i in 1 2 3 4; do bin/journal ops/alert "entry $i"; done
oa=$(echo "$A" | bin/changes projects/demo)
echo "$oa" | grep -q "^ops/alert: 5 journal lines$" || fail "count: [$oa]"
echo "$oa" | grep -qF "  - (+2 more in journal/)" || fail "more count: [$oa]"
echo "$oa" | grep -qF "  - entry 4" || fail "newest entry shown"; echo "$oa" | grep -qF "entry 1" && fail "only the last 3 shown"
bin/journal ops/alert "$long"; oa=$(echo "$A" | bin/changes projects/demo); l=$(echo "$oa" | sed -n 2p)
[ ${#l} -le 206 ] || fail "journal text not trimmed (${#l})"; echo "$l" | grep -q "…$" || fail "trim mark"
# memory: new and updated files with their description; MEMORY.md itself is not reported
printf -- '---\nname: db-host\ndescription: "db host notes; SSH key in the secret store"\n---\nbody secret-ish text\n' > memory/db-host.md
echo "- x" >> memory/MEMORY.md; oa=$(echo "$A" | bin/changes projects/demo)
echo "$oa" | grep -qx "memory: new memory/db-host.md: db host notes; SSH key in the secret store" || fail "new memory: [$oa]"
echo "$oa" | grep -q "MEMORY.md" && fail "MEMORY.md reported"; echo "$oa" | grep -q "body secret-ish" && fail "memory body printed"
touch -t 209901030000 memory/db-host.md; mkdir -p projects/demo/memory; printf 'no front matter\n' > projects/demo/memory/n.md
oa=$(echo "$A" | bin/changes projects/demo)
echo "$oa" | grep -qx "memory: updated memory/db-host.md: db host notes; SSH key in the secret store" || fail "updated memory: [$oa]"
echo "$oa" | grep -qx "memory: new projects/demo/memory/n.md" || fail "memory without description: [$oa]"
# a description only from the front matter: a body line or a missing front matter prints none; block scalars are joined
printf 'no front matter\ndescription: TOKEN=abc123 body line\n' > memory/body.md
printf -- '---\nname: f\ndescription: >-\n  folded line one\n  and two\n---\ndescription: body copy\n' > memory/folded.md
oa=$(echo "$A" | bin/changes projects/demo)
echo "$oa" | grep -qx "memory: new memory/body.md" || fail "body description printed: [$oa]"; echo "$oa" | grep -q "TOKEN=" && fail "body line leaked"
echo "$oa" | grep -qx "memory: new memory/folded.md: folded line one and two" || fail "block description: [$oa]"
# short journal labels ("alert" for ops/alert) count for that folder
bin/journal alert "short label note"; oa=$(echo "$A" | bin/changes projects/demo)
echo "$oa" | grep -q "^ops/alert: 1 journal line$" || fail "short label not matched: [$oa]"
# hook JSON that arrives while stdin stays open is still read (bash 3.2 read -t would drop it)
bin/changes projects/demo < <(printf '{"session_id":"slow-1"}'; sleep 4) >/dev/null
[ -f "$AGENT_STATE/changes-seen.slow-1" ] || fail "slow stdin: session id lost (fell back to the shared snapshot)"
# old snapshots of ended sessions are removed, never the current session's own
touch "$AGENT_STATE/changes-seen.gone"; touch -t 202001010000 "$AGENT_STATE/changes-seen.gone" "$AGENT_STATE/changes-seen.sess-a"
bin/journal ops/alert "after idle"; oa=$(echo "$A" | bin/changes projects/demo)
[ -e "$AGENT_STATE/changes-seen.gone" ] && fail "old snapshot kept"
echo "$oa" | grep -q "^ops/alert: 1 journal line$" || fail "idle session lost its snapshot: [$oa]"
# output is capped
for i in $(seq 1 45); do printf -- '---\ndescription: m%s\n---\n' $i > memory/m$i.md; done
oa=$(echo "$A" | bin/changes projects/demo); assert_eq "$(echo "$oa" | wc -l | tr -d ' ')" "41" "capped at 40 lines + 1"
echo "$oa" | tail -1 | grep -q "^\.\.\. (5 more lines" || fail "cap note: [$(echo "$oa" | tail -1)]"
# never fails and never waits: a silent open stdin returns within the read timeout
t0=$(date +%s); bin/changes projects/demo < <(sleep 30) >/dev/null; assert_eq "$?" "0" "silent stdin exit 0"; [ $(( $(date +%s) - t0 )) -lt 6 ] || fail "waited on stdin"
echo ok
