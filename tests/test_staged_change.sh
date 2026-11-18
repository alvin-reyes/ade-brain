#!/bin/bash
# templates/scripts/staged-change.sh: check changes nothing, go backs up and applies, a failed health check undoes itself,
# undo restores the backup, and the window / approval / version guards stop before any write.
. "$(dirname "$0")/helpers.sh"
S="$REPO/templates/scripts/staged-change.sh"
bash -n "$S" || fail "staged-change.sh syntax"
W="$(mktemp -d)"; cd "$W"
export TARGET="$W/app.conf" BACKUP_DIR="$W/backups" LOCK="$W/lock" MIN_FREE_KB=1 NAME=t WINDOW=0000-2359
echo old > "$TARGET"
cat > hooks.sh <<'H'
do_change() { echo new > "$TARGET"; }
health_check() { [ ! -f "$W/sick" ] || ! grep -q new "$TARGET"; }   # with $W/sick present, the new version is unhealthy
H
export HOOKS="$W/hooks.sh" W
# the clock for window tests: the now_hhmm hook reads $W/now (production reads the real clock; no env override)
printf '. "%s/hooks.sh"\nnow_hhmm() { cat "%s/now"; }\n' "$W" "$W" > hooks-clock.sh; echo 1200 > now
snap() { (cd "$W" && find . -path ./out -prune -o -type f -print | LC_ALL=C sort | xargs cat | cksum); }

# check: passes, changes nothing, takes no backup
before=$(snap); bash "$S" check > out 2>&1 || { cat out; fail "check on a healthy dummy"; }
assert_contains out "CHECK OK (nothing changed)" "check result line"
assert_eq "$(snap)" "$before" "check changed a file"; [ -e "$BACKUP_DIR/last" ] && fail "check took a backup"

# go, healthy: backup of the old content, then the change
bash "$S" go > out 2>&1 || { cat out; fail "go on a healthy dummy"; }
assert_contains out "== t OK ==" "go result line"; assert_eq "$(cat "$TARGET")" new "go applied the change"
assert_eq "$(cat "$(cat "$BACKUP_DIR/last")/target")" old "backup holds the old content"
[ -d "$LOCK" ] && fail "go left its lock behind"

# undo restores the backup
bash "$S" undo > out 2>&1 || { cat out; fail "undo"; }
assert_eq "$(cat "$TARGET")" old "undo restored the backup"

# go, unhealthy after the change: undone automatically, exit 1
touch "$W/sick"; bash "$S" go > out 2>&1 && fail "go with a failing health check exited 0"
assert_contains out "UNDONE AUTOMATICALLY" "auto-undo line"; assert_eq "$(cat "$TARGET")" old "auto-undo restored the backup"
rm -f "$W/sick"

# guards stop before any write: outside the window, override without approval, wrong version, lock held
echo old > "$TARGET"; before=$(snap)
HOOKS="$W/hooks-clock.sh" WINDOW=0030-0730 bash "$S" go > out 2>&1 && fail "go outside the window exited 0"
assert_contains out "outside the window" "window stop"
HOOKS="$W/hooks-clock.sh" WINDOW=0030-0730 DAYTIME_OK=1 bash "$S" go > out 2>&1 && fail "DAYTIME_OK without APPROVED_BY exited 0"
assert_contains out "needs APPROVED_BY" "override needs an approver"
EXPECTED=abc1234 bash "$S" go > out 2>&1 && fail "go on the wrong version exited 0"
assert_contains out "expected abc1234" "version stop"
mkdir "$LOCK"; bash "$S" go > out 2>&1 && fail "go with the lock held exited 0"; rmdir "$LOCK"
assert_eq "$(snap)" "$before" "a refused go changed a file"
HOOKS="$W/hooks-clock.sh" WINDOW=0030-0730 DAYTIME_OK=1 APPROVED_BY=owner bash "$S" go > out 2>&1 || { cat out; fail "approved override"; }
assert_contains out "approved by owner" "override names the approver"

# a restore that fails is never reported as restored or undone (exit 1, and it says so)
cat > hooks-lost.sh <<'H'
. "$W/hooks.sh"
do_change() { rm -f "$BACKUP_DIR/last"; echo broken > "$TARGET"; return 1; }   # the change fails and the backup pointer is gone
H
echo old > "$TARGET"; HOOKS="$W/hooks-lost.sh" bash "$S" go > out 2>&1 && fail "go with a lost backup exited 0"
grep -q "(restored)" out && fail "a failed restore was reported as restored: $(cat out)"
assert_contains out "NOT RESTORED" "a failed restore says so"
cat > hooks-lost2.sh <<'H'
. "$W/hooks.sh"
do_change() { rm -f "$BACKUP_DIR/last"; echo new > "$TARGET"; }   # applies, then the health check fails, and restore cannot run
H
echo old > "$TARGET"; touch "$W/sick"; HOOKS="$W/hooks-lost2.sh" bash "$S" go > out 2>&1 && fail "auto-undo with a lost backup exited 0"
rm -f "$W/sick"
grep -q "UNDONE AUTOMATICALLY" out && fail "a failed auto-undo was reported as undone: $(cat out)"
assert_contains out "NOT UNDONE" "a failed auto-undo says so"
# a restore whose copy fails leaves the live target in place
echo old > "$TARGET"; bash "$S" go > out 2>&1 || { cat out; fail "go before the copy-failure undo"; }
chmod 000 "$(cat "$BACKUP_DIR/last")/target"; bash "$S" undo > out 2>&1 && fail "undo with an unreadable backup exited 0"
chmod 644 "$(cat "$BACKUP_DIR/last")/target"
assert_eq "$(cat "$TARGET" 2>/dev/null)" new "a failed restore copy removed the live target"
ls "$W" | grep -q 'restore' && fail "a failed restore left a temporary copy: $(ls "$W")"

# a window that crosses midnight: open at 23:00 and 05:00, closed at 12:00 (the clock is the now_hhmm hook, not the env)
grep -q NOW_HHMM "$S" && fail "the window reads its clock from the environment (NOW_HHMM)"
for t in 2300 0500; do echo "$t" > now; HOOKS="$W/hooks-clock.sh" WINDOW=2200-0600 bash "$S" check > out 2>&1 || { cat out; fail "check at $t"; }
  assert_contains out "window 2200-0600" "window crossing midnight open at $t"; grep -q "outside the window" out && fail "$t is inside 2200-0600"; done
echo 1200 > now; HOOKS="$W/hooks-clock.sh" WINDOW=2200-0600 bash "$S" go > out 2>&1 && fail "go at 12:00 in 2200-0600 exited 0"
assert_contains out "outside the window" "12:00 is outside 2200-0600"
echo 1200 > now

# the skeleton itself: every rm goes through ${VAR:?}
grep -vE '^[[:space:]]*#' "$S" | grep -E '(^|[^a-z_])rm ' | grep -vE 'rm (-[a-z]+ )*-- "\$\{[A-Za-z_]+:\?' | grep -q . && fail "an rm without a \${VAR:?} guard"
bash "$S" bogus > /dev/null 2>&1; assert_eq "$?" 2 "unknown mode exits 2"
echo ok
