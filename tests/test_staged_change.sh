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
NOW_HHMM=1200 WINDOW=0030-0730 bash "$S" go > out 2>&1 && fail "go outside the window exited 0"
assert_contains out "outside the window" "window stop"
NOW_HHMM=1200 WINDOW=0030-0730 DAYTIME_OK=1 bash "$S" go > out 2>&1 && fail "DAYTIME_OK without APPROVED_BY exited 0"
assert_contains out "needs APPROVED_BY" "override needs an approver"
EXPECTED=abc1234 bash "$S" go > out 2>&1 && fail "go on the wrong version exited 0"
assert_contains out "expected abc1234" "version stop"
mkdir "$LOCK"; bash "$S" go > out 2>&1 && fail "go with the lock held exited 0"; rmdir "$LOCK"
assert_eq "$(snap)" "$before" "a refused go changed a file"
NOW_HHMM=1200 WINDOW=0030-0730 DAYTIME_OK=1 APPROVED_BY=owner bash "$S" go > out 2>&1 || { cat out; fail "approved override"; }
assert_contains out "approved by owner" "override names the approver"

# the skeleton itself: every rm goes through ${VAR:?}
grep -vE '^[[:space:]]*#' "$S" | grep -E '(^|[^a-z_])rm ' | grep -vE 'rm (-[a-z]+ )*-- "\$\{[A-Za-z_]+:\?' | grep -q . && fail "an rm without a \${VAR:?} guard"
bash "$S" bogus > /dev/null 2>&1; assert_eq "$?" 2 "unknown mode exits 2"
echo ok
