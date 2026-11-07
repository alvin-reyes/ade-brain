#!/bin/bash
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"; export MONITOR_QUIET=1 AGENT_STATE="$(mktemp -d)"
# stub: never the real osascript (notifications)
STUB="$(mktemp -d)"; export PATH="$STUB:$PATH"
printf '#!/bin/bash\necho "$@" >> "%s/osa.log"\n' "$STUB" > "$STUB/osascript"; chmod +x "$STUB"/*
bin/monitor; assert_eq "$?" "0" "no monitors: exit 0"
mkdir -p ops/demo/monitors.d; printf '#!/bin/bash\necho "status 1"\n' > ops/demo/monitors.d/a.sh; chmod +x ops/demo/monitors.d/a.sh
bin/monitor; J="journal/$(date -u +%Y-%m-%d).md"
assert_contains "$J" "monitor a.sh: status 1" "first run is journaled"
grep -q "· ops/demo$" "$J" || fail "journaled under the monitor's folder"
[ -f "$AGENT_STATE/monitor-state/$(printf '%s' ops/demo/monitors.d/a.sh | sed 's/[^A-Za-z0-9]/-/g').status" ] || fail "state kept in the state dir"
n=$(grep -c "status 1" "$J"); bin/monitor; assert_eq "$(grep -c "status 1" "$J")" "$n" "unchanged output is not journaled again"
printf '#!/bin/bash\necho "status 2"\necho "ALERT disk 96%%"\n' > ops/demo/monitors.d/a.sh
bin/monitor; assert_contains "$J" "ALERT disk 96%" "an alert is journaled"
[ ! -e "$STUB/osa.log" ] || fail "MONITOR_QUIET=1 must not notify"
# the status line is compared without its leading timestamp: only a real change is journaled
printf '#!/bin/bash\necho "Fri $(date +%%H:%%M) UTC | code abc | db 5"\n' > ops/demo/monitors.d/a.sh
bin/monitor; n=$(grep -c "| code abc | db 5" "$J"); [ "$n" = 1 ] || fail "first run not journaled once ($n)"
printf '#!/bin/bash\necho "Sat 23:59 UTC | code abc | db 5"\n' > ops/demo/monitors.d/a.sh
bin/monitor; assert_eq "$(grep -c "| code abc | db 5" "$J")" "1" "same status, new timestamp: no new entry"
printf '#!/bin/bash\necho "2026-01-02 23:59Z | code abc | db 5"\n' > ops/demo/monitors.d/a.sh
bin/monitor; assert_eq "$(grep -c "| code abc | db 5" "$J")" "1" "same status, ISO timestamp: no new entry"
printf '#!/bin/bash\necho "Sat 23:59 UTC | code abc | db 6"\n' > ops/demo/monitors.d/a.sh
bin/monitor; assert_eq "$(grep -c "| code abc | db 6" "$J")" "1" "changed status is journaled"
# an ALERT is journaled once; again only after it clears and returns
printf '#!/bin/bash\necho "Sat 23:59 UTC | same"\necho "ALERT queue stuck"\n' > ops/demo/monitors.d/a.sh
bin/monitor; bin/monitor; bin/monitor; assert_eq "$(grep -c "ALERT queue stuck" "$J")" "1" "a repeated ALERT is journaled once"
printf '#!/bin/bash\necho "Sat 23:59 UTC | same"\n' > ops/demo/monitors.d/a.sh
bin/monitor; assert_eq "$(grep -c "ALERT queue stuck" "$J")" "1" "clearing is quiet"
# not quiet: a new ALERT notifies once, titled with the hub name and the folder
printf '#!/bin/bash\necho "Sat 23:59 UTC | same"\necho "ALERT queue stuck"\n' > ops/demo/monitors.d/a.sh
MONITOR_QUIET= bin/monitor; assert_eq "$(grep -c "ALERT queue stuck" "$J")" "2" "ALERT journaled again after it cleared and returned"
assert_contains "$STUB/osa.log" 'with title "hub: ops/demo"' "notification names the hub and folder"
assert_contains "$STUB/osa.log" "ALERT queue stuck" "notification carries the ALERT line"
MONITOR_QUIET= bin/monitor; assert_eq "$(wc -l < "$STUB/osa.log" | tr -d ' ')" "1" "a standing ALERT notifies once"
# a hanging monitor is killed by the timeout (the portable fallback too), child processes included
printf '#!/bin/bash\nsleep 30\necho late\n' > ops/demo/monitors.d/a.sh
s=$(date +%s); MONITOR_TIMEOUT=1 bin/monitor; [ $(( $(date +%s) - s )) -lt 15 ] || fail "hanging monitor was not killed"
. bin/lib.sh; s=$(date +%s); _timeout_fallback 1 sleep 30; rc=$?
[ $(( $(date +%s) - s )) -lt 15 ] && [ "$rc" != 0 ] || fail "fallback timeout did not kill (rc=$rc)"
_timeout_fallback 5 true || fail "fallback timeout failed a quick command"
# negative: a non-executable monitor is skipped; projects/ folders are monitored too
printf '#!/bin/bash\necho "should not run"\n' > ops/demo/monitors.d/b.sh; chmod -x ops/demo/monitors.d/b.sh
mkdir -p projects/app/monitors.d; printf '#!/bin/bash\necho "app up"\n' > projects/app/monitors.d/up.sh; chmod +x projects/app/monitors.d/up.sh
bin/monitor; grep -qF "should not run" "$J" && fail "non-executable monitor ran"
assert_contains "$J" "monitor up.sh: app up" "projects/ monitors run"
echo ok
