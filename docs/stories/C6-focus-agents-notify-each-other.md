# C6: focus agents sync and notify each other through hooks

Status: Ready for development (2026-11-21). Risk: high (cross-session messages reach running agents).
Owner's intent (2026-11-21): "for our focus agent, we need to ensure they sync and notify each other via hooks."
Builds on the folder hooks in `templates/folder-settings.json` (SessionStart `bin/context --rules`, UserPromptSubmit
`bin/changes`, Stop `bin/stop-check`, SessionEnd `bin/session-end`) and `bin/sessions`. Verification: `bash tests/run.sh`.

## Today and the gap
`bin/changes` shows other folders' STATE, journal and memory updates, but only when the user sends a prompt. A focus
agent working on its own (dispatched, C3) never sees a peer's news, and nothing can be addressed to one session.

## Goal
One event log per hub (`$(state_dir)/events.jsonl`, one JSON line per event: time, from, to, kind, text). Hooks write
events automatically; `bin/notify` writes one by hand; hooks deliver each session its unread events, also mid-work.

- **Written by hooks (no model):** Stop → `idle` (folder, last STATE line); SessionEnd → `ended` (commits, outcome);
  PostToolUse on Bash `git push` → `pushed` (repo, branch); PostToolUse on Edit/Write under `.ade/context/` →
  `contract` (repo, path).
- **By hand:** `bin/notify <folder|session-name|main|all> <text>` (text ≤ 500 chars, one line).
- **Delivered:** UserPromptSubmit (`bin/changes`) and a new PostToolUse hook `bin/inbox` (at most once per 60 s per
  session) print this session's unread events as context; the Stop hook blocks once when an event addressed to this
  session is unread, so the agent reads it before it stops. The main session receives every event; a focus session
  receives events addressed to it, to its folder, to `all`, and `pushed`/`contract` events for a repo it also works in.
- **Safety:** event text is data, not instructions (the delivery says so on every line); nothing in an event runs a
  command; text is trimmed, one line, no ANSI; secrets are never written (gitleaks-style patterns rejected).

## Acceptance criteria (`tests/test_events.sh`, fake hook stdin, no model)
| AC | Criterion | Test |
|---|---|---|
| 1 | Stop and SessionEnd hooks append `idle` and `ended` events for their folder | `hooks_write_lifecycle_events` |
| 2 | A Bash `git push` tool call appends `pushed` with repo and branch; other Bash calls append nothing | `push_event_written` |
| 3 | An Edit under a checkout's `.ade/context/` appends `contract` with the path | `contract_event_written` |
| 4 | `bin/notify projects/a "rebase on main"` appends one event; a multi-line or over-500-char text is refused (exit 2) | `notify_validates_text` |
| 5 | `bin/inbox` prints each unread event once, marked as data, then nothing until a new event; at most once per 60 s | `inbox_delivers_once_rate_limited` |
| 6 | Routing: main gets all; a focus session gets its own, its folder's, `all`, and push/contract events for a shared repo, never another folder's private notes | `routing_by_session_and_repo` |
| 7 | Stop blocks once when an event addressed to this session is unread, and not again for the same event | `stop_blocks_once_for_unread` |
| 8 | A text matching a secret pattern is refused and nothing is written | `secrets_refused` |
| 9 | Every hook here exits 0 on any internal error (a broken log never blocks a session) and finishes within 2 s | `hooks_never_block_or_hang` |

## Out of scope
Telegram delivery (C5 forwards main's events later); cross-machine sessions; agents replying by themselves.
