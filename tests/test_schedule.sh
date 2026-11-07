#!/bin/bash
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"; export AGENT_STATE="$(mktemp -d)"
# dry install: one plist per job, labelled per hub, logs under the state dir; nothing is loaded
L="$(mktemp -d)"; out=$(AGENT_LAUNCHAGENTS="$L" SCHEDULE_DRY=1 bin/schedule install) || fail "schedule install"
P="$L/ai.agent-hub.hub.sync.plist"; [ -f "$P" ] || fail "sync plist written"
echo "$out" | grep -q "wrote $P" || fail "dry install names the sync plist"
plutil -lint "$P" >/dev/null || fail "sync plist is not valid"
assert_contains "$P" "<string>ai.agent-hub.hub.sync</string>" "sync label"
assert_contains "$P" "<string>$HUB/bin/sync</string><string>--auto</string>" "sync job runs bin/sync --auto"
grep -q -- "--yes" "$P" && fail "sync job must never run --yes"
assert_contains "$P" "<integer>1800</integer>" "every 30 minutes"
assert_contains "$P" "$AGENT_STATE/logs/sync.log" "sync log in the state dir"
grep -q "{{" "$P" && fail "unfilled placeholder in the sync plist"
[ -d "$AGENT_STATE/logs" ] || fail "logs dir made"
# HUB_AUTO_SYNC=0 in hub.conf: no sync job (and an earlier one is removed); the other jobs stay
echo HUB_AUTO_SYNC=0 > hub.conf
out=$(AGENT_LAUNCHAGENTS="$L" SCHEDULE_DRY=1 bin/schedule install) || fail "schedule install, auto sync off"
[ -f "$P" ] && fail "auto sync off: sync plist kept"
echo "$out" | grep -q "removed ai.agent-hub.hub.sync" || fail "auto sync off: removal reported"
[ -f "$L/ai.agent-hub.hub.briefing.plist" ] || fail "auto sync off: briefing plist missing"
rm -f hub.conf
echo ok
