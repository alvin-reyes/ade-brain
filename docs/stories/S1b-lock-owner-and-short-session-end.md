# S1b: lock owner rule and short session end

Status: Ready for development (2026-11-09). Follows S1 (`docs/stories/S1-session-end-without-hook.md`, Done).
Source: owner decisions 2026-11-09 in `.ade/session.md` (1: sync lock rule; 2: session end detaches brain and sync).
Verification command: `bash tests/run.sh` (architecture verification command, `docs/architecture.md`).
Branch: `s1b-story`, based on `origin/s1-session-end`. PR base: `other-ai-clis`. The PR carries all of S1's commits
(`5a7196b` through `5b6442e`): PR #5 was squash-merged as `649e3a7`, so none of the S1 commits are ancestors of
`other-ai-clis`, and the review fixes and Done commits were never in it.

## Goal

Two changes to the sync lock and the SessionEnd path, both decided by the owner:

1. **The lock owner rule.** A sync lock is removed only when its owner is gone: its pid file names a pid that no
   longer exists, or it has no usable pid (file missing, empty, or not digits) and is older than a short grace. A lock
   held by a live process is never removed, however old. This replaces S1's 120-minute age rule (S1 AC9).
2. **A short session end.** On the SessionEnd hook path, `bin/session-end` journals and commits under the lock as
   today, releases the lock, starts `refresh_brain` (`bin/brain index`) and `auto_sync` (`bin/sync --auto`) detached,
   and returns. The hook must not wait on either.

## Scope

1. **Owner rule (`bin/lib.sh`).** `_sync_lock_stale <lock>` returns 0 (stale) when:
   - the pid file holds digits and `ps -p <pid>` finds no process; or
   - the pid file is missing, empty, or not digits, and the lock directory's mtime is more than `sync_lock_grace`
     seconds ago.
   Nothing else makes a lock stale. The 120-minute `find -mmin +120` test is deleted.
   - Use `ps -p`, not `kill -0`: `kill -0` fails with EPERM for a live process owned by someone else, which would
     wrongly count it as gone.
   - Grace: new function `sync_lock_grace` prints `10` (fixed; no override). The age is measured from the lock
     directory's mtime (`stat -f %m`, the same macOS form `_sync_lock_reap` uses). A lock directory created just now,
     whose pid is not written yet, is not stolen.
   - Pid reuse (decision, fail-safe): a reused pid is a live process, so the lock is kept until that process exits. No
     run ever takes a lock from a live process. The cost is that a dead owner whose pid was reused blocks sync until that
     process exits or someone removes the lock directory by hand. The logs already say `skipped: another sync is
     running`. The owner should confirm this trade-off (open question below).
   - `sync_lock_take`, `_sync_lock_reap` and the guarded takeover (`<lock>.gc`, judged again inside the guard, moved
     aside and checked by inode) are kept as they are. Only the staleness test changes.
   - Update the comments in `bin/lib.sh` (`sync_lock_take`), `bin/sync` (the `--auto` header and the "over 2 hours old"
     comment) and `tests/test_sync.sh` (the "over 2 hours old" comment) to the new rule.
   - `.ade/context/auto-sync-and-monitors.md` (instruction only, the scrum-master does not edit it): its line that says
     "A stale lock (owner pid dead, or over 120 minutes old)" must be rewritten to the owner rule above. Only that
     staleness sentence changes. The Dev makes this edit in the story's branch.

2. **Detached work on the hook path (`bin/session-end`).**
   - Order on the hook path (no `--since`): stdin read, journal and commit under the lock, lock released, then start
     the detached job and `exit 0`. The lock is released before the job starts, so `bin/sync --auto` inside it can take
     the lock (S1 AC10 still holds).
   - The detached job runs `refresh_brain` first, then `auto_sync`, in that order (the same order as today, when the
     brain index finished before the sync was started).
   - How to detach (the Dev may choose the exact form, but these are required):
     - a new session (`setsid`, or `python3 -c 'import os; os.setsid(); ...'`; macOS has no `setsid` CLI, and
       `python3` is already used by the stdin read). Fall back to `nohup` only when `python3` is missing, and say so in
       the code comment;
     - stdin from `/dev/null`, stdout and stderr to the session-end log (`$LOG`), never the hook's own pipes;
     - not waited on by the hook process.
   - How the job re-enters the script: `bin/session-end` checks an internal environment variable
     (`AGENT_SESSION_END_BG=1`) before parsing arguments. When it is set, the script runs only the two detached steps
     for the folder given, and writes no journal line. Do not add a new command-line option: S2b owns the argument
     parser, and `--launch` must stay refused (S1 AC6).
   - Why detach here: the Claude Code SessionEnd hook waits on the hook's output pipes. A background child that keeps
     them open keeps the hook running, however quickly the script itself returns. The brain index can take up to its
     120 s timeout. The sync can wait on the network.
   - Failures in the detached job are logged to the session-end log, one line each, even on the hook path (where
     nothing else is logged on success):
     `bg step failed: brain index exit <n>` and `bg step failed: sync exit <n>`. A step that succeeds logs nothing.
     The line never contains the stderr of the step or any secret.

