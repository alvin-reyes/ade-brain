#!/bin/bash
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"
out=$(PATH=/usr/bin:/bin AGENT_REMOTE_KEY=/nonexistent DOCTOR_OFFLINE=1 bin/doctor); rc=$?
assert_eq "$rc" "0" "doctor always exits 0"
echo "$out" | grep -qE "^MISSING +gitleaks" || fail "missing gitleaks reported"
echo "$out" | grep -qE "^MISSING +remote ssh key +/nonexistent" || fail "missing ssh key reported"
out=$(PATH=/usr/bin:/bin DOCTOR_OFFLINE=1 bin/doctor); echo "$out" | grep -q "remote ssh key" && fail "no key configured, nothing to report"
echo ok
