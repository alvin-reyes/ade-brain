#!/bin/bash
# bin/dispatch (story C3): starts focus builders for ready BMAD tickets; fake `tickets next` (node), fake bin/work and bin/sessions
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"
bin/new projects/demo >/dev/null
CK="$(mktemp -d)/demo-code"; mkdir -p "$CK/_bmad" && : > "$CK/_bmad/ade-runtime.mjs"   # the folder's checkout, with BMAD
printf '| demo-code | %s | main | Owner | none |\n' "$CK" >> projects/demo/ACCESS.md
S="$(mktemp -d)"; export S
# fake node: logs its argv, prints $S/tickets.json, or fails like the real tool when $S/fail exists
cat > "$S/node" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$S/node.argv"
[ -e "$S/fail" ] && { echo "tickets: error: no ticket store here"; exit 2; }
cat "$S/tickets.json"
SH
# fake bin/work: one line per call, each argument in brackets; fake bin/sessions prints $S/sessions
printf '#!/bin/bash\nfor a in "$@"; do printf "[%%s]" "$a"; done >> "$S/work.log"; echo >> "$S/work.log"\n' > bin/work
printf '#!/bin/bash\necho "NAME FOLDER PID PARENT STARTED ROLE STATUS LAST"\ncat "$S/sessions" 2>/dev/null; exit 0\n' > bin/sessions
chmod +x "$S/node" bin/work bin/sessions
export PATH="$S:$PATH"
J="journal/$(date -u +%Y-%m-%d).md"
reset() { rm -f "$S/work.log" "$S/node.argv" "$S/sessions" "$S/fail" "$J"; : > "$S/work.log"; unset HUB_DISPATCH_MAX; }
row() { printf '{"ref":"%s","state":"todo","risk":"%s"%s}' "$1" "$2" "${3:-}"; }
tickets() {  # tickets <ready rows> [refine rows] [in-progress rows] [blocked rows]
  printf '{"store":"repo","folder":"demo","ready_to_refine":[%s],"ready_to_start":[%s],"in_progress":[%s],"blocked":[%s]}\n' \
    "${2:-}" "$1" "${3:-}" "${4:-}" > "$S/tickets.json"
}
calls() { grep -c . "$S/work.log"; }
journal_lines() { cat "$J" 2>/dev/null | grep -c '^dispatch'; }

starts_one_by_default() {
  reset; tickets "$(row 1.1 medium),$(row 1.2 low)"
  out=$(bin/dispatch projects/demo) || fail "dispatch exits 0: $out"
  assert_eq "$(calls)" 1 "one start by default"
  assert_eq "$(cat "$S/work.log")" "[--role][builder][--name][1.1][--prompt][bmad-build 1.1][projects/demo]" "bin/work call"
  assert_eq "$(cat "$S/node.argv")" "$CK/_bmad/ade-runtime.mjs tickets --project-root $CK next" "the checkout's tickets next"
  # a ref with characters bin/work does not take in a name is sanitised for --name, kept in the prompt
  reset; tickets "$(row 'demo/01-a b.md' low)"
  bin/dispatch projects/demo >/dev/null 2>&1
  assert_eq "$(calls)" 0 "a ref with a space is refused, never started"
  reset; tickets "$(row 'demo/01-a.md' low)"
  bin/dispatch projects/demo >/dev/null || fail "dispatch a file ref"
  assert_eq "$(cat "$S/work.log")" "[--role][builder][--name][demo-01-a.md][--prompt][bmad-build demo/01-a.md][projects/demo]" "sanitised name"
}

max_capped_at_two() {
  reset; tickets "$(row 1.1 low),$(row 1.2 low),$(row 1.3 low)"
  HUB_DISPATCH_MAX=2 bin/dispatch projects/demo >/dev/null || fail "dispatch max 2"
  assert_eq "$(calls)" 2 "HUB_DISPATCH_MAX=2 starts two"
  reset; tickets "$(row 1.1 low),$(row 1.2 low),$(row 1.3 low)"
  HUB_DISPATCH_MAX=9 bin/dispatch projects/demo >/dev/null || fail "dispatch max 9"
  assert_eq "$(calls)" 2 "HUB_DISPATCH_MAX above 2 is capped at 2"
  reset; tickets "$(row 1.1 low)"
  HUB_DISPATCH_MAX=two bin/dispatch projects/demo >/dev/null 2>&1; assert_eq "$?" 2 "a bad HUB_DISPATCH_MAX is refused"
  assert_eq "$(calls)" 0 "nothing started on a bad HUB_DISPATCH_MAX"
}

