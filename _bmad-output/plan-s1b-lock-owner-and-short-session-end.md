---
title: 'S1b: sync lock owner rule and a short session end'
type: 'feature'
ticket: 'S1b-lock-owner-and-short-session-end'
created: '2026-11-21'
status: 'done'
baseline_revision: 'ba44fd59934192542d3f3f6cedc09790ca7d5097'
route: 'full'
route_source: 'auto'
risk: 'medium'
review: 'quick'
review_source: 'pinned'
lenses_ran: [quick]
review_loop_iteration: 0
context:
  - '{project-root}/docs/stories/S1b-lock-owner-and-short-session-end.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The sync lock treats any lock over 120 minutes old as stale, so a live long-running owner can lose its lock; and the SessionEnd hook runs `bin/brain index` (up to 120 s) in the foreground and waits up to 30 s on a busy lock, which keeps Claude Code's session end hanging.

**Approach:** Implement story S1b exactly as written in `docs/stories/S1b-lock-owner-and-short-session-end.md` (owner decisions 1-4 of 2026-11-09): owner rule with a `<lock>/start` record (pid + `ps lstart`) and a 10 s grace for pid-less locks; a 5 s hook-path lock wait (`AGENT_HOOK_LOCK_WAIT`); brain index then sync run detached in their own session on the hook path, foreground with `--since`; failures logged as `bg step failed: <step> exit <n>`.

## Boundaries & Constraints

**Always:** Bash 3.2; `ps -p` for liveness (not `kill -0`); `LC_ALL=C ps -o lstart=` for start time; `stat -f %m` for mtime; start record written before the pid file; every detached child has stdin `/dev/null` and stdout/stderr to `$LOG` (else `tests/run.sh` hangs); hook path prints nothing and logs nothing on success; exit codes unchanged.

**Never:** a new command-line option (re-entry is `AGENT_SESSION_END_BG=1`); changes to `_sync_lock_reap`'s guard/inode logic, `sync_lock_release`, what is committed, `bin/sync` behaviour, `bin/changes`, `bin/brain`, the `hub.conf` block in `bin/lib.sh`; an override for the 10 s grace; stderr of a step or any secret in the log.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Dead owner | pid file names no process | lock removed, `removed stale lock` | commit proceeds |
| Pid reused | live pid, start record same pid, different start | removed, logged | commit proceeds |
| Live owner, old | live pid, matching start or no record, dated 2020 | kept | busy: journal line, exit 0 |
| Rewritten pid | record names A, pid file names live B | judged by B alone, kept | — |
| Pid-less | pid file missing/empty/`abc` | kept under 10 s old, removed when older | — |
| Hook, slow steps | brain and sync stubs sleep 8 s | pipeline returns < 5 s, lock gone; markers appear later in order | step failure → `bg step failed:` line |
| `--since` | any | lock wait `AGENT_LOCK_WAIT`; steps foreground, done on return | same log format |

</frozen-after-approval>

## Code Map

- `bin/lib.sh:288-331` -- `sync_lock_wait`, `sync_lock_take` (writes `$k/pid` at line 20 of the block), `_sync_lock_stale` (the `kill -0` / `find -mmin +120` test to replace), `_sync_lock_reap` (keep), `sync_lock_release` (keep). Add `proc_start`, `sync_lock_grace`, `sync_hook_lock_wait` here.
- `bin/session-end` -- header lines 2-11; `refresh_brain` (line 80, currently swallows status) and `auto_sync` (lines 82-87, currently `nohup ... &`) must return real statuses and run in-line inside the job; lock take at line 95 uses `sync_lock_wait`; lines 106-109 run the follow-on steps. Re-entry check `AGENT_SESSION_END_BG=1` goes before the argument loop (line 18); `$LOG`/`log()` already exist.
- `bin/sync:3-4,27,38` -- comments only.
- `tests/test_session_end.sh` -- `setup`, `hold_lock`, `hook`, `run_held`, `KIDS` cleanup to reuse; checks AC7 (line 78), AC8 (85), AC9 (95), AC10 (103), AC14 (113) change; new checks AC19-AC37 appended before `echo ok`.
- `tests/test_sync.sh:64` comment ("over 2 hours old", line ~269 in file); AC22 and AC38 after `sync_yes_busy_fails` (second hub section, `$sp` live sleep, `AGENT_LOCK_WAIT=3`).
- `tests/helpers.sh` -- `make_hub` sets `AGENT_AUTO_SYNC=0`, temp `AGENT_SYNC_LOG`/`AGENT_SYNC_LOCK`.
- `.ade/context/auto-sync-and-monitors.md` -- the `AGENT_LOCK_WAIT` sentence and the "over 120 minutes old" sentence only.

## Tasks & Acceptance

**Execution:**
- [ ] `tests/test_session_end.sh`, `tests/test_sync.sh` -- write/modify checks AC7-AC10, AC14, AC19-AC38 per the story's table and TDD order; run and confirm each red for the stated reason (guards green) -- tests are the contract.
- [ ] `bin/lib.sh` -- `proc_start`, start record in `sync_lock_take`, `_sync_lock_stale` cases a/b/c, `sync_lock_grace` (10), `sync_hook_lock_wait` (`${AGENT_HOOK_LOCK_WAIT:-5}`), comment -- owner rule.
- [ ] `bin/session-end` -- wait choice by `--since`; detached job via `python3` `os.setsid()` (nohup fallback commented) re-entering with `AGENT_SESSION_END_BG=1`; job runs brain then sync in order, logs failures; `--since` runs both in foreground; header comment -- short hook.
- [ ] `bin/sync`, `tests/test_sync.sh`, `.ade/context/auto-sync-and-monitors.md` -- comment and context wording to the new rule.

**Acceptance Criteria:**
- Given the story's AC1-AC38, when `bash tests/run.sh` runs twice in a row, then every test file prints `ok` both times and exit is 0.

## Implementation Notes

## Plan Change Log

## Review Triage Log

Pass 1 (quick lens): high 1, medium 2, low 2, false 0, maybe-false 0, rejected 1.
| # | Finding | Verdict | Route | Evidence |
|---|---|---|---|---|
| 1 | `proc_start` uses local time; TZ mismatch makes case b steal a live lock | high | patch | `TZ=UTC` vs `TZ=America/Toronto` give different lstart for one pid; fix: fixed TZ=UTC + test |
| 2 | test_report.sh positive polls 3 s, negative checks no longer prove "off" | medium | patch | sync now waits for the detached brain index; owner approved editing this file |
| 3 | AC28 check compares pgid, not session | medium | patch | `timeout` can give a new pgid without setsid; compare session ids |
| 4 | context entry for session-end log not updated (new `bg step failed:` contract) | low | patch | DoD 3.4 requires recording the contract; overrides the story's "nothing else changes" |
| 5 | staleness sentence not re-wrapped | low | patch | direct correction |
| 6 | hook path creates an empty session-end log on success | low | rejected | the story requires the detached job's stdout/stderr to go to $LOG; an empty file logs nothing |

## Verification

**Commands:**
- `bash tests/run.sh` (twice) -- expected: all `ok`, exit 0
- `bash tests/test_session_end.sh && bash tests/test_sync.sh` -- expected: `ok` each
