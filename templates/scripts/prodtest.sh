#!/usr/bin/env bash
# Read-only production test: run it after a deploy, before a go, or any time someone asks "is it OK?".
#   bash prodtest.sh
# Prints one PASS / FAIL / WARN line per check and a summary line; exits 1 if any check FAILs.
#
# READ-ONLY by design: no file, switch, database or service write, no message sent. Database reads use a read-only
# session (e.g. psql -c "set default_transaction_read_only = on; select ..."); API calls are GETs only; secrets are
# read at runtime into a variable and never printed (print switch names and 0/1 only, mask other values).
#
# Copy it per system, fill in the PLACEHOLDER checks, and keep each one a single PASS/FAIL/WARN line.
#   FAIL = something is wrong now (wrong version, service down, a switch in the wrong state)
#   WARN = worth a look, not wrong by itself (a traceback in today's log, disk getting full, a stale log)
set -u

# ---- PLACEHOLDER settings (env overrides keep the script testable) ------------------------------------------------
REPO=${REPO:-}                       # the deployed checkout; empty skips the code checks
EXPECTED_FILE=${EXPECTED_FILE:-}     # a file holding the version the deploy script last wrote
URLS=${URLS:-}                       # space-separated health URLs, each must answer 2xx
LOGS=${LOGS:-}                       # space-separated log files scanned for tracebacks
MAX_LOG_AGE_MIN=${MAX_LOG_AGE_MIN:-60}
MIN_FREE_GB=${MIN_FREE_GB:-5}
DISK_PATH=${DISK_PATH:-/}

PASS=0; FAIL=0; WARN=0
ok() { echo "PASS $*"; PASS=$((PASS + 1)); }
bad() { echo "FAIL $*"; FAIL=$((FAIL + 1)); }
warn() { echo "WARN $*"; WARN=$((WARN + 1)); }
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }   # GNU, then BSD/macOS
echo "== production test, $(date -u '+%a %Y-%m-%d %H:%M') UTC"

# 1. Code: the deployed version is the one the last deploy recorded, with no local edits
if [ -n "$REPO" ]; then
  head=$(git -C "$REPO" rev-parse --short=7 HEAD 2>/dev/null); dirty=$(git -C "$REPO" status --porcelain --untracked-files=no 2>/dev/null | wc -l | tr -d ' ')
  want=$(cat "$EXPECTED_FILE" 2>/dev/null)
  [ -n "$head" ] && [ "$head" = "$want" ] && ok "code $head = expected" || bad "code ${head:-?}, expected ${want:-? (no $EXPECTED_FILE)}"
  [ "$dirty" = 0 ] && ok "no local changes in $REPO" || bad "$dirty local change(s) in $REPO"
fi

# 2. Services answer
for u in $URLS; do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$u" 2>/dev/null)
  case "$c" in 2??) ok "$u answers $c" ;; *) bad "$u answers ${c:-nothing}" ;; esac
done

# 3. Logs: tracebacks today, and the log is still being written
today=$(date -u +%Y-%m-%d)
for l in $LOGS; do
  [ -f "$l" ] || { warn "log $l missing"; continue; }
  tb=$(awk -v d="$today" 'index($0, d) {on = 1} on && /Traceback/ {n++} END {print n + 0}' "$l")
  [ "$tb" = 0 ] && ok "no traceback today in $l" || warn "$tb traceback(s) today in $l"
  age=$(( ($(date +%s) - $(mtime "$l")) / 60 ))
  [ "$age" -le "$MAX_LOG_AGE_MIN" ] && ok "$l written $age min ago" || warn "$l last written $age min ago"
done

# 4. PLACEHOLDER: switches, scheduled jobs, read-only data checks. Examples:
#   grep -q '^FEATURE_X=1' "$ENV_FILE" && ok "feature X on" || bad "feature X not on"
#   crontab -l | grep -q 'run_job.sh' && ok "job scheduled" || bad "job missing from cron"
#   n=$(psql "$DB" -XAtq -c "set default_transaction_read_only = on; select count(*) from t") ...

# 5. Disk
free=$(df -Pk "$DISK_PATH" | awk 'NR==2 {print int($4 / 1048576)}')
[ "${free:-0}" -ge "$MIN_FREE_GB" ] && ok "disk $DISK_PATH: $free GB free" || warn "disk $DISK_PATH: only ${free:-0} GB free"

echo "== RESULT: $PASS pass, $FAIL fail, $WARN warn"
[ "$FAIL" = 0 ]
