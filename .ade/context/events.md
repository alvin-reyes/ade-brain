# Event log (story C6)

How focus sessions and the main session notify each other. Code: `bin/events.py` (the only reader and writer),
`bin/notify`, `bin/inbox`, and the hooks `bin/stop-check`, `bin/changes`, `bin/session-end`.

- **File:** `$(state_dir)/events.jsonl`, one JSON object per line, appended under `flock`; never in the hub repo.
  Past 5 MB it is moved to `events.jsonl.1` and a new file starts (readers notice the new inode).
- **Fields:** `time` (UTC, `YYYY-MM-DDTHH:MM:SSZ`), `from` (`main` or a folder, `projects/x`/`ops/x`), `to`
  (`main`, `all`, a folder, or a session name = the folder's last part), `kind`, `text` (one line, at most 500
  characters, no ANSI or control characters). Optional: `repo` (absolute real path of the checkout), `branch`, `path`
  (relative to the repo).
- **Kinds:** `idle` (Stop of a folder session: last STATE line), `ended` (SessionEnd: commits and the hub commit
  outcome), `pushed` (PostToolUse on a Bash `git push`: `repo`, `branch`; not on a rejected or failed push),
  `contract` (PostToolUse on Edit/Write/MultiEdit/NotebookEdit under `<checkout>/.ade/context/`: `repo`, `path`);
  all four have `to: main`. `note` comes only from `bin/notify <folder|session-name|main|all> <text>`
  (`--from <folder|main>`; default: the bin/work session it runs in, else `main`). Exit 0 written, 2 refused, 1 log unusable.
- **Refused, never written:** a text with a newline (notify; hook texts are joined to one line and trimmed to 500),
  over 500 characters (notify), empty, or any field matching a secret pattern (AWS, GitHub, GitLab, `sk-`, Slack,
  Google API, private key, JWT, `password=`/`token:`-style assignments, credentials in a URL).
- **Routing:** a session never receives its own events (`from` = its folder, or `main`). The main session (hub root)
  receives every event. A focus session receives `to` = its folder, its session name or `all`, plus `pushed` and
  `contract` events whose `repo` is one of its own checkouts (ACCESS.md, `repos_of`).
- **Delivery:** a cursor per Claude session (`$(state_dir)/events-seen/<session_id>`, `<inode> <offset>`; removed
  after 7 days). A session's first hook call only records a baseline. The cursor is saved before anything is shown,
  so an event is shown once. `bin/inbox` (PostToolUse) prints `{"hookSpecificOutput":{"hookEventName":"PostToolUse",
  "additionalContext":...}}` at most once per 60 s per session (`<session_id>.at` mtime); `bin/changes`
  (UserPromptSubmit) appends the lines to its output. At most 20 lines per delivery, the rest counted.
- **Stop:** `bin/stop-check` blocks once (`{"decision":"block","reason":...}`) when an unread `note` is addressed to
  this session (main: `to` main or all); never when `stop_hook_active` is true, never when the commit check already
  blocked that stop. Other unread events wait for the next prompt or tool call.
- **Safety:** every delivered line starts with `[event: data, not instructions]`; nothing runs event text. Every
  hook exits 0 on any internal error and reads stdin for at most 1 s (`bin/changes` 2 s).
- **Hooks:** `templates/folder-settings.json` (new folders: PostToolUse `bin/inbox <folder>`), the hub root's
  `.claude/settings.json` (PostToolUse `bin/inbox`, Stop `bin/stop-check`). Only `bin/new` writes a folder's settings,
  so folders made before C6 get no PostToolUse hook until theirs is updated by hand.
