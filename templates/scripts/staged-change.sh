#!/usr/bin/env bash
# Staged production change: one script per change, written and reviewed before the window, run on the machine.
#   bash staged-change.sh check   read-only: every precondition, prints what go would do, changes nothing
#   bash staged-change.sh go      preconditions again, backup, change, health check; a failed check undoes itself
#   bash staged-change.sh undo    restores the backup taken by the last go
#
# Copy it per change (e.g. change-<what>-<date>.sh), fill in the PLACEHOLDER parts, run `check` first, then `go` only
# on the owner's word for this change. See docs/shipping-changes-safely.md.
#
# Fill in the three functions below (current_version, do_change, health_check), or put them in a file and pass
# HOOKS=/path/to/hooks.sh, which this script sources after its defaults.
#
# Rules this skeleton keeps (keep them when you edit it):
#   - every precondition failure says "STOP ...: nothing changed" and exits 1 before anything is touched
#   - a backup is taken and verified before the first write
#   - every rm names its path through ${VAR:?}, so an empty variable can never become `rm -rf /`
#   - secrets are read at runtime into a variable (secret below), never echoed, logged or passed on a command line
#   - out of the change window only with DAYTIME_OK=1 and APPROVED_BY naming who approved it
set -u

# ---- PLACEHOLDER settings (env overrides keep the script testable) ------------------------------------------------
TARGET=${TARGET:-/srv/app/config.yml}          # the file or folder this change replaces
REPO=${REPO:-}                                 # optional: a git checkout that must have no local changes
EXPECTED=${EXPECTED:-}                         # optional: the version the machine must be on now (current_version)
BACKUP_DIR=${BACKUP_DIR:-/var/backups/staged-change}
LOCK=${LOCK:-/tmp/staged-change.lock}          # a mkdir lock (portable); use flock on Linux to also wait on cron's locks
WINDOW=${WINDOW:-0030-0730}                     # HHMM-HHMM local time (TZ_WINDOW) when go may run
TZ_WINDOW=${TZ_WINDOW:-UTC}
MIN_FREE_KB=${MIN_FREE_KB:-1048576}            # 1 GB free next to the backups
NAME=${NAME:-change}                           # a short label for the backup folder and the result line
MODE=${1:-check}

# ---- PLACEHOLDER hooks ---------------------------------------------------------------------------------------------
current_version() { [ -n "$REPO" ] && git -C "$REPO" rev-parse --short=7 HEAD || echo unknown; }
do_change() { echo "PLACEHOLDER: write the change to $TARGET here"; return 1; }   # return non-zero on any failure
health_check() { return 0; }   # PLACEHOLDER: e.g. curl -fsS --max-time 10 http://127.0.0.1:8080/health >/dev/null
[ -n "${HOOKS:-}" ] && { . "${HOOKS:?}" || { echo "STOP cannot read HOOKS=$HOOKS: nothing changed"; exit 1; }; }

# ---- helpers -------------------------------------------------------------------------------------------------------
ok() { echo "OK   $*"; }
stop() { echo "STOP $*: nothing changed"; exit 1; }
# secret NAME FILE: reads NAME=value from FILE at runtime into the variable NAME; never prints the value.
secret() { local v; v=$(grep -E "^$1=" "${2:?secret file}" 2>/dev/null | tail -1 | cut -d= -f2-) && [ -n "$v" ] || return 1
  printf -v "$1" '%s' "$v"; }