3. **`--since` stays foreground (decision).** When `--since` is given, the outcome line is written as today, and then
   `refresh_brain` and `auto_sync` run in the foreground, in that order, with the lock already released. Failures of
   those steps are logged in the same `bg step failed:` format. Why: `--since` is the launcher's path (S2b, plan
   section "Session end"), and the launcher already double-forks with `setsid` and stdin on `/dev/null`, so no session
   waits on it. Foreground keeps the outcome and the step results in one run, which the tests can check. Nothing in the
   code asks for a detached `--since` run: the hook is the only caller that needs the short return.
   - Exit codes are unchanged: 0 for the hook path in every case, 0 for a `--since` run whose steps fail (the failure
     is logged, as today).

4. **Test harness safety.** Every detached child must have its stdout and stderr redirected away from the test's
   pipe. `tests/run.sh` captures each test with `$( )`, which waits for every writer of that pipe to close. A background
   job that keeps it open makes the whole suite hang.

5. **`bin/sync --yes`.** Unchanged in behaviour. Its lock uses the new owner rule through the shared
   `_sync_lock_stale`, and its existing `sync_yes_only_owner_releases` check still holds.

## Out of scope

- `--launch <id>`, the once-only marker and the double-fork launcher (S2b). This story does not add the launcher.
- Any change to what is committed (still `$F` and `journal` only, via `commit_folder`).
- `bin/sync`'s push, rebase and gitleaks logic. Only its lock comments change.
- Recording the pid together with the process start time to detect pid reuse. That is a format change that would break
  the pid-file checks in the tests. It stays a possible follow-up if the owner wants it.
- Changing the busy-lock wait (`AGENT_LOCK_WAIT`, default 30 s). See the open question about the hook's time limit.
- Any change to `bin/changes`, `bin/brain`, the 8-hour fallback, or the transcript parsing.

## Acceptance criteria

Each criterion is covered by a named check in `tests/test_session_end.sh` or `tests/test_sync.sh`. Each check prints its
name through `fail`. ACs marked **changed** replace the S1 criterion of the same number. ACs 1 to 8 and 11 to 17 are
S1's, unchanged; AC18 is S1's and its existing check still passes unmodified except for the comment.

