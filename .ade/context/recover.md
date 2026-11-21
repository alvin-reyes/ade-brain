# Crash recovery (`bin/recover`, story R1)

- **When:** at login (launchd `ai.agent-hub.<hub>.recover`, RunAtLoad, installed by `bin/schedule install`), at the
  start of every `bin/chat start` (before the session), and by hand. One run at a time: `<state dir>/recover.lock`
  (the sync-lock rules). `bin/recover --check` (shown by `bin/doctor`) prints one `OK|WARN  recover <check>  <detail>`
  row per check and changes nothing.
- **Output:** one line per repair, each also one journal line `recover: <line>` (folder `.`); with any repair a note
  `<state dir>/recover/<UTC>.<pid>.md` ("recovery note: <path>" printed last). Nothing found: `nothing to recover`, no
  journal line, no note. A second run right after the first finds nothing.
- **Never:** commits, resets, stashes or checks out anything; marks a ticket Done.
- **Checks and repairs:**
  - `orchestrator`: `<state dir>/chat/chat.pid` names no live channel session -> removed; the chat gets
    `restarted, <N> agent(s) running, <M> waiting` (N = `bin/sessions` rows, M = unanswered `bin/chat ask`s).
  - `agents`: a session entry (`<state dir>/sessions/*`, or `sessions-dead/*`, where `bin/sessions` now moves the
    entries it prunes) whose launcher is no live `-work.` process. Journaled `agent <name> died (<folder>)`; for role
    `builder` the ticket `<name>` is marked `blocked` with reason `agent died` (`node <cwd>/_bmad/ade-runtime.mjs tickets
    --project-root <cwd> mark <name> blocked --blocked "agent died"`); `bin/notify --from <folder> main "blocked: agent
    <name> died; restart: bin/work --continue [--role R] --name <name> <folder>"` (the C7 card shows it ⚠ blocked);
    uncommitted work in `<cwd>` kept and listed (diff stat and `git status --porcelain`). The entry is then removed.
  - `locks`: `<state dir>/chat/lock`, `chat/forward.lock`, `dispatch.lock` and the sync lock, removed only when stale
    by the S1b owner rule (`_sync_lock_stale` / `_sync_lock_reap` in `bin/lib.sh`); a live owner's lock is kept.
  - `event log`: `events.py repair` drops a torn last line under the log's lock and resets every cursor
    (`events-seen/*`, `chat/forward.cursor`) whose offset is past the end to the end.
  - `disk`: under `AGENT_DISK_MIN_MB` (default 200) MB free (`df -Pk`) for the hub or the state dir: one journal line
    and one chat alert, then quiet (`<state dir>/recover/disk-alert`) until there is space again.
  - `chat service` (`--check` only): `<state dir>/chat/gave-up` exists.
- **Chat messages** go through `bin/chat say`; when the channel is down the message is kept in
  `<state dir>/chat/pending/` and `bin/chat forward` sends it first next time (journal: `recover: chat unreachable: the
  message is kept`).
- **Restart a dead agent:** `bin/work --continue ...` passes `claude --continue` (the folder's last conversation).
- **Not covered here:** Linux/systemd units (no Linux layer yet, story V1); tmux (agents run in Terminal/ADE tabs, which
  are separate processes from any UI); `bin/sync` already keeps commits when a push fails and retries on its next run.
