# S1: bin/session-end without a hook

Status: Done (2026-11-09): QA re-verification green; adversarial code re-review PASS. Source: `docs/plans/2026-11-09-other-ai-cli-agents.md`, section "S1: `bin/session-end` without a hook".
Verification command: `bash tests/run.sh` (architecture verification command, `docs/architecture.md`).

## Goal

`bin/session-end` can be run by something other than Claude Code's SessionEnd hook (the launcher in S2b, and by hand)
without hanging, without losing its start time, and without racing a manual or automatic sync. It must keep the hook
behaviour that exists today.

Today `bin/session-end` reads its whole stdin with `in=$(cat ...)` (`bin/session-end:8`). A stdin that never closes
blocks it forever. Verified on the current code: `sleep 60 | script -q /dev/null bin/session-end projects/demo` runs
until a 15 s watchdog kills it (exit 143). That is the red state the first test must reproduce.

## Scope

1. **Input.** Replace `in=$(cat 2>/dev/null)` with a bounded read: the Python deadline read from `bin/changes` lines 13-21
   (2 s, `select` loop, returns whatever arrived). Copy it or move it to one shared helper; if shared, `bin/changes`
   behaviour must not change (`tests/test_changes.sh` stays green).
2. **Arguments.** `bin/session-end [folder] [--since <epoch>]`. `folder` defaults to `.` as today.
   - `--since <epoch>`: an exact start time, digits only. It wins over the transcript timestamp.
   - Without `--since`: today's rule (transcript first-line timestamp, else the last 8 hours) is unchanged.
   - Any other argument, including `--launch`, is refused with exit 2 and a message naming it. `--launch` is S2b's
     and must not be added here.
3. **Sync lock.** The commit step (journal line + `commit_folder`) runs under the sync lock, the same lock path as
   `bin/sync` (`$(state_dir)/sync.lock`, or `AGENT_SYNC_LOCK`).
   - Wait up to `AGENT_LOCK_WAIT` seconds (default 30), polling about once a second.
   - Stale handling identical to `bin/sync --auto` (test_sync.sh): a lock whose pid is dead, or that is over 120 minutes
     old, is removed and logged.
   - If the lock is still held by a live process after the wait, skip the commit and journal that (see AC8).
   - Release the lock before `auto_sync` starts, so the `bin/sync --auto` it spawns can take the same lock.
   - Only remove a lock whose pid file is this process's own pid (the same trap rule `bin/sync` uses).
4. **`bin/sync --yes`** takes the same lock as `--auto`. It waits up to `AGENT_LOCK_WAIT`. If still busy, it exits 1 with
   `another sync is running` on stderr and commits nothing. Review mode (no flag) stays read-only and takes no lock.
   `--auto` keeps today's behaviour: skip and log when busy, exit 0.
5. **Log.** When `--since` is given, one line per run is appended to the session-end log:
   `$(state_dir)/logs/session-end.log`, overridable by `AGENT_SESSION_END_LOG` (this path is the story's choice; the plan
   names only "the session-end log"). The line holds the UTC timestamp, the folder, the start epoch and the outcome
   (`committed`, `nothing to commit`, `skipped: sync lock busy`, or `refused: <reason>`).
6. **Exit codes.** The hook path (no `--since`, folder argument only) keeps exit 0 in every case, as its header says.
   Bad usage (non-digit `--since`, unknown argument) exits 2 with a message on stderr.

## Out of scope

- `--launch <id>`, the once-only marker and the double-fork launcher (S2b).
- The per-launch inbox and its apply (S2c).
- Native hooks (S4).
- Any change to what gets committed (still `$F` and `journal` only, via `commit_folder`).
- Changing `bin/sync`'s push or rebase logic.
- Changing the 8-hour fallback or the transcript parsing.

## Acceptance criteria

Each criterion is covered by a named check in `tests/test_session_end.sh` (new) or `tests/test_sync.sh` (existing, extended).
Each check prints its name on failure through `fail`, so QA can read which one broke.