running_ticket_not_restarted() {
  reset; tickets "$(row 1.1 low),$(row 1.2 low)"
  echo "1.1 projects/demo 123 - 2026-11-21T00:00:00Z builder busy -" > "$S/sessions"
  HUB_DISPATCH_MAX=2 bin/dispatch projects/demo >/dev/null || fail "dispatch with one running"
  assert_eq "$(cat "$S/work.log")" "[--role][builder][--name][1.2][--prompt][bmad-build 1.2][projects/demo]" "running 1.1 not restarted, 1.2 started"
  reset; tickets "$(row 1.1 low),$(row 1.2 low)"
  echo "1.1 projects/demo 123 - 2026-11-21T00:00:00Z builder busy -" > "$S/sessions"
  bin/dispatch projects/demo >/dev/null || fail "dispatch with the one slot taken"
  assert_eq "$(calls)" 0 "the running ticket takes the only slot"
  # a broken session list starts nothing
  reset; tickets "$(row 1.1 low)"; printf '#!/bin/bash\nexit 1\n' > "$S/sessions-bad"; cp bin/sessions "$S/sessions-ok"
  cp "$S/sessions-bad" bin/sessions; bin/dispatch projects/demo >/dev/null 2>&1; rc=$?; cp "$S/sessions-ok" bin/sessions
  assert_eq "$rc" 1 "bin/sessions failing exits 1"; assert_eq "$(calls)" 0 "nothing started without a session list"
}

high_risk_waits() {
  reset; tickets "$(row 2.1 high),$(row 2.2 low ',"hitl":true'),$(row 2.3 '')"
  out=$(HUB_DISPATCH_MAX=2 bin/dispatch projects/demo) || fail "dispatch with waiting tickets: $out"
  assert_eq "$(calls)" 0 "high-risk, hitl and unknown-risk tickets are not started"
  for r in 2.1 2.2 2.3; do echo "$out" | grep -q "^waiting for the owner: $r " || fail "$r printed as waiting: $out"; done
  assert_eq "$(journal_lines)" 1 "one journal line"
  for r in 2.1 2.2 2.3; do assert_eq "$(grep -o "waiting for the owner:[^;]*" "$J" | tr ' ,' '\n\n' | grep -cx "$r")" 1 "$r journaled once"; done
}

approve_starts_one() {
  reset; tickets "$(row 2.1 high),$(row 2.2 low)"
  out=$(bin/dispatch --approve 2.1 projects/demo) || fail "approve a ready high-risk ticket: $out"
  assert_eq "$(cat "$S/work.log")" "[--role][builder][--name][2.1][--prompt][bmad-build 2.1][projects/demo]" "approve starts only 2.1"
  reset; tickets "$(row 2.1 high)" "" "" "$(row 2.9 high)"
  bin/dispatch --approve 2.9 projects/demo >/dev/null 2>&1; assert_eq "$?" 1 "approving a ticket that is not ready exits 1"
  assert_eq "$(calls)" 0 "a blocked ticket is never started by --approve"
  bin/dispatch --approve 2.7 projects/demo >/dev/null 2>&1; assert_eq "$?" 1 "approving an unknown ticket exits 1"
  echo "2.1 projects/demo 123 - 2026-11-21T00:00:00Z builder busy -" > "$S/sessions"
  bin/dispatch --approve 2.1 projects/demo >/dev/null 2>&1; assert_eq "$?" 1 "approving a running ticket exits 1"
  assert_eq "$(calls)" 0 "a running ticket is not started again by --approve"
}

only_ready_started() {
  reset; tickets "" "$(row 3.1 low)" "$(row 3.2 low)" "$(row 3.3 low)"
  HUB_DISPATCH_MAX=2 bin/dispatch projects/demo >/dev/null || fail "dispatch with nothing ready"
  assert_eq "$(calls)" 0 "to-refine, in-progress and blocked tickets are never started"
}

bad_tree_starts_nothing() {
  reset; tickets "$(row 1.1 low)"; touch "$S/fail"
  out=$(bin/dispatch projects/demo 2>&1); assert_eq "$?" 1 "tickets next failing exits 1"
  echo "$out" | grep -q "no ticket store here" || fail "its message is shown: $out"
  assert_eq "$(calls)" 0 "nothing started on a bad tree"
  reset; echo 'not json' > "$S/tickets.json"
  bin/dispatch projects/demo >/dev/null 2>&1; assert_eq "$?" 1 "unreadable tickets output exits 1"
  reset; tickets "$(row 1.1 low)"; mv "$CK/_bmad" "$CK/_nobmad"
  out=$(bin/dispatch projects/demo 2>&1); rc=$?; mv "$CK/_nobmad" "$CK/_bmad"
  assert_eq "$rc" 1 "no BMAD in the checkout exits 1"; assert_eq "$(calls)" 0 "nothing started without BMAD"
  bin/dispatch projects/nope >/dev/null 2>&1; assert_eq "$?" 2 "an unknown folder is refused"
}

run_journaled() {
  reset; tickets "$(row 1.1 low),$(row 2.1 high)"
  bin/dispatch projects/demo >/dev/null || fail "dispatch for the journal"
  assert_eq "$(journal_lines)" 1 "one journal line per run"
  grep -q '^dispatch: started 1.1; waiting for the owner: 2.1$' "$J" || fail "journal lists started and waiting: $(cat "$J")"
  reset; tickets ""
  bin/dispatch projects/demo >/dev/null || fail "dispatch with nothing"
  grep -q '^dispatch: started none; waiting for the owner: none$' "$J" || fail "an empty run is journaled: $(cat "$J" 2>/dev/null)"
}

starts_one_by_default; max_capped_at_two; running_ticket_not_restarted; high_risk_waits
approve_starts_one; only_ready_started; bad_tree_starts_nothing; run_journaled
echo ok
