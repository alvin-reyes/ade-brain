# Shipping changes safely

Patterns that kept production quiet in real client work. They apply to any hub persona that changes a live system.
Two skeletons go with them: `templates/scripts/staged-change.sh` and `templates/scripts/prodtest.sh` (both tested in
`tests/`).

## A production change is a staged script

Write one script per change, review it like code, and run it on the machine in three steps:

- **`check`** is read-only. It runs every precondition and prints what `go` would do. Run it as often as you like.
- **`go`** runs the preconditions again, takes a backup, makes the change, then runs a health check. If the check
  fails, the script undoes the change itself and says so.
- **`undo`** restores the backup from the last `go`, then runs the health check again.

Preconditions worth checking: the machine is on the expected version (refuse to stack on an unknown state), no local
edits, the change window is open, no scheduled job is mid-run (take its lock, or refuse when a job starts within a
minute or two), enough free disk for the backup, and the system is healthy before you start. Each failure stops with
"nothing changed". Run the new code's own tests and pinned eval counts on a scratch copy before switching to it.

Guard every `rm` with `${VAR:?}`, so an empty variable can never delete a root. Read secrets at runtime into a
variable; never echo them, log them, or put them on a command line. Print switch names and 0/1, mask other values.

Outside the window the script refuses unless an explicit override is set (`DAYTIME_OK=1`) together with the name of
whoever approved that run (`APPROVED_BY=`). An override without an approver is refused too.

A change with no undo (pruning old backups, a one-way migration) says so at the top and keeps the newest rollbacks.

## Production tests are read-only

After a deploy, or whenever someone asks "is it OK?", run a read-only test: one `PASS`, `FAIL` or `WARN` line per
check and a summary line (`== RESULT: N pass, N fail, N warn`). `FAIL` means wrong now (wrong version, a service
down, a switch in the wrong state); `WARN` means worth a look (a traceback today, a stale log, disk filling). It writes
nothing: read-only database sessions, GET requests only, no messages sent.

## Test before production

- **SIT first.** Run the full suite against a copy of the system on a separate machine before any deploy. Fake the
  external services the system talks to (messaging, email, payment, third-party APIs) and run an egress logger, so a
  test that would have reached a real person shows up as a logged attempt, not a sent message. The suite must pass in
  full on the exact commit being deployed; never stop a suite mid-run and call it green.
- **Pin eval counts.** Record the expected number (`evals: 40 passed, 0 failed`) and fail on any other count. A
  shrinking count is a lost test, not a pass.

## Review until SHIP

- Loop **review, fix, re-review** until the reviewer says SHIP. Each round gets a fresh reviewer brief that asks for
  new adversarial probes, not a re-read of the last round's findings.
- **Revert checks**: for every fix, undo it and run its test. The test must fail. A test that passes with the fix
  removed tests nothing.
- Give the reviewer the code and the rules, not your conclusion.

## Safety-first automation

When an automated step is unsure (an ambiguous match, missing data, a rule that does not clearly apply), it hands the
case to a human and does not send. A missed automatic reply costs a minute of someone's time; a wrong one sent to a
customer costs trust. Make "hand to the human" the default branch, and make each "send" branch earn its place with a
test.

## Working with agents and approvals

- **Relayed approvals.** If an approval reaches you second-hand (through another agent or a summary) and a safety
  check blocks acting on it, ask the owner directly. A relayed "yes" is not the owner's "yes".
- **Hand-back fallback.** Ask each subagent to also write its result to a summary file in the scratch area, so the
  work survives a lost or truncated hand-back.
- **Deploy freeze.** During a freeze, build and test as usual but stop at a draft PR. Nothing merges or deploys until
  the freeze lifts.
- **Document on the board.** When a stakeholder is not on the email or chat thread, put the decision, the change and
  its result on the shared board or issue they do read, so the record does not depend on who was cc'd.