| AC | Criterion | Automated test |
|---|---|---|
| AC1 | With a stdin pipe whose writer never closes, run under `script -q /dev/null`, `bin/session-end` finishes within 20 s and commits the folder. **Fails on today's code** (hangs in `cat`). | `held_pipe_under_script_finishes` |
| AC2 | With a never-closing stdin pipe and no pty, `bin/session-end F` finishes within 20 s, exits 0, and commits the folder. | `never_closing_pipe_finishes` |
| AC3 | Without `--since`, the start time still comes from the transcript's first-line timestamp (a commit older than that timestamp is not journaled; one after it is). | `hook_start_from_transcript` |
| AC4 | With `--since <epoch>`, that epoch is the start: a commit dated before it is not journaled, one dated after it is. | `since_sets_exact_start` |
| AC5 | `--since abc` exits 2 with a message on stderr and makes no commit. | `since_rejects_non_epoch` |
| AC6 | `--launch x` (and any unknown argument) exits 2 with `unknown argument` on stderr and makes no commit. | `unknown_argument_refused` |
| AC7 | A sync lock held by a live pid that is released inside the wait window does not stop the commit: the folder is committed and the run exits 0. | `waits_for_lock_then_commits` |
| AC8 | A sync lock still held by a live pid after the wait: no commit, the hub files remain uncommitted (`git status` shows them), one journal line says the commit was skipped because the sync lock was busy and lists the commits, exit 0, and the other process's lock directory is left in place. | `busy_lock_skips_and_journals` |
| AC9 | A stale lock (pid dead) and a lock older than 120 minutes are each removed, logged as `removed stale lock`, and the commit proceeds. | `stale_lock_removed` |
| AC10 | The lock is released before the follow-on sync: a real `bin/sync --auto` spawned by `auto_sync` logs `synced:` and never `skipped: another sync is running`. (`AGENT_AUTO_SYNC=1`, a gitleaks stub on PATH, and `AGENT_SYNC_LOCK` shared with `bin/session-end`.) | `release_before_auto_sync` |
| AC11 | `bin/sync --yes` waits for a lock held by a live pid that is released inside the window, then commits and exits 0. | `sync_yes_waits_for_lock` |
| AC12 | `bin/sync --yes` with a lock that never clears exits 1 with `another sync is running` on stderr, and commits nothing. | `sync_yes_busy_fails` |
| AC13 | `bin/sync` review mode (no flag) takes no lock: with the lock dir present it still lists pending changes and exits 0. | `sync_review_takes_no_lock` |
| AC14 | When `--since` is given, one line per run is appended to `$(state_dir)/logs/session-end.log` (or `AGENT_SESSION_END_LOG`) containing the folder, the start epoch and the outcome word from the list in Scope 5. | `since_writes_session_end_log` |
| AC15 | The default lock wait is 30 s: `sync_lock_wait` (in `bin/lib.sh`) prints `30` when `AGENT_LOCK_WAIT` is unset, and the value of `AGENT_LOCK_WAIT` otherwise. The other checks set `AGENT_LOCK_WAIT=3` to keep the suite fast. | `lock_wait_default_is_30` |
| AC16 | On the hook path (no `--since`), exit status is 0 in every busy, stale and nothing-to-commit case. | `hook_path_always_exits_zero` |
| AC17 | `bin/changes` and `tests/test_changes.sh` are unchanged in behaviour (the read is shared or copied, and the existing changes tests pass). | `tests/test_changes.sh` (existing, run by `tests/run.sh`) |
| AC18 | `tests/test_sync.sh` existing checks still pass, including the `--auto` lock-skip and stale-lock checks. | `tests/test_sync.sh` (existing, run by `tests/run.sh`) |

## Test notes (TDD order)

1. Write `tests/test_session_end.sh` with AC1 first, using the probe shape that was verified on today's code:
   a background `sleep 60 | script -q /dev/null "$HUB/bin/session-end" projects/demo` with a watchdog. macOS has no
   `timeout` by default, so either source `bin/lib.sh` and use its `timeout` (it has a fallback), or use a manual
   watchdog. Confirm the test fails (red) before changing `bin/session-end`.
2. Add AC2, then AC3 to AC6 (which need the bounded read and the argument parser).
3. Add the lock tests (AC7 to AC10), then extend `tests/test_sync.sh` for AC11 to AC13.
4. Add AC14 to AC16. AC15 is a `lib.sh` function test.
5. Run the whole suite. A test that is only red because of a missing function name is not a red test for the right reason;
   check the failure message.

Use a `make_hub` hub from `tests/helpers.sh` for every check. Set `AGENT_AUTO_SYNC=0` (the helper already does) except
in AC10. Keep held-lock helpers as `sleep` background processes that are killed in cleanup.

## Files touched

- `bin/session-end`: bounded read, argument parsing, lock around the commit step, release before `auto_sync`, log line.
- `bin/sync`: `--yes` takes the lock and waits; review mode unchanged.
- `bin/lib.sh`: `sync_lock_wait` (and, if shared, the lock acquire/release helper used by both scripts). Shared with SP and
  S2a, which also edit this file; keep the edit to adding functions, and do not touch the `hub.conf` sourcing block at
  `bin/lib.sh:47`.
- `bin/changes`: only if the deadline read is moved into a shared helper; otherwise unchanged.
- `tests/test_session_end.sh`: new.
- `tests/test_sync.sh`: extended for AC11 to AC13 (existing checks unchanged).
- `docs/stories/S1-session-end-without-hook.md`: this file. The Verification section is filled by QA only.

## Dependencies and shared contracts

- None before it. It runs in parallel with the SP and S3a work (plan priority: S0 item 21 and SP first, S1 alongside).
- Shared with S2b: the `session-end` argument shape (`F [--since N]`). S2b adds `--launch`, so S1 must leave the parser
  in a form where a new option is one added case.