| AC | Criterion | Automated test |
|---|---|---|
| AC1 | (S1, unchanged) Held pipe under `script -q /dev/null`: finishes within 20 s, commits. | `held_pipe_under_script_finishes` |
| AC2 | (S1, unchanged) Never-closing pipe, no pty: finishes within 20 s, exit 0, commits. | `never_closing_pipe_finishes` |
| AC3 | (S1, unchanged) Without `--since`, the start comes from the transcript's first-line timestamp. | `hook_start_from_transcript` |
| AC4 | (S1, unchanged) With `--since <epoch>`, that epoch is the exact start. | `since_sets_exact_start` |
| AC5 | (S1, unchanged) `--since abc` exits 2, message on stderr, no commit. | `since_rejects_non_epoch` |
| AC6 | (S1, unchanged) `--launch x` and any unknown argument exit 2 with `unknown argument`, no commit. | `unknown_argument_refused` |
| AC7 | (S1, unchanged) Live lock released inside the wait window: the folder is committed, exit 0. | `waits_for_lock_then_commits` |
| AC8 | (S1, unchanged) Live lock still held after the wait: no commit, files left uncommitted, one busy-lock journal line listing the commits, exit 0, other process's lock left in place. | `busy_lock_skips_and_journals` |
| AC9 | **Changed.** A lock whose pid is dead, and a lock with an empty pid file whose directory is older than the grace (10 s), are each removed, logged `removed stale lock`, and the commit proceeds. The age-only (120-minute) removal of S1 is gone; AC19 covers the live case. | `stale_lock_removed` |
| AC10 | **Changed.** The lock is free when the detached brain step starts (the stub records whether `<lock>` exists), and the detached `bin/sync --auto` logs `synced:` and never `skipped: another sync is running`. The test waits for both detached steps (polls the brain marker and the sync log) before checking. Uses `AGENT_AUTO_SYNC=1`, a gitleaks stub on PATH, `AGENT_SYNC_LOCK` shared with `bin/session-end`. | `release_before_auto_sync` |
| AC11 | (S1, unchanged) `bin/sync --yes` waits for a lock released inside the window, then commits, exit 0. | `sync_yes_waits_for_lock` (test_sync.sh) |
| AC12 | (S1, unchanged) `bin/sync --yes` with a lock that never clears: exit 1, `another sync is running` on stderr, no commit. | `sync_yes_busy_fails` (test_sync.sh) |
| AC13 | (S1, unchanged) `bin/sync` review mode takes no lock. | `sync_review_takes_no_lock` (test_sync.sh) |
| AC14 | (S1, unchanged) With `--since`, one log line per run in `$(state_dir)/logs/session-end.log` (or `AGENT_SESSION_END_LOG`): folder, start epoch, outcome word. The brain stub in this check exits 0, so no `bg step failed` line appears. | `since_writes_session_end_log` |
| AC15 | (S1, unchanged) `sync_lock_wait` prints `30` by default, and the value of `AGENT_LOCK_WAIT` otherwise. | `lock_wait_default_is_30` |
| AC16 | (S1, unchanged) Hook path exit status is 0 in every busy, stale and nothing-to-commit case. | `hook_path_always_exits_zero` |
| AC17 | (S1, unchanged) `bin/changes` and `tests/test_changes.sh` unchanged in behaviour. | `tests/test_changes.sh` (existing) |
| AC18 | (S1, unchanged) The existing `tests/test_sync.sh` checks still pass, including the `--auto` lock-skip and the stale-lock check. That check uses a lock with no pid file and an old date, which the new rule still removes. Only its comment changes. | `tests/test_sync.sh` (existing) |
| AC19 | **New.** A lock held by a live pid and dated 2020 is not removed. The commit is skipped (busy-lock journal line, hub files uncommitted), exit 0, and the other process's pid stays in the lock. | `live_old_lock_kept` |
| AC20 | **New.** A lock directory with no pid file, created less than 10 s ago, is not removed while the wait runs. The commit is skipped as busy and the directory stays. | `fresh_pidless_lock_kept` |
| AC21 | **New.** `sync_lock_grace` (in `bin/lib.sh`) prints `10`. | `lock_grace_is_10` |
| AC22 | **New.** `bin/sync --yes` with a live pid and a 2020 date: exit 1, `another sync is running` on stderr, lock kept. | `sync_yes_live_old_kept` (test_sync.sh) |
| AC23 | **New.** Hook path with a brain stub and a sync command stub that each sleep 8 s: `echo '{"transcript_path":""}' \| bin/session-end projects/demo 2>&1 \| cat` returns within 5 s, and the lock directory is already gone when it returns. The pipeline's end (not a timer inside the script) is what is measured. | `hook_returns_within_bound` |
| AC24 | **New.** The same run: after the hook returns, the brain marker and then the sync marker appear within 30 s. The sync stub finds the brain marker already present (the order holds). | `background_runs_to_completion` |
| AC25 | **New.** Brain stub exits 3 and sync command stub exits 1: the session-end log gets one `bg step failed: brain index exit 3` line and one `bg step failed: sync exit 1` line, the hook still exits 0, and it prints nothing on stdout or stderr. | `background_failure_logged` |
| AC26 | **New.** With `--since`, the brain and sync markers exist by the time `bin/session-end` returns, the outcome line is written, and the lock is released. | `since_runs_foreground` |
| AC27 | **New.** Hook path with exit-0 stubs: the session-end log gets no new line. | `hook_logs_nothing_on_success` |
| AC28 | **New.** The detached steps run in their own session: a brain stub that writes `ps -o pgid= -p $$` records a process group different from the test shell's. | `background_own_session` |

## Test notes (TDD order)

Write the tests first, run them, and confirm each new check fails for the right reason before touching the code. A
missing function (`sync_lock_grace: command not found`) is not a red test for AC21 in the right sense; check the message
says what was wanted (`got [] want [10]`).

1. **AC23 first.** Add `hook_returns_within_bound` (stubs: `bin/brain` sleeps 8 s and writes a marker; `AGENT_SYNC_CMD`
   points at a stub that sleeps 8 s and writes a marker). On today's code the hook takes about 8 s in the foreground:
   red for the right reason (`hook took 8 s`).
2. **AC24, AC25, AC27, AC28** on the same stubs. Then **AC26** (`--since` foreground): expect it green on today's code
   for the markers, and check that the new `bg step failed` lines are absent until they are written.
3. **AC9 (changed).** Replace its second half with an empty pid file dated 2020 and no live owner. Red on today's code
   (the 120-minute rule is not met): `dead owner's lock kept` or `old lock: not committed` style message.
4. **AC19, AC20, AC21, AC22.** Red on today's code for AC19 (the old live lock is removed) and AC21/AC22 (function
   missing or lock removed). AC20 passes today (a fresh pid-less lock is kept); it is a guard for the new rule.
