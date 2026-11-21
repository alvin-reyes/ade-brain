# S1b: lock owner rule and short session end

Status: **Done (2026-11-21)**: verification green twice, quick review findings fixed. Earlier: Ready for development (2026-11-09; revised the same day with the owner's answers to the two open questions).
Follows S1 (`docs/stories/S1-session-end-without-hook.md`, Done).
Source: owner decisions 2026-11-09 in `.ade/session.md` (1: sync lock rule; 2: session end detaches brain and sync), and
the owner's answers of 2026-11-09 on pid reuse and on the hook's lock wait (see "Owner decisions carried in", 3 and 4).
Verification command: `bash tests/run.sh` (architecture verification command, `docs/architecture.md`).
Branch: `s1b-story`, based on `origin/s1-session-end`. PR base: `other-ai-clis`. The PR carries all of S1's commits
(`5a7196b` through `5b6442e`): PR #5 was squash-merged as `649e3a7`, so none of the S1 commits are ancestors of
`other-ai-clis`, and the review fixes and Done commits were never in it.

## Goal

Three changes to the sync lock and the SessionEnd path, all decided by the owner:

1. **The lock owner rule.** A sync lock is removed only when its owner is gone: its pid file names a pid that no
   longer exists; or its pid is alive but now belongs to a process with a different start time than the one the lock
   recorded (the pid was reused); or it has no usable pid (file missing, empty, or not digits) and is older than a short
   grace. A lock held by a live owner process (same pid, same start time) is never removed, however old. This replaces
   S1's 120-minute age rule (S1 AC9).
2. **A short session end.** On the SessionEnd hook path, `bin/session-end` journals and commits under the lock as
   today, releases the lock, starts `refresh_brain` (`bin/brain index`) and `auto_sync` (`bin/sync --auto`) detached,
   and returns. The hook must not wait on either.
3. **A short hook wait for a busy lock.** The hook path waits at most 5 s (`AGENT_HOOK_LOCK_WAIT`) for a busy lock, then
   skips its commit and journals it. `--since` and `bin/sync --yes` keep `AGENT_LOCK_WAIT` (default 30).

## Scope

1. **Owner rule (`bin/lib.sh`).** `_sync_lock_stale <lock>` returns 0 (stale) when:
   - a. the pid file holds digits and `ps -p <pid>` finds no process; or
   - b. the pid file holds digits, the process is alive, the start record `<lock>/start` names that same pid, and the
     live process's start time differs from the recorded one (pid reused); or
   - c. the pid file is missing, empty, or not digits, and the lock directory's mtime is more than `sync_lock_grace`
     seconds ago.
   Nothing else makes a lock stale. The 120-minute `find -mmin +120` test is deleted. A live pid is kept when there is
   no start record (old format), when the start record names a different pid than the pid file, or when its start field
   is empty: such a lock is judged by pid alone, as today.
   - Use `ps -p`, not `kill -0`: `kill -0` fails with EPERM for a live process owned by someone else, which would
     wrongly count it as gone.
   - **Start record (decision 2026-11-09, answer to open question 1).** `sync_lock_take` writes `<lock>/start`, one line
     `<pid> <start>`, for its own pid (`$$`). `<start>` is `proc_start $$`. New helper `proc_start <pid>` prints
     `LC_ALL=C ps -o lstart= -p <pid>` with runs of spaces collapsed to one and leading and trailing spaces trimmed; it
     prints nothing when `ps` prints nothing. The start record is written before `<lock>/pid`, so a visible pid file
     always has its start record already. If `proc_start` is empty, no start record is written and the lock is in the
     old format (judged by pid).
   - **Pid reuse (decision 2026-11-09).** Case b removes the lock, logged as every removal is (`removed stale lock`).
     A live pid whose start time matches the record is the owner and is kept, however old.
   - `sync_lock_release` is unchanged: it compares the pid file only. The start record goes with the directory.
   - Grace: new function `sync_lock_grace` prints `10` (fixed; no override). The age is measured from the lock
     directory's mtime (`stat -f %m`, the same macOS form `_sync_lock_reap` uses). A lock directory created just now,
     whose pid is not written yet, is not stolen.
   - `sync_lock_take`, `_sync_lock_reap` and the guarded takeover (`<lock>.gc`, judged again inside the guard, moved
     aside and checked by inode) are kept as they are. Only the staleness test and the start record write change.
   - Update the comments in `bin/lib.sh` (`sync_lock_take`), `bin/sync` (the `--auto` header, the stale-lock comment at
     line 27 that says "over 2 hours old") and `tests/test_sync.sh` (the "over 2 hours old" comment at line 64) to the new
     rule.
   - `.ade/context/auto-sync-and-monitors.md` (instruction only, the scrum-master does not edit it): two lines change.
     Line 12, the `AGENT_LOCK_WAIT` sentence, now says the hook path waits `AGENT_HOOK_LOCK_WAIT` (default 5) and
     `--since` and `--yes` wait `AGENT_LOCK_WAIT` (default 30). Line 15, the staleness sentence ("owner pid dead, or
     over 120 minutes old"), is rewritten to the owner rule above. Nothing else in that file changes. The Dev makes these
     edits in the story's branch.

2. **Detached work on the hook path (`bin/session-end`).**
   - Order on the hook path (no `--since`): stdin read, take the lock (waiting at most `sync_hook_lock_wait`, see 6),
     journal and commit under it, lock released, then start the detached job and `exit 0`. The lock is released before
     the job starts, so `bin/sync --auto` inside it can take the lock (S1 AC10 still holds).
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

3. **`--since` stays foreground (decision).** When `--since` is given, the lock wait is `AGENT_LOCK_WAIT` (default 30),
   the outcome line is written as today, and then `refresh_brain` and `auto_sync` run in the foreground, in that order,
   with the lock already released. Failures of those steps are logged in the same `bg step failed:` format. Why:
   `--since` is the launcher's path (S2b, plan section "Session end"), and the launcher already double-forks with
   `setsid` and stdin on `/dev/null`, so no session waits on it. Foreground keeps the outcome and the step results in one
   run, which the tests can check. Nothing in the code asks for a detached `--since` run: the hook is the only caller
   that needs the short return.
   - Exit codes are unchanged: 0 for the hook path in every case, 0 for a `--since` run whose steps fail (the failure
     is logged, as today).

4. **Test harness safety.** Every detached child must have its stdout and stderr redirected away from the test's
   pipe. `tests/run.sh` captures each test with `$( )`, which waits for every writer of that pipe to close. A background
   job that keeps it open makes the whole suite hang.

5. **`bin/sync --yes`.** Unchanged in behaviour. Its lock uses the new owner rule through the shared
   `_sync_lock_stale` and the start record through the shared `sync_lock_take`, and its existing
   `sync_yes_only_owner_releases` check still holds. It waits `AGENT_LOCK_WAIT` (default 30) and never reads
   `AGENT_HOOK_LOCK_WAIT`.

6. **Hook-path lock wait (decision 2026-11-09, answer to open question 2).** New function `sync_hook_lock_wait` in
   `bin/lib.sh` prints `${AGENT_HOOK_LOCK_WAIT:-5}`. `bin/session-end` takes the lock with `sync_hook_lock_wait` when
   `--since` is not given, and with `sync_lock_wait` (`AGENT_LOCK_WAIT`, default 30) when it is. When the lock is still
   busy after that wait, the hook path does what it does today: no commit, one journal line `hub commit skipped: sync
   lock busy`, exit 0. The header comment of `bin/session-end` (lines 8 to 9) says so. `sync_lock_take` already makes its
   tries one second apart, so the wait is about `W` seconds.

## Out of scope

- `--launch <id>`, the once-only marker and the double-fork launcher (S2b). This story does not add the launcher.
- Any change to what is committed (still `$F` and `journal` only, via `commit_folder`).
- `bin/sync`'s push, rebase and gitleaks logic. Only its lock comments change.
- The 10 s grace (no override) and the default `AGENT_LOCK_WAIT` of 30 s. Only the hook path gets its own knob.
- Recording the reason for a removal in the log (the line stays `removed stale lock` for every case).
- Any change to `bin/changes`, `bin/brain`, the 8-hour fallback, or the transcript parsing.

## Acceptance criteria

Each criterion is covered by a named check in `tests/test_session_end.sh` or `tests/test_sync.sh`. Each check prints its
name through `fail`. ACs marked **changed** replace the S1 criterion of the same number; ACs marked **new** have no S1
counterpart. ACs 1 to 6, 11 to 17 and 18 are S1's; AC18's existing check still passes unmodified except for the comment.

| AC | Criterion | Automated test |
|---|---|---|
| AC1 | (S1, unchanged) Held pipe under `script -q /dev/null`: finishes within 20 s, commits. | `held_pipe_under_script_finishes` |
| AC2 | (S1, unchanged) Never-closing pipe, no pty: finishes within 20 s, exit 0, commits. | `never_closing_pipe_finishes` |
| AC3 | (S1, unchanged) Without `--since`, the start comes from the transcript's first-line timestamp. | `hook_start_from_transcript` |
| AC4 | (S1, unchanged) With `--since <epoch>`, that epoch is the exact start. | `since_sets_exact_start` |
| AC5 | (S1, unchanged) `--since abc` exits 2, message on stderr, no commit. | `since_rejects_non_epoch` |
| AC6 | (S1, unchanged) `--launch x` and any unknown argument exit 2 with `unknown argument`, no commit. | `unknown_argument_refused` |
| AC7 | **Changed (wait knob).** Live lock released inside the hook's wait window: the folder is committed, exit 0. The check sets `AGENT_HOOK_LOCK_WAIT=5` (it set `AGENT_LOCK_WAIT=5`, which the hook path no longer reads); the lock is released 1 s in. | `waits_for_lock_then_commits` |
| AC8 | **Changed (wait knob).** Live lock still held after the hook's wait (`AGENT_HOOK_LOCK_WAIT`, set to 3 s by the check): no commit, files left uncommitted, one busy-lock journal line listing the commits, exit 0, other process's lock left in place. | `busy_lock_skips_and_journals` |
| AC9 | **Changed.** A lock whose pid is dead, and a lock with an empty pid file dated 2020 (older than the grace), are each removed, logged `removed stale lock` (two lines), and the commit proceeds. A live owner's lock dated 2020 is no longer removed: AC19 covers it. | `stale_lock_removed` |
| AC10 | **Changed.** The lock is free when the detached brain step starts (the stub records whether `<lock>` exists), and the detached `bin/sync --auto` logs `synced:` and never `skipped: another sync is running`. The test waits for both detached steps (polls the brain marker and the sync log) before checking. Uses `AGENT_AUTO_SYNC=1`, a gitleaks stub on PATH, `AGENT_SYNC_LOCK` shared with `bin/session-end`. | `release_before_auto_sync` |
| AC11 | (S1, unchanged) `bin/sync --yes` waits for a lock released inside the window, then commits, exit 0. | `sync_yes_waits_for_lock` (test_sync.sh) |
| AC12 | (S1, unchanged) `bin/sync --yes` with a lock that never clears: exit 1, `another sync is running` on stderr, no commit. | `sync_yes_busy_fails` (test_sync.sh) |
| AC13 | (S1, unchanged) `bin/sync` review mode takes no lock. | `sync_review_takes_no_lock` (test_sync.sh) |
| AC14 | (S1, unchanged) With `--since`, one log line per run in `$(state_dir)/logs/session-end.log` (or `AGENT_SESSION_END_LOG`): folder, start epoch, outcome word. The brain stub in this check exits 0, so no `bg step failed` line appears. | `since_writes_session_end_log` |
| AC15 | (S1, unchanged) `sync_lock_wait` prints `30` by default, and the value of `AGENT_LOCK_WAIT` otherwise. | `lock_wait_default_is_30` |
| AC16 | (S1, unchanged) Hook path exit status is 0 in every busy, stale and nothing-to-commit case. | `hook_path_always_exits_zero` |
| AC17 | (S1, unchanged) `bin/changes` and `tests/test_changes.sh` unchanged in behaviour. | `tests/test_changes.sh` (existing) |
| AC18 | (S1, unchanged) The existing `tests/test_sync.sh` checks still pass, including the `--auto` lock-skip and the stale-lock check. That check uses a lock with no pid file and an old date, which the new rule still removes. Only its comment changes. | `tests/test_sync.sh` (existing) |
| AC19 | **New.** A lock held by a live pid (pid-only, old format) and dated 2020 is not removed. The commit is skipped (busy-lock journal line, hub files uncommitted), exit 0, and the other process's pid stays in the lock. | `live_old_lock_kept` |
| AC20 | **New.** A lock directory with no pid file, created less than 10 s ago, is not removed while the wait runs. The commit is skipped as busy and the directory stays. | `fresh_pidless_lock_kept` |
| AC21 | **New.** `sync_lock_grace` (in `bin/lib.sh`) prints `10`. | `lock_grace_is_10` |
| AC22 | **New.** `bin/sync --yes` with a live pid (pid-only) and a 2020 date: exit 1, `another sync is running` on stderr, lock kept. | `sync_yes_live_old_kept` (test_sync.sh) |
| AC23 | **New.** Hook path with a brain stub and a sync command stub that each sleep 8 s: `echo '{"transcript_path":""}' \| bin/session-end projects/demo 2>&1 \| cat` returns within 5 s, and the lock directory is already gone when it returns. The pipeline's end (not a timer inside the script) is what is measured. | `hook_returns_within_bound` |
| AC24 | **New.** The same run: after the hook returns, the brain marker and then the sync marker appear within 30 s. The sync stub finds the brain marker already present (the order holds). | `background_runs_to_completion` |
| AC25 | **New.** Brain stub exits 3 and sync command stub exits 1: the session-end log gets one `bg step failed: brain index exit 3` line and one `bg step failed: sync exit 1` line, the hook still exits 0, and it prints nothing on stdout or stderr. | `background_failure_logged` |
| AC26 | **New.** With `--since`, the brain and sync markers exist by the time `bin/session-end` returns, the outcome line is written, and the lock is released. | `since_runs_foreground` |
| AC27 | **New.** Hook path with exit-0 stubs: the session-end log gets no new line. | `hook_logs_nothing_on_success` |
| AC28 | **New.** The detached steps run in their own session: a brain stub that writes `ps -o pgid= -p $$` records a process group different from the test shell's. | `background_own_session` |
| AC29 | **New.** `sync_lock_take` writes `<lock>/start` whose first field is the taker's pid and whose rest equals `proc_start` of that pid, and the pid file names the same pid. With `proc_start` overridden to print nothing, the lock is still taken and no `start` file is written. | `lock_records_start` |
| AC30 | **New.** A lock whose pid file names a live `sleep` and whose start record names that pid with a different start time (`Mon Jan  1 00:00:00 2001`): the hook removes the lock, the session-end log has one `removed stale lock` line, the folder is committed, exit 0. | `pid_reused_lock_removed` |
| AC31 | **New.** Same as AC30 but the start record holds the live pid's real `proc_start`: the lock is kept, the busy-lock journal line is written, the other process's pid stays in the pid file, exit 0. | `same_pid_same_start_kept` |
| AC32 | **New.** A pid-only lock (no start record, as written before this change): a live pid dated 2020 is kept, and a dead pid is removed. Both are judged by pid alone. | `old_format_judged_by_pid` |
| AC33 | **New.** The start record names pid A (live, its real start) but the pid file now names a different live pid B (the pre-commit overwrite case of `only_owner_releases_lock`): the lock is judged by B alone and kept. A's record is not compared with B. | `rewritten_pid_judged_alone` |
| AC34 | **New.** A lock with an unusable pid file (`abc`) and a start record present: a directory under 10 s old is kept (busy, exit 0), and one dated 2020 is removed. A start record never makes an unusable-pid lock stale. | `pidless_grace_still_applies` |
| AC35 | **New.** Hook path, no `--since`, `AGENT_HOOK_LOCK_WAIT` unset (so 5 s), a live pid-only lock held throughout: the pipeline returns after 4 to 9 s, exit 0, no commit, the busy-lock journal line, the lock kept. The check measures with `date +%s` before and after. | `hook_lock_gives_up_5s` |
| AC36 | **New.** With `--since` and `AGENT_LOCK_WAIT=12` (`AGENT_HOOK_LOCK_WAIT` unset), a live lock released about 8 s in: the folder is committed, the outcome is `committed`, exit 0, and the run took at least 7 s. Shows `--since` is not capped at the hook's bound. | `since_waits_full_window` |
| AC37 | **New.** `sync_hook_lock_wait` (in `bin/lib.sh`) prints `5` with `AGENT_HOOK_LOCK_WAIT` unset, and the value of `AGENT_HOOK_LOCK_WAIT` otherwise (7 in the check). | `hook_lock_wait_default_is_5` |
| AC38 | **New.** `bin/sync --yes` with `AGENT_HOOK_LOCK_WAIT=1`, `AGENT_LOCK_WAIT=10`, and a lock released about 6 s in: exit 0, the folder is committed. Shows `--yes` keeps `AGENT_LOCK_WAIT` and never reads the hook knob. | `sync_yes_uses_lock_wait` (test_sync.sh) |

## Test notes (TDD order)

Write the tests first, run them, and confirm each new check fails for the right reason before touching the code. A
missing function (`sync_hook_lock_wait: command not found`) is not a red test in the right sense on its own; check the
message says what was wanted (`got [] want [5]`). Some new checks are **guards**: they pass on today's code, because they
protect behaviour the change must keep. Write them, see them pass, and keep them green.

1. **AC23 first.** Add `hook_returns_within_bound` (stubs: `bin/brain` sleeps 8 s and writes a marker; `AGENT_SYNC_CMD`
   points at a stub that sleeps 8 s and writes a marker). On today's code the hook takes about 8 s in the foreground:
   red for the right reason (`hook took 8 s`).
2. **AC24, AC25, AC27, AC28** on the same stubs. Then **AC26** (`--since` foreground): expect it green on today's code
   for the markers, and check that the new `bg step failed` lines are absent until they are written.
3. **Hook wait.** Set `AGENT_HOOK_LOCK_WAIT=5` in AC7 and `AGENT_HOOK_LOCK_WAIT=3` in AC8 (both were `AGENT_LOCK_WAIT`).
   Then **AC35** (red today: the hook waits the exported `AGENT_LOCK_WAIT=3`, so it returns after about 3 s, `hook took
   3 s, want 4 to 9`) and **AC37** (red: `got [] want [5]`). **AC36** is a guard (green today: `--since` already waits
   `AGENT_LOCK_WAIT`). **AC38** is a guard in `tests/test_sync.sh`.
4. **AC9 (changed).** Replace the second half (the live pid dated 2020) with an empty pid file dated 2020 and no live
   owner. This is a **guard**: green today, because the 120-minute rule also removes it. The live-owner case moves to
   AC19, which is red today (the lock is removed).
5. **AC19, AC20, AC21, AC22.** Red on today's code for AC19 (the old live lock is removed), AC21 (`got [] want [10]`) and
   AC22 (the lock is removed and `--yes` goes on). AC20 is a guard (a fresh pid-less lock is kept today).
6. **AC29, AC30.** Red on today's code: AC29 (no start file: `got [] want [<pid>]`), AC30 (the live lock is kept, the
   commit is skipped). **AC31, AC32, AC33, AC34** are guards, green on today's code: they must stay green once the start
   record is compared, which is what makes them worth having.
7. **Implement** `proc_start`, `sync_lock_take`'s start record, `_sync_lock_stale` (cases a, b, c), `sync_lock_grace`,
   `sync_hook_lock_wait`, the hook's wait choice, the detached job and the `--since` foreground path. Then **AC10**
   (update the wait so it polls both detached steps). Then the comment changes in `bin/lib.sh`, `bin/sync`,
   `tests/test_sync.sh` and the two context lines.
8. Run `bash tests/run.sh` and then `bash tests/test_session_end.sh` and `bash tests/test_sync.sh` on their own. Run the
   suite twice in a row: the new bound, wait and background checks depend on timing, so a flaky pass is not a pass.

Use a `make_hub` hub for every check. Keep held-lock helpers as `sleep` background processes that are killed in cleanup.
A check that needs a start record writes it with `proc_start` from `bin/lib.sh` (or a fixed string for a reused pid).
Background markers and log lines are polled (up to 30 s), never fixed-sleep. Every test-owned stub writes its marker
with a `date +%s` and nothing else to stdout.

## Files touched

- `bin/lib.sh`: `_sync_lock_stale` rewritten to the owner rule (cases a, b, c); new `proc_start`, `sync_lock_grace` and
  `sync_hook_lock_wait`; `sync_lock_take` writes the start record and its comment changes. Shared with S2a, S2b, SP: keep
  the edit to the staleness test, the start record and the new functions. Do not touch the `hub.conf` sourcing block at
  `bin/lib.sh:47`.
- `bin/session-end`: header comment (the hook wait, the detached part and `--since` foreground); the hook wait choice;
  the detached job (env-var re-entry, new session, redirects); the `bg step failed:` log lines; the `--since` branch that
  runs both steps in the foreground.
- `bin/sync`: header, the `--auto` comment and the line 27 stale rule comment; no behaviour change.
- `tests/test_session_end.sh`: AC7 and AC8 (wait knob), AC9 (changed), AC10 (changed), AC14 (brain stub exits 0), AC19 to
  AC37.
- `tests/test_sync.sh`: the "over 2 hours old" comment (AC18 check unchanged), AC22 added after `sync_yes_busy_fails`,
  AC38 added after AC22.
- `.ade/context/auto-sync-and-monitors.md`: line 12 (the wait sentence) and line 15 (the staleness sentence), per the
  instruction above.
- `docs/stories/S1b-lock-owner-and-short-session-end.md`: this file. The Verification section is filled by QA only.

## Dependencies and shared contracts

- Depends on S1 (Done). Its lock path, log path, `--since` shape and AC numbers stay.
- Shared with S2b: the `session-end` argument shape is unchanged (`F [--since N]`). The detached job is re-entered by the
  environment variable `AGENT_SESSION_END_BG`, not by an option, so the parser S2b extends is untouched. The launcher
  uses `--since`, so it waits `AGENT_LOCK_WAIT`, not the hook knob. Record the variable in the context entry only if the
  Dev is asked to; it is internal.
- Shared with S2c: the lock is still held around the commit step, and is released before the detached part.
- Shared lock format: `<lock>/pid` (unchanged) and `<lock>/start` (new, `<pid> <start>`). Every lock holder reads both
  through `bin/lib.sh`, so `bin/sync` and `bin/session-end` agree.
- Environment knobs: `AGENT_HOOK_LOCK_WAIT` (new, default 5; hook path only) and `AGENT_LOCK_WAIT` (default 30; `--since`,
  `bin/sync --yes`).
- Plan reference: `docs/plans/2026-11-09-other-ai-cli-agents.md` "Session end" (S2b launcher) and "S1" (section lines
  399 to 410), which still describe the S1 lock rule. The plan is not edited by this story.

## Coding standards

- Bash 3.2 compatible (macOS `/bin/bash`): no associative arrays, no `mapfile`, no `${var,,}`.
- Use the existing helpers: `state_dir`, `hub_root`, `utc_now`, `sync_lock_path`, `sync_lock_wait`, `bin/journal`, and the
  new `proc_start`, `sync_hook_lock_wait`, `sync_lock_grace`.
- `ps -p` for liveness; `stat -f %m` for mtime (the macOS forms the file already uses); `LC_ALL=C ps -o lstart=` for the
  start time, so the string is the same in every locale.
- Never log a secret or the stderr of a detached step. The `bg step failed:` line holds only the step name and status.
- Keep the hook path quiet: nothing on stdout or stderr from the hook path, and nothing in the session-end log on
  success.

## Owner decisions carried in (2026-11-09, `.ade/session.md`)

1. Sync lock: an old lock is removed only when its owner process is gone, or its pid file is missing, unreadable or
   empty after a grace (10 s). The 120-minute rule is removed; a live-but-old lock is kept. Supersedes S1 AC9.
2. Session end: detaches `refresh_brain` and `auto_sync` in the background on the hook path, after the lock is released,
   and returns. The `--since` (launcher and manual) path stays in the foreground (reasons in Scope 3).
3. **Pid reuse (2026-11-09, answer to open question 1).** The lock records the owner's start time with its pid
   (`<lock>/start`). A live pid whose start time differs from the record counts as gone and its lock is removed and
   logged. The same pid with the same start time is the owner and is kept. A pid-only lock in the old format is judged by
   pid as before. The 10 s grace still applies to a lock with an unusable pid file.
4. **Hook wait (2026-11-09, answer to open question 2).** The hook path waits at most `AGENT_HOOK_LOCK_WAIT` (default 5 s)
   for a busy lock, then skips its commit and journals it as before. `--since` keeps `AGENT_LOCK_WAIT` and waits up to it
   (default 30 s); `bin/sync --yes` keeps `AGENT_LOCK_WAIT`.

## Notes (not blocking)

- The review notes on the empty pid file case and pid reuse were not found in the repo text available to the
  scrum-master (only the owner's decisions and the code). The handling above follows decisions 1 and 3 and the code.
  The Dev should check it against the review text if it is attached to the PR.

## Verification

Command: `bash tests/run.sh` (must print `ok    test_session_end.sh` and `ok    test_sync.sh`, and exit 0).

Real output recorded by the reviewer (2026-11-21, after the review fixes; `bash tests/run.sh` run twice in a row):

```
== run 1 06:50:34
exit 0
== run 2 07:11:52
exit 0
== done 07:34:24
```

Each run printed `ok` for all 28 test files, including `test_session_end.sh`, `test_sync.sh` and `test_report.sh`.
Quick review: 5 findings fixed (TZ-independent start record, test_report timing, AC28 session check, context entry), 1 rejected; see the plan's triage log.