- Shared with S2c: the lock is held around the commit step, so S2c's inbox apply can run inside the same lock.
- No new `.ade/context/` entry is needed for S1 (the lock path and the log path are existing conventions; record the log
  path in the README if the Dev changes it).

## Coding standards

- Bash 3.2 compatible (macOS `/bin/bash`): no associative arrays, no `mapfile`, no `${var,,}`.
- Use the existing helpers: `state_dir`, `hub_root`, `utc_now`, `bin/journal`.
- Never print or log a secret. This story does not touch secrets.
- Keep the hook path quiet: nothing on stdout from the hook path (the existing scripts send output to /dev/null).

## Verification

Command: `bash tests/run.sh` (must print `ok    test_session_end.sh` and `ok    test_sync.sh`, and exit 0).

Real output recorded by QA:

QA run 2026-11-09, branch s1-session-end, `bash tests/run.sh`, exit 0:

```
ok    test_brain.sh
ok    test_briefing.sh
ok    test_changes.sh
ok    test_context.sh
ok    test_doctor.sh
ok    test_init.sh
ok    test_lib.sh
ok    test_models.sh
ok    test_monitor.sh
ok    test_new.sh
ok    test_precommit.sh
ok    test_remote.sh
ok    test_report.sh
ok    test_root.sh
ok    test_schedule.sh
ok    test_secret.sh
ok    test_session_end.sh
ok    test_setup.sh
ok    test_sync.sh
ok    test_work.sh
EXIT 0
```

AC coverage (tests read, not just the exit code): AC1-AC16 each map to the named check (`CHECK=` in
`tests/test_session_end.sh`; AC11-AC13 in `tests/test_sync.sh`) and each asserts the criterion (exit code, commit or no
commit, journal line, lock dir/pid, log lines). AC17 and AC18 are covered by `test_changes.sh` and `test_sync.sh` passing;
`bin/changes` is untouched (the deadline read was copied into `bin/session-end`).
Slice: diff vs origin/other-ai-clis touches bin/lib.sh (functions added only), bin/session-end, bin/sync, the two test
files and `.ade/knowledge/developer.md` (a Dev note, harmless). No `--launch` option added (it is only refused).
Minor, not blocking: AC1's pre-change red state was not re-run by QA; the check does use the verified `script` probe shape.

Verdict: PASS. Done.

### QA re-verification 2026-11-09 (after reopen; fixes in bccbd79), branch s1-session-end, `bash tests/run.sh`

Real output (the run was piped through `tail`, so the shell exit code shown is tail's; every one of the 20 files printed
`ok` and no FAIL line appeared):

```
ok    test_brain.sh
ok    test_briefing.sh
ok    test_changes.sh
ok    test_context.sh
ok    test_doctor.sh
ok    test_init.sh
ok    test_lib.sh
ok    test_models.sh
ok    test_monitor.sh
ok    test_new.sh
ok    test_precommit.sh
ok    test_remote.sh
ok    test_report.sh
ok    test_root.sh
ok    test_schedule.sh
ok    test_secret.sh
ok    test_session_end.sh
ok    test_setup.sh
ok    test_sync.sh
ok    test_work.sh
```

New checks read, not just run; each exists and asserts what it claims:
- `stale_takeover_one_holder` (test_session_end.sh): 40 rounds of 4 concurrent takers on a dead-pid lock; asserts exactly one "won" and no "lost" per round, plus an expired takeover guard (`.gc`) does not block the lock.
- `release_before_auto_sync`: brain stub records whether the lock dir exists when the step before auto_sync runs; asserts "free" and that the follow-on sync did not log "another sync is running" and did sync.
- `only_owner_releases_lock`: pre-commit hook writes another live pid into the pid file; asserts the lock dir survives and still names that pid.
- `sync_yes_only_owner_releases` (test_sync.sh): same shape for `bin/sync --yes`.
- `lock_wait_is_at_least_w`: `date +%s` is faked to tick at x.9 s; asserts a busy lock is waited on >= 2000 ms and never taken.
- `refused_commit_logged`: refusing pre-commit hook; asserts exit 0, last log line ends "failed: commit refused", hook path exit 0.
- `since_digit_count`: 8 and 12 digits exit 2 with no commit; 9 digits accepted.
- `since_not_echoed_into_log`: `evil` and a newline-forged value; asserts one log line per run, neither string in the log, both logged as "refused:".
- `stdin_read_capped`: `yes |` flood; asserts committed and elapsed <= 5 s.

AC1-AC18 still each map to a named check as in the first verification (AC11-AC13 in test_sync.sh; AC17/AC18 via
test_changes.sh and test_sync.sh green). Not proven by QA: the new checks' red state against the pre-fix code was not
re-run (the race check is probabilistic by design, 40 rounds).

Verdict (QA): PASS on re-verification. Status is NOT Done: awaiting the adversarial code re-review.