window_ok() {
  if [ "${DAYTIME_OK:-0}" = 1 ]; then
    [ -n "${APPROVED_BY:-}" ] || { echo "STOP DAYTIME_OK=1 needs APPROVED_BY=<who approved this run>: nothing changed"; exit 1; }
    return 0
  fi
  local now=$((10#${NOW_HHMM:-$(TZ=$TZ_WINDOW date +%H%M)})) a=$((10#${WINDOW%-*})) b=$((10#${WINDOW#*-}))
  [ "$now" -ge "$a" ] && [ "$now" -le "$b" ]
}
take_lock() { mkdir "$LOCK" 2>/dev/null || return 1; trap 'rmdir -- "${LOCK:?}" 2>/dev/null' EXIT; }
restore() {   # put the newest backup back; used by undo and by a failed health check
  local b; b=$(cat "$BACKUP_DIR/last" 2>/dev/null) && [ -n "$b" ] && [ -e "$b/target" ] || { echo "STOP no backup to restore"; return 1; }
  rm -rf -- "${TARGET:?}" && cp -Rp -- "${b:?}/target" "${TARGET:?}" && ok "restored $TARGET from $b"
}

case "$MODE" in
  undo)
    take_lock || { echo "STOP $LOCK is held (another run?): nothing changed"; exit 1; }
    restore || exit 1
    health_check && { ok "healthy after undo"; echo "== $NAME UNDONE =="; exit 0; }
    echo "== $NAME UNDONE, BUT NOT HEALTHY: look now =="; exit 1 ;;
  check|go) ;;
  *) echo "usage: $0 check|go|undo"; exit 2 ;;
esac

# ---- preconditions (check and go) ----------------------------------------------------------------------------------
[ -e "$TARGET" ] || stop "$TARGET does not exist"
ok "target $TARGET exists"
if [ -n "$EXPECTED" ]; then
  cur=$(current_version); [ "$cur" = "$EXPECTED" ] || stop "machine is on $cur, expected $EXPECTED"; ok "on $EXPECTED"
fi
if [ -n "$REPO" ]; then
  [ -z "$(git -C "$REPO" status --porcelain --untracked-files=no)" ] || stop "local changes in $REPO"; ok "no local changes in $REPO"
fi
mkdir -p "$BACKUP_DIR" 2>/dev/null && [ -w "$BACKUP_DIR" ] || stop "cannot write $BACKUP_DIR"
free=$(df -Pk "$BACKUP_DIR" | awk 'NR==2 {print $4}')
[ "${free:-0}" -ge "$MIN_FREE_KB" ] || stop "only ${free:-0} KB free next to $BACKUP_DIR (need $MIN_FREE_KB)"
ok "disk: $free KB free"
[ -d "$LOCK" ] && { [ "$MODE" = go ] && stop "$LOCK is held (another run?)"; echo "NOTE $LOCK is held now: go would refuse"; }
health_check && ok "healthy before the change" || stop "not healthy before the change (fix that first)"
if window_ok; then
  if [ "${DAYTIME_OK:-0}" = 1 ]; then ok "outside-window run approved by $APPROVED_BY"; else ok "window $WINDOW $TZ_WINDOW open"; fi
else [ "$MODE" = go ] && stop "outside the window $WINDOW $TZ_WINDOW"; echo "NOTE outside the window $WINDOW $TZ_WINDOW: go would refuse"; fi
[ "$MODE" = go ] || { echo "CHECK OK (nothing changed). Next: bash $0 go"; exit 0; }

# ---- go: lock, backup, change, health check, auto-undo -------------------------------------------------------------
take_lock || stop "$LOCK is held (another run?)"
B="$BACKUP_DIR/$NAME-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$B" && cp -Rp -- "$TARGET" "$B/target" || { rm -rf -- "${B:?}"; stop "backup failed"; }
diff -r -- "$TARGET" "$B/target" >/dev/null || { rm -rf -- "${B:?}"; stop "backup does not match $TARGET"; }
echo "$B" > "$BACKUP_DIR/last"; ok "backup at $B (undo: bash $0 undo)"

if ! do_change; then
  echo "FAIL the change did not apply: restoring"; restore; echo "== $NAME: STOP (restored) =="; exit 1
fi
ok "change applied"
if health_check; then
  ok "healthy after the change"; echo "== $NAME OK =="; exit 0
fi
echo "FAIL not healthy after the change: undoing automatically"
restore && health_check && ok "healthy again after the undo"
echo "== $NAME: UNDONE AUTOMATICALLY =="; exit 1
