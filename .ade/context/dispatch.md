# Dispatch (config key and contract, story C3)

- `bin/dispatch [--approve <ref>] <folder>` reads `node <checkout>/_bmad/ade-runtime.mjs tickets --project-root <checkout> next`
  (the folder's one Code repo checkout, `repos_of`) and starts ready tickets with
  `bin/work --role builder --name <name> --prompt "bmad-build <ref>" <folder>`.
- `HUB_DISPATCH_MAX` (hub.conf or the environment): the most builder sessions at once, **hub-wide** (every folder). Unset = 1;
  above 2 = 2; not a whole number = exit 2. Used slots = the running `bin/sessions` rows with ROLE `builder` in any folder,
  plus this folder's running ticket sessions of another role, plus the start markers of the last 120 s whose session is
  not listed yet.
- Running = a `bin/sessions` row, or a marker younger than 120 s, with the ticket's name **and** this folder. bin/work
  registers a session as `$(state_dir)/sessions/<--name or folder name>.<launcher pid>` with `name=` the same.
- State: `$(state_dir)/dispatch.lock` (one run at a time; `pid` inside; a held lock refuses with exit 1, a lock whose pid
  no longer runs is taken over) and `$(state_dir)/dispatch/<name>` (`<epoch> <folder>`, written after each start; registration
  is asynchronous, so the marker stops a second run starting the same ticket or overfilling the slots).
- Only `ready_to_start` rows are started; only risk `low` or `medium` with no `hitl` (nor a `hitl` drift). The risk is the
  higher of the row's (the leaf file's) and its `tickets.toml` entry's, read via `tickets find <ref>` -> `story_file` ->
  the sibling `tickets.toml` `[[entry]]` with the row's `id`; a disagreement counts as the higher, an unset entry risk next
  to a set file risk counts as unset (waits), and a risk that cannot be checked (find failing, no Python `tomllib`) waits.
  Anything else prints `waiting for the owner: <ref> (<why>); ...` and starts only by `--approve <ref>`.
- `--approve <ref>`: the ticket must be ready, not running, with a free slot; then stdin and stdout must be TTYs and
  `/dev/tty` must open, and the owner types the ref back at `/dev/tty` (120 s). Journal: `dispatch: started <ref> (approved
  at the terminal)`.
- The real gate is Claude Code's permission prompt: `templates/folder-settings.json` (every folder session) and the hub
  root `.claude/settings.json` carry `permissions.ask` for `Bash(*bin/dispatch --approve*)`, `Bash(*ade dispatch --approve*)`
  and `Bash(script *)`.
- **Residual risk:** this is a speed bump, not a security boundary. An agent that gets a pseudo-terminal another way (a
  tool other than `script`, e.g. python's `pty`, `expect`), or that calls `bin/work --role builder` directly, or edits both the
  leaf file and `tickets.toml` to lower a risk, still starts a high-risk ticket. The owner's protection is the permission
  prompt in their own session and reading the journal.
- A ref must match `^[A-Za-z0-9][A-Za-z0-9._/-]*$` (whole string; else skipped, never started); the session name is the ref
  with every character outside `A-Za-z0-9._-` turned into `-` (`demo/01-a.md` -> `demo-01-a.md`). `bin/work --name` takes
  `^[A-Za-z0-9][A-Za-z0-9._-]*$` only, so a name can never be read as a flag.
- Journal (bin/journal): one line per run, `dispatch: started <refs|none>; waiting for the owner: <refs|none>` (plus
  `; bin/work failed for <ref>`), skipped when nothing started, nothing failed and the line equals the folder's last
  `dispatch` line in today's journal.
- Exit: 0 done; 1 refused (no or several Code repos, no BMAD, no node, `tickets next` failing or unreadable, bin/sessions
  failing, the lock held, `--approve` of a ticket that is not ready, running or has no free slot, or not confirmed at a
  terminal) or a bin/work start failed (no more starts that run); 2 usage or unknown folder.

## Requirement
Python 3.11 or later (`tomllib`) to compare a ticket's file risk with its entry risk. With an older python3 every ticket that has a leaf file waits for the owner (fail-safe). macOS ships 3.9 at /usr/bin/python3; Ubuntu 24.04 ships 3.12.
