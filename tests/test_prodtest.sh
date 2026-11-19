#!/bin/bash
# templates/scripts/prodtest.sh: one PASS/FAIL/WARN line per check, a summary line, exit 1 on any FAIL, writes nothing.
. "$(dirname "$0")/helpers.sh"
S="$REPO/templates/scripts/prodtest.sh"
bash -n "$S" || fail "prodtest.sh syntax"
W="$(mktemp -d)"; G="$W/app"; mkdir "$G"
git -C "$G" init -q && git -C "$G" config user.name t && git -C "$G" config user.email t@t
echo a > "$G/f"; git -C "$G" add f && git -C "$G" commit -qm a
git -C "$G" rev-parse --short=7 HEAD > "$W/expected"
printf '%s ok\n' "$(date -u +%Y-%m-%d)" > "$W/app.log"
export REPO="$G" EXPECTED_FILE="$W/expected" LOGS="$W/app.log" URLS="" MIN_FREE_GB=0
snap() { (cd "$W" && find . -type f -not -path '*/.git/*' | LC_ALL=C sort | xargs cat | cksum); }

before=$(snap); out=$(bash "$S") || fail "a healthy dummy fails: $out"
echo "$out" | grep -q "^== RESULT: [0-9]* pass, 0 fail, 0 warn$" || fail "summary line: $out"
echo "$out" | grep -qv -E '^(PASS|FAIL|WARN|==) ' && fail "a line that is not PASS/FAIL/WARN: $out"

# a traceback today is a WARN, not a FAIL
printf '%s Traceback (most recent call last):\n' "$(date -u +%Y-%m-%d)" >> "$W/app.log"
out=$(bash "$S") || fail "a traceback alone failed the run"
echo "$out" | grep -q "^WARN 1 traceback" || fail "traceback not warned: $out"

# a local edit and a wrong version are FAILs, exit 1
echo b > "$G/f"; echo 0000000 > "$W/expected"; before=$(snap)
out=$(bash "$S") && fail "a dirty, wrong-version tree passed"
echo "$out" | grep -q "^FAIL code" || fail "version FAIL missing: $out"
echo "$out" | grep -q "^FAIL 1 local change" || fail "local change FAIL missing: $out"
echo "$out" | grep -q "^== RESULT: .* 2 fail" || fail "summary counts: $out"

# read-only: the run wrote nothing
assert_eq "$(snap)" "$before" "prodtest changed a file"
echo ok
