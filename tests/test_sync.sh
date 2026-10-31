#!/bin/bash
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"; git config core.hooksPath .githooks; git add -A >/dev/null 2>&1; git commit -q --no-verify -m base >/dev/null 2>&1
echo "x" >> memory/MEMORY.md; mkdir -p repos/y && echo c > repos/y/z.py
bin/sync | grep -q "memory/MEMORY.md" || fail "review lists the change"
[ -z "$(git diff --cached --name-only)" ] || fail "review mode left things staged"
bin/sync --yes >/dev/null || fail "sync --yes failed"
git log -1 --name-only --pretty=format: | grep -q "^repos/" && fail "repos/ committed"
git log -1 --pretty=%s | grep -q "^sync " || fail "commit message"
# review mode lists untracked paths under .claude/ so they are not swept in unseen
mkdir -p .claude/skills/zz && echo s > .claude/skills/zz/SKILL.md; echo q >> memory/MEMORY.md
out=$(bin/sync); echo "$out" | tail -1 | grep -q "untracked under .claude/.*skills/zz" || fail "review does not note untracked .claude paths"
bin/sync --yes >/dev/null || fail "sync --yes failed"
# files staged by someone else outside the hub paths: never committed, never unstaged
echo "y" >> memory/MEMORY.md; echo s > scratch.txt; echo more >> other.txt; git add scratch.txt other.txt
bin/sync | grep -q "memory/MEMORY.md" || fail "review lists the pending hub change while others are staged"
git diff --cached --name-only | grep -qx scratch.txt || fail "review altered the index"
bin/sync --yes >/dev/null || fail "sync --yes with other staged files failed"
git show --name-only --pretty=format: HEAD | grep -qx memory/MEMORY.md || fail "hub change not committed"
git show --name-only --pretty=format: HEAD | grep -qE "^(scratch|other)\.txt$" && fail "non-hub staged file committed"
git diff --cached --name-only | grep -qx scratch.txt || fail "scratch.txt lost its staging"
git diff --cached --name-only | grep -qx other.txt || fail "other.txt lost its staging"
# unreachable remote: the commit stays, the failure is reported with exit 1
echo "z" >> memory/MEMORY.md; git remote add origin /nonexistent; git config push.default current
out=$(bin/sync --yes 2>&1); rc=$?
[ "$rc" = 1 ] || fail "unreachable remote: want exit 1, got $rc"
echo "$out" | grep -q "push failed" || fail "push failure not reported"
echo "$out" | grep -q "does not appear to be a git repository" || fail "push did not fail on the unreachable remote"
echo "$out" | grep -q "synced:" && fail "reported synced after a failed push"
git log -1 --pretty=%s | grep -q "^sync " || fail "commit missing after push failure"
echo ok
