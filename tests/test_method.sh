#!/bin/bash
# story C1: the hub takes the method (rules.md, bmad/custom/*.toml) from ade-method. Never the network: a local fixture
# repo stands in for ade-method through AGENT_METHOD_REPO.
. "$(dirname "$0")/helpers.sh"
PIN="$(bash -c ". '$REPO/bin/lib.sh' && method_pin")"
[ -n "$PIN" ] || fail "bin/lib.sh has no method_pin"
# a fixture ade-method with tags v1 and v2 (and the pin), each holding different rules and overrides
F="$(mktemp -d)/ade-method"; method_repo "$F" v1 v2 "$PIN"
fresh() { make_hub; cd "$HUB"; export AGENT_METHOD_REPO="$F"; }

sync_copies_method() {
  fresh; bin/method sync v1 >/dev/null || fail "sync v1 failed"
  assert_eq "$(cat .ade/rules.md)" "rules v1" "rules.md copied"
  assert_eq "$(cat _bmad/custom/bmad-build.toml)" "# build v1" "bmad-build.toml copied"
  assert_eq "$(cat _bmad/custom/bmad-code-review.toml)" "# review v1" "bmad-code-review.toml copied"
  [ -f _bmad/custom/.gitignore ] || fail "sync removed _bmad/custom/.gitignore"
}
version_recorded() {
  fresh; bin/method sync v2 >/dev/null || fail "sync v2 failed"
  assert_eq "$(awk '$1=="ref"{print $2}' .ade/method-version)" "v2" "ref recorded"
  assert_eq "$(awk '$1=="commit"{print $2}' .ade/method-version)" "$(git -C "$F" rev-parse 'v2^{commit}')" "commit recorded"
}
ref_from_conf_or_arg() {
  fresh; bin/method sync >/dev/null || fail "sync with no ref and no hub.conf failed"
  assert_eq "$(cat .ade/rules.md)" "rules $PIN" "no ref: the template's pin"
  echo "HUB_METHOD_REF=v1" > hub.conf; bin/method sync >/dev/null || fail "sync from hub.conf failed"
  assert_eq "$(cat .ade/rules.md)" "rules v1" "HUB_METHOD_REF picks the ref"
  bin/method sync v2 >/dev/null || fail "sync v2 failed"
  assert_eq "$(cat .ade/rules.md)" "rules v2" "an argument overrides HUB_METHOD_REF"
}
bad_ref_changes_nothing() {
  fresh; bin/method sync v1 >/dev/null || fail "sync v1 failed"
  before="$(cat .ade/rules.md _bmad/custom/*.toml .ade/method-version)"
  bin/method sync no-such-ref >/dev/null 2>&1; assert_eq "$?" "1" "unknown ref exits 1"
  assert_eq "$(cat .ade/rules.md _bmad/custom/*.toml .ade/method-version)" "$before" "unknown ref changed nothing"
  AGENT_METHOD_REPO=/nonexistent/ade-method bin/method sync v1 >/dev/null 2>&1; assert_eq "$?" "1" "unreachable repo exits 1"
  assert_eq "$(cat .ade/rules.md _bmad/custom/*.toml .ade/method-version)" "$before" "unreachable repo changed nothing"
}
check_finds_drift() {
  fresh; bin/method sync v1 >/dev/null || fail "sync v1 failed"
  bin/method check >/dev/null || fail "check after sync exits 0"
  echo "my own rule" >> .ade/rules.md; echo x > _bmad/custom/bmad-code-review.toml
  out=$(bin/method check 2>&1); assert_eq "$?" "1" "drift exits 1"
  echo "$out" | grep -q "\.ade/rules\.md" || fail "check names rules.md: $out"
  echo "$out" | grep -q "_bmad/custom/bmad-code-review\.toml" || fail "check names the review override: $out"
  echo "$out" | grep -q "bmad-build\.toml" && fail "check names a file that matches: $out"
  rm _bmad/custom/bmad-build.toml; bin/method check 2>&1 | grep -q "bmad-build\.toml" || fail "a missing file is drift"
}
doctor_reports_drift() {
  fresh; bin/method sync v1 >/dev/null || fail "sync v1 failed"
  out=$(PATH=/usr/bin:/bin DOCTOR_OFFLINE=1 bin/doctor); echo "$out" | grep -qE "^OK +method +.*v1" || fail "in step: OK row: $out"
  echo drift >> .ade/rules.md; echo drift >> _bmad/custom/bmad-build.toml
  out=$(PATH=/usr/bin:/bin DOCTOR_OFFLINE=1 bin/doctor)
  assert_eq "$(echo "$out" | grep -cE "^[A-Z]+ +method ")" "1" "one method row"
  echo "$out" | grep -E "^MISSING +method " | grep -q "\.ade/rules\.md" || fail "doctor names the drifted file: $out"
  echo "$out" | grep -q "drift$" && fail "doctor prints file contents, not just names: $out"
  return 0
}
init_syncs_method() {
  fresh; D="$(mktemp -d)/h"; bin/init --persona tech-lead --client A --owner B --dest "$D" >/dev/null || fail "init failed"
  assert_eq "$(cat "$D/.ade/rules.md")" "rules $PIN" "init syncs the pinned rules"
  assert_eq "$(awk '$1=="ref"{print $2}' "$D/.ade/method-version")" "$PIN" "init records the pin"
  assert_eq "$(. "$D/hub.conf"; echo "$HUB_METHOD_REF")" "$PIN" "init writes HUB_METHOD_REF"
  (HUB="$D" "$D/bin/method" check >/dev/null) || fail "a new hub starts in step"
}
template_matches_pin() {
  assert_eq "$(awk '$1=="ref"{print $2}' "$REPO/.ade/method-version")" "$PIN" "the template's method is the pinned ref"
  (unset HUB; cd "$REPO" && bin/method check) || fail "the template's .ade/rules.md or _bmad/custom/ differ from $PIN"
  grep -qi "lean mode" "$REPO/.ade/rules.md" && fail "the template's rules carry a lean-mode section of their own"
  return 0
}
for t in sync_copies_method version_recorded ref_from_conf_or_arg bad_ref_changes_nothing check_finds_drift \
         doctor_reports_drift init_syncs_method template_matches_pin; do (set -u; $t) || fail "$t"; done
echo ok
