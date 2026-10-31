#!/bin/bash
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"; export AGENT_STATE="$(mktemp -d)"
bin/new projects/demo >/dev/null
R="$(mktemp -d)/demo-code"   # checkouts live outside the hub, absolute path in ACCESS.md
mkdir -p "$R" && git -C "$R" init -q && git -C "$R" config user.email t@t && git -C "$R" config user.name t
printf '| demo-code | %s | main | Alvin | none |\n' "$R" >> projects/demo/ACCESS.md
touch -t 202001010000 projects/demo/STATE.md
# negative: no commits yet, nothing blocks and session-end writes nothing
assert_eq "$(bin/stop-check projects/demo)" "" "no commits, no block"
echo '{"transcript_path":""}' | bin/session-end projects/demo; assert_eq "$?" "0" "session-end exits 0"
[ ! -e "journal/$(date -u +%Y-%m-%d).md" ] || fail "session-end with no commits wrote a journal entry"
echo x > "$R/a" && git -C "$R" add a && git -C "$R" commit -qm "fix pings"
out=$(bin/stop-check projects/demo); echo "$out" | grep -q '"decision":"block"' || fail "stop-check blocks after new commits"
assert_eq "$(bin/stop-check projects/demo)" "" "blocks only once per commit"
bin/context | grep -q "projects/demo (state may be stale" || fail "root flags stale state"
echo '{"transcript_path":""}' | bin/session-end projects/demo
assert_contains "journal/$(date -u +%Y-%m-%d).md" "fix pings" "session-end journals the commits"
# transcript start time: a session that started after the commit sees nothing new
printf '{"timestamp":"2099-01-01T00:00:00.000Z"}\n' > "$AGENT_STATE/t.jsonl"
n=$(grep -c "auto: session ended" "journal/$(date -u +%Y-%m-%d).md")
echo "{\"transcript_path\":\"$AGENT_STATE/t.jsonl\"}" | bin/session-end projects/demo
assert_eq "$(grep -c "auto: session ended" "journal/$(date -u +%Y-%m-%d).md")" "$n" "future start writes nothing"
touch projects/demo/STATE.md
bin/context | grep -q "state may be stale" && fail "fresh STATE.md still flagged"
# session end commits the folder's hub files and the journal (never pushes, never other paths)
git add bin/journal && git commit -qm base -- bin/journal
echo "scratch" > other.txt; git add other.txt
echo "more" >> projects/demo/STATE.md; git remote add origin /nonexistent
echo '{"transcript_path":""}' | bin/session-end projects/demo; assert_eq "$?" "0" "session-end with hub changes exits 0"
git log -1 --pretty=%s | grep -q "^session projects/demo " || fail "session commit made"
git show --name-only --pretty=format: HEAD | grep -qx projects/demo/STATE.md || fail "folder STATE committed"
git show --name-only --pretty=format: HEAD | grep -q "^journal/" || fail "journal committed"
git show --name-only --pretty=format: HEAD | grep -qvE "^(projects/demo/|journal/|$)" && fail "commit holds other paths"
git diff --cached --name-only | grep -qx other.txt || fail "someone else's staged file lost its staging"
git rev-parse -q --verify refs/remotes/origin/HEAD >/dev/null && fail "pushed"
h=$(git rev-parse HEAD); T="{\"transcript_path\":\"$AGENT_STATE/t.jsonl\"}"   # starts in 2099: no code commits to journal
echo "$T" | bin/session-end projects/demo
assert_eq "$(git rev-parse HEAD)" "$h" "no hub changes, no commit"
echo x >> projects/demo/STATE.md; echo "$T" | bin/session-end .
assert_eq "$(git rev-parse HEAD)" "$h" "hub root session never commits"
echo ok
