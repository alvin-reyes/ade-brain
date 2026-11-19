#!/bin/bash
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"; . bin/lib.sh
bin/new projects/demo >/dev/null
old="$CLAUDE_HOME/projects/$(encode_path "$HUB/projects/demo")/memory"
rm -f "$old"; mkdir -p "$old" && echo "remember" > "$old/fact.md"     # a pre-existing real memory dir
bin/setup >/dev/null || fail "setup failed"
[ -L "$old" ] || fail "memory dir is not a link"
assert_eq "$(readlink "$old")" "$HUB/projects/demo/memory" "link target"
assert_eq "$(cat "$HUB/projects/demo/memory/fact.md")" "remember" "existing memory kept"
ls -d "$old".bak-* >/dev/null 2>&1 || fail "no backup of the old dir"
bin/setup | grep -q "ok projects/demo" || fail "not idempotent"
assert_eq "$(git config core.hooksPath)" ".githooks" "hooks path"
# BMAD skills: linked into the Claude home; a pre-existing real one is left alone; idempotent
mkdir -p .claude/skills/bmad-x .claude/skills/bmad-y .claude/skills/other
echo x > .claude/skills/bmad-x/SKILL.md; echo y > .claude/skills/bmad-y/SKILL.md; echo o > .claude/skills/other/SKILL.md
mkdir -p "$CLAUDE_HOME/skills/bmad-y"; echo mine > "$CLAUDE_HOME/skills/bmad-y/SKILL.md"
bin/setup >/dev/null || fail "setup failed with skills"
[ -L "$CLAUDE_HOME/skills/bmad-x" ] || fail "bmad-x not linked"
assert_eq "$(readlink "$CLAUDE_HOME/skills/bmad-x")" "$HUB/.claude/skills/bmad-x" "skill link target"
[ ! -L "$CLAUDE_HOME/skills/bmad-y" ] && [ "$(cat "$CLAUDE_HOME/skills/bmad-y/SKILL.md")" = mine ] || fail "pre-existing skill overwritten"
[ ! -e "$CLAUDE_HOME/skills/other" ] || fail "non-bmad skill linked"
bin/setup >/dev/null || fail "second setup failed"
assert_eq "$(readlink "$CLAUDE_HOME/skills/bmad-x")" "$HUB/.claude/skills/bmad-x" "skill link idempotent"
# one checkout claimed by two folders: only the first (owner) is linked, the second gets a warning
bin/new projects/dup >/dev/null; SH="$(mktemp -d)/shared"; mkdir -p "$SH"
printf '| shared | %s | main | Owner | none |\n' "$SH" >> projects/demo/ACCESS.md
printf '| shared | %s | main | Owner | none |\n' "$SH" >> projects/dup/ACCESS.md
out=$(bin/setup 2>&1) || fail "setup failed with a doubly claimed checkout"
smem="$CLAUDE_HOME/projects/$(encode_path "$SH")/memory"
assert_eq "$(readlink "$smem")" "$HUB/projects/demo/memory" "the first claimant owns the checkout memory"
assert_eq "$(echo "$out" | grep -c 'linked projects/demo repo shared')" "1" "one link for the shared checkout"
echo "$out" | grep -q "warning: $SH is claimed by projects/dup, owned by projects/demo" || fail "no warning for the second claimant"
echo "$out" | grep -q "projects/dup repo shared" && fail "second claimant linked the checkout"
# the owner's own bin/work still resolves it; a folder with an empty Checkout is not an owner
assert_eq "$(. bin/lib.sh; repos_of projects/demo | grep -c "$SH")" "1" "repos_of returns the owned path"
# a folder that says "memory owned by <folder>" never takes the checkout, even when it sorts first
bin/new projects/aaa >/dev/null; SH2="$(mktemp -d)/shared2"; mkdir -p "$SH2"
printf '| s2 | %s | main | Owner | memory owned by projects/zzz |\n' "$SH2" >> projects/aaa/ACCESS.md
bin/new projects/zzz >/dev/null; printf '| s2 | %s | main | Owner | none |\n' "$SH2" >> projects/zzz/ACCESS.md
bin/setup >/dev/null 2>&1 || fail "setup failed with a marked shared checkout"
assert_eq "$(readlink "$CLAUDE_HOME/projects/$(encode_path "$SH2")/memory")" "$HUB/projects/zzz/memory" "the named owner keeps the checkout memory"
echo ok