5. **Implement** `_sync_lock_stale`, `sync_lock_grace`, the detached job and the `--since` foreground path. Then
   **AC10** (update the wait so it polls both detached steps). Then the comment changes in `bin/sync` and
   `tests/test_sync.sh` and the context sentence.
6. Run `bash tests/run.sh` and then `bash tests/test_session_end.sh` and `bash tests/test_sync.sh` on their own. Run the
   suite twice in a row: the new bound and background checks depend on timing, so a flaky pass is not a pass.

Use a `make_hub` hub for every check. Keep held-lock helpers as `sleep` background processes that are killed in cleanup.
Background markers and log lines are polled (up to 30 s), never fixed-sleep. Every test-owned stub writes its marker
with a `date +%s` and nothing else to stdout.

## Files touched

- `bin/lib.sh`: `_sync_lock_stale` rewritten to the owner rule, `sync_lock_grace` added, `sync_lock_take` comment.
  Shared with S2a, S2b, SP: keep the edit to the staleness test and the new function. Do not touch the `hub.conf`
  sourcing block at `bin/lib.sh:47`.
- `bin/session-end`: header comment (the detached part and `--since` foreground); the detached job (env-var re-entry,
  new session, redirects); the `bg step failed:` log lines; the `--since` branch that runs both steps in the foreground.
- `bin/sync`: header and the `--auto` comment (stale rule); no behaviour change.
- `tests/test_session_end.sh`: AC9 (changed), AC10 (changed), AC14 (brain stub exits 0), AC19 to AC28.
- `tests/test_sync.sh`: the "over 2 hours old" comment (AC18 check unchanged), AC22 added after `sync_yes_busy_fails`.
- `.ade/context/auto-sync-and-monitors.md`: only the staleness sentence (line 15), per the instruction above.
- `docs/stories/S1b-lock-owner-and-short-session-end.md`: this file. The Verification section is filled by QA only.

## Dependencies and shared contracts

- Depends on S1 (Done). Its lock path, log path, `--since` shape and AC numbers stay.
- Shared with S2b: the `session-end` argument shape is unchanged (`F [--since N]`). The detached job is re-entered by the
  environment variable `AGENT_SESSION_END_BG`, not by an option, so the parser S2b extends is untouched. Record this
  variable in the context entry only if the Dev is asked to; it is internal.
- Shared with S2c: the lock is still held around the commit step, and is released before the detached part.
- Plan reference: `docs/plans/2026-11-09-other-ai-cli-agents.md` "Session end" (S2b launcher) and "S1" (section lines
  399 to 410), which still describe the S1 lock rule. The plan is not edited by this story.

## Coding standards

- Bash 3.2 compatible (macOS `/bin/bash`): no associative arrays, no `mapfile`, no `${var,,}`.
- Use the existing helpers: `state_dir`, `hub_root`, `utc_now`, `sync_lock_path`, `sync_lock_wait`, `bin/journal`.
- `ps -p` for liveness; `stat -f %m` for mtime (the macOS forms the file already uses).
- Never log a secret or the stderr of a detached step. The `bg step failed:` line holds only the step name and status.
- Keep the hook path quiet: nothing on stdout or stderr from the hook path, and nothing in the session-end log on
  success.

## Owner decisions carried in (2026-11-09, `.ade/session.md`)

1. Sync lock: an old lock is removed only when its owner process is gone, or its pid file is missing, unreadable or
   empty after a grace (10 s). The 120-minute rule is removed; a live-but-old lock is kept. Supersedes S1 AC9.
2. Session end: detaches `refresh_brain` and `auto_sync` in the background on the hook path, after the lock is released,
   and returns. The `--since` (launcher and manual) path stays in the foreground (reasons in Scope 3).

## Open questions for the owner (do not block the story)

- Pid reuse: a dead owner's pid reused by a live unrelated process keeps the lock until that process exits. Accept, or
  add the process start time to the lock (a follow-up that changes the pid-file format)?
- The hook path still waits up to `AGENT_LOCK_WAIT` (30 s) when a live process holds the lock. The 5 s bound in AC23 is
  for the uncontended case only. Is a 30 s wait acceptable inside the SessionEnd hook, or should the hook path's wait
  be shorter?
- The review notes on the empty pid file case and pid reuse were not found in the repo text available to the
  scrum-master (only the owner's decision and the code). The handling above follows the decision and the code; the
  Dev should check it against the review text if it is attached to the PR.

## Verification

Command: `bash tests/run.sh` (must print `ok    test_session_end.sh` and `ok    test_sync.sh`, and exit 0).

Real output recorded by QA:

