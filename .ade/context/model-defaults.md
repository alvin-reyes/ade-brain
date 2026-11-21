# Model defaults (config keys and contracts)

ADE (the terminal) sets models when it opens a project; the hub's values are fallbacks. A Claude settings `env` value
replaces the shell's, so the hub never writes model variables into `.claude/settings.json`.

- `HUB_MODEL`, `HUB_EFFORT` (hub.conf, `bin/init --model/--effort`): session model and effort for `bin/work` and the
  persona agent. Default: the persona's `model:`, and the model's own effort.
- `HUB_AGENT_MODEL` (`--agent-model`, default `sonnet`): each folder agent's `model:` (`templates/agent.md`); `bin/work
  --agent-model [name=]M` overrides per session.
- `HUB_SUBAGENT_MODEL` (`--subagent-model`, default `sonnet`, empty means `sonnet`): fallback only. `bin/work`'s launcher
  runs `export CLAUDE_CODE_SUBAGENT_MODEL="${CLAUDE_CODE_SUBAGENT_MODEL:-<value>}"` before claude, where `<value>` is the inherited
  `CLAUDE_CODE_SUBAGENT_MODEL` (e.g. ADE's) if set, else `HUB_SUBAGENT_MODEL`, else `sonnet`. An Agent-tool `model` or
  a definition's `model:` still wins. `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` is never set. A hub-root session gets only
  what its environment (ADE) gives it.
- `HUB_BRIEFING_MODEL` (`--briefing-model`, default `haiku`): `bin/briefing`.
- BMAD (`_bmad/custom/`, from ade-method, story C1): `bmad-build` builds on the owner's builder model (default Opus 5.5)
  and scales review to risk: low none, medium the quick review on the subagent default (no model passed), high the
  thorough review on the builder's model. `bmad-code-review` has `review = "quick"` (thorough on request). ADRs 0003, 0005.

## Install and account of a focus session (`bin/work`, Anthropic path)

- The Claude command (`--claude`, `AGENT_CLAUDE`, `HUB_CLAUDE`, else `claude`): a bare name is resolved with `command -v`
  in the caller's environment and the absolute path goes into the launch command, so the new window's login shell cannot
  pick another install. An explicit path, or a name not found on the caller's `PATH`, is kept as given.
- The account: the launcher runs `export CLAUDE_CONFIG_DIR='<caller's value>'`, or `unset CLAUDE_CONFIG_DIR` when the
  caller has none, so a value the login shell sets cannot switch accounts. A wrapper that exports its own still wins.
- Provider sessions are unchanged: plain `claude`, their own `CLAUDE_CONFIG_DIR` (`.ade/context/providers.md`).

## Context and output limits (token use)

Measured on four hubs over 30 days (2026-11-18): 69% of context tokens were in calls already over 200k (sessions ran to
~965k on 1M-context models), and 63% of Bash output came from results over 5,000 characters. These keys cap both.

- `HUB_COMPACT_WINDOW` (`bin/init --compact-window N`, default `200000`; `0` = Claude's default): the window a session
  auto-compacts at. Focus sessions: the `bin/work` launcher runs
  `export CLAUDE_CODE_AUTO_COMPACT_WINDOW="${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-<value>}"`, so an inherited value (ADE's)
  wins. Hub root: `autoCompactWindow` in its `.claude/settings.json` (the environment variable outranks it). Claude Code
  takes 100000-1000000 and caps it at the model's window.
- `HUB_BASH_MAX_CHARS` (`--bash-max-chars N`, default `8000`; `0` = Claude's default of 30000): inline Bash output.
  Longer output goes to a file with a short preview, which Claude reads only as needed. Focus sessions: the launcher's
  `export BASH_MAX_OUTPUT_LENGTH="${BASH_MAX_OUTPUT_LENGTH:-<value>}"`. Hub root: `bashOutputMaxChars` in its settings.
- `HUB_ROOT_MODEL` (`--root-model M`, default `sonnet`; empty = none): `model` in the hub root's `.claude/settings.json`,
  written by `bin/init`, so the orchestrator session coordinates on Sonnet. A `--model` flag or `ANTHROPIC_MODEL` (ADE's)
  still wins; code is written on the builder model (`bmad-build`, default Opus 5.5; ADR 0005). Hubs made earlier: add `"model": "sonnet"` by hand.
- These are settings keys or launcher exports, never a settings `env` block (an env value would replace ADE's).

## A session on another Claude account

When a focus session's account (the dir its wrapper exports, else the caller's `CLAUDE_CONFIG_DIR`, else `~/.claude`)
is not the hub's (`HUB_CLAUDE_CONFIG_DIR`), `bin/work` links the hub's and the folder's memory into that account the way
`bin/setup` does (`link_memory` in `bin/lib.sh`: files in a plain memory folder there are copied in, never overwriting,
and the folder is kept as `memory.bak-<time>`), and says so in one line. `bin/setup --config-dir DIR` does the same for
hub-root sessions; `bin/doctor` names a shell account that lacks the link.

## The brain index

`bin/monitor` (every 30 minutes) ends with an incremental `bin/brain index`, quietly, so search stays current between
focus sessions; a failure never fails the monitor run.

Project context (story C4, ADR 0004): `bin/brain index` also reads the Markdown under `.ade/context/` and
`.ade/knowledge/` of every code checkout a folder's ACCESS.md lists (`repos_of` in `bin/lib.sh`), and nothing else in
the checkout. It only opens those files for reading; a missing or unreadable checkout or file is skipped. Results are
named `<folder>: <checkout dir name>/<path in checkout>`, e.g. `projects/demo: demo-code/.ade/context/decisions/0001-x.md`.
`bin/brain` passes the checkouts to `bin/brain.py` as `BRAIN_CHECKOUTS`, one `<folder><TAB><checkout>` line each.
