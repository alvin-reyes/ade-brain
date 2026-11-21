# The hub commands `ade` calls (story H1)

The hub side of ade-cli's `.ade/context/hub-interface.md` (`ade setup`, A5; `ade ui` and `ade dash`, A6). `ade` exports
`HUB`, runs `<hub>/bin/<script>` and returns its exit code unchanged. Change a line here only together with ade-cli.

## `bin/agent --live-test <provider[:model]> [--dir <folder>]`
- Task: stdin's first line (at most 1 KB); empty or a terminal = `Reply with the word READY and nothing else.` No
  folder context. Model default `haiku` (a slot alias; an `anthropic` model must pass `anthropic_model_ok`).
- Folder: `--dir` must be absolute, exist, not be inside a git work tree and not be inside the hub (else exit 2); the
  caller removes it. Without `--dir` a `mktemp -d` folder (`agent-live.*` in `TMPDIR`) is made and removed on exit.
- Same run as `bin/agent --role` (`agent.py`: allowlisted environment, own process group, `AGENT_TIMEOUT`, the same
  read-only Claude Code flags, provider settings and config dir), journaled as `role=live-test folder=-`. Every
  `candidate_refusal` check applies (`read` mode: the key is read once) except `HUB_PROVIDERS_ALLOWED`.
- Unset before the run (and never in the engine's allowlisted environment): `ANTHROPIC_*`, `CLAUDE_CODE_OAUTH_TOKEN`,
  `CLAUDE_CODE_USE_*`, `*_API_KEY`, `*_AUTH_TOKEN`, `TELEGRAM_BOT_TOKEN`.
- Output: the engine's stdout (first 4 KB, keys hidden). Exit 0 only when a whole line is `READY` (spaces, tabs and CR
  ignored). Exit 1 otherwise, the last line `agent: live test of <p>:<m> failed: <why>; details: <err file>`, where
  `<why>` is a refusal, `no READY line; it said: <last line>` or the engine failure plus its last line (keys hidden).
  `gemini` (no engine until E1) and `muse` (no provider row) exit 1. Exit 2: usage, a bad id or model, a bad folder.
- Hidden (`redact` in `bin/lib.sh`, the same patterns in `agent.py`): `[0-9]{6,12}:[A-Za-z0-9_-]{30,}` (bot token),
  `(sk|pk|ak|key)-[A-Za-z0-9_-]{8,}`, any `[A-Za-z0-9_-]{32,}` run.

## `bin/keys` and the Anthropic API key
- `anthropic` is a `key_tools` entry: Keychain name `anthropic-api-key`, `bin/keys set anthropic` (stdin or hidden
  prompt), `bin/keys forget anthropic`; the list prints `anthropic   stored|missing   anthropic-api-key` like every tool
  (`ade` matches `^<tool> +stored`).
- A stored key is used by `bin/agent` (role runs and live tests) only through a 0600 `--settings` file holding
  `apiKeyHelper` = `HUB=<hub> AGENT_KEYCHAIN_SERVICE=<service> <hub>/bin/secret anthropic-api-key`
  (`anthropic_settings_write`), never an environment variable. Without one: the Claude login, no settings file.
  `bin/work`, `bin/chat start` and `ade claude` still use the Claude login.

## `bin/chat logs [-n N]` and `bin/chat test [channel]`
- `logs`: the last N lines (1 to 10000, default 50; else exit 2) of `<state dir>/logs/chat.log` through `redact`;
  no log = nothing, exit 0.
- `test`: channel default `telegram` (unknown exit 2). Exit 1, nothing sent, while the orchestrator runs (its plugin
  reads the bot's updates), without a stored token, a token not shaped `<digits>:<30+ chars>`, or an `access.json`
  whose `allowFrom` is not exactly one id. Then: `getUpdates offset=-1` (the start offset), one `sendMessage` to that
  id, and `getUpdates` long polls (at most 20 s each) until a message from that chat arrives (exit 0, "reply received")
  or `AGENT_CHAT_TEST_TIMEOUT` (default 120, 1 to 600) passes (exit 1, "no reply"). Updates read meanwhile are
  confirmed (consumed). A failed send exits 1 with the API's description. The token goes to `curl -K -` in a config
  on stdin, written by the printf builtin: never an argument, the environment or the output.

## `bin/inbox --count [main|<folder>|<name>]`
- Target: `main` (default), `projects/<n>` or `ops/<n>`, a `bin/sessions` NAME (the registry entry's `folder=`), else a
  bare folder name naming exactly one folder; otherwise exit 2. Prints one number, exit 0 (1 when the log is unusable).
- Counts the events `for_me` (events.md routing) after `<state dir>/events-read/<main|folder>` (`<inode> <offset>`),
  which every delivery (`bin/inbox` hook, `bin/changes`) writes for its folder; with none, what that folder's first
  delivery would show (its notes of the last 24 h). Reads no stdin, writes nothing.

## `bin/dispatch --list [folder]`
- One `<state><TAB><ref><TAB><folder>` line per ticket, in `tickets next` order: `ready` (ready_to_start, low or medium
  risk, no hitl: starts when a slot is free), `waiting` (ready_to_start needing the owner: high, unset or unverifiable
  risk, or hitl), `running` (a ready_to_start or in_progress ticket whose session or recent start marker runs).
  Refine, blocked and idle in-progress tickets are not listed.
- Every folder by default (one without exactly one BMAD checkout is skipped); a named folder without one exits 1, an
  unknown folder 2. `tickets next` or `bin/sessions` failing exits 1. No lock, no `bin/work`, no marker removed or
  made, no journal line.
