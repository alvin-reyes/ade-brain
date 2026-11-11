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
- BMAD (`_bmad/custom/`): `bmad-build` writes code on Opus (its implementation subagent passes `opus`); review lenses
  in `bmad-build` and `bmad-code-review` pass no model, so they run on the subagent default; `bmad-code-review` has
  `review = "quick"` (thorough on request). An "Opus review" request runs the lenses on `opus`. See ADR 0002.
