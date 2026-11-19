#!/bin/bash
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"
stub_security
printf 'pat-123\n' | bin/secret --set api-token 2>err || fail "set failed"
grep -q "pat-123" err && fail "set echoed the value"
assert_eq "$(bin/secret api-token)" "pat-123" "get returns the value"
bin/secret --has api-token || fail "--has after set"
# the value goes to security on stdin, so no logged argv holds it
grep -q "pat-123" "$STORE.argv" && fail "the value reached a security argument"
V='sk "quoted" back\\slash $HOME `x`'; printf '%s\n' "$V" | bin/secret --set odd 2>/dev/null || fail "set with shell characters"
assert_eq "$(bin/secret odd)" "$V" "a value with quotes, backslashes and dollars survives"
SECURITY_FAIL=1 bash -c "printf 'nope\n' | bin/secret --set failed" 2>err; assert_eq "$?" "1" "a failed store exits 1"; assert_contains err "could not store" "a failed store says so"
bin/secret --forget api-token 2>/dev/null; bin/secret --has api-token && fail "--has after forget"
bin/secret nope 2>err; assert_eq "$?" "1" "missing secret exits 1"; assert_contains err "not stored" "says how to store it"
printf '\n' | bin/secret --set empty 2>/dev/null; assert_eq "$?" "1" "empty value refused"
bin/secret >/dev/null 2>&1; assert_eq "$?" "2" "no args exits 2"
echo ok
