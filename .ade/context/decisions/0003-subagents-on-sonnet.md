# 0003: Subagents on the subagent default (Sonnet unless ADE says otherwise), code on Opus

- Status: Superseded in part by 0005 (code only by Opus). Accepted (owner, 11 Nov 2026; revised the same day so ADE sets the models)
- Context: token use was high. Most BMAD skills launch subagents without naming a model, so in an Opus session they
  all ran on Opus. bmad-build's reviewers matched the session model, and bmad-code-review ran 4–5 lenses per review.
  ADE (the terminal) sets models when it opens a project, and a Claude settings `env` value replaces the shell's, so
  a value written into the hub's settings would override ADE's.
- Decision: no settings file sets `CLAUDE_CODE_SUBAGENT_MODEL`. `bin/work` sets it at launch only when the session
  doesn't inherit one: the inherited value (ADE's) wins, else `HUB_SUBAGENT_MODEL` (`sonnet`). No force flag. BMAD
  review lenses pass no model, so they follow that default; bmad-code-review is quick by default. Code is still
  written only by Opus (bmad-build's explicit `opus`). Persona session models are unchanged.
- Consequences: planning, research and review subagents cost the subagent default's rates. Reviews are shallower
  unless "thorough" or "Opus review" is asked for; a quick review of a diff over 200 lines says so and offers a
  thorough run (lenses are chosen when the workflow is rendered, so it cannot switch on its own). A hub-root session
  not started by ADE has no subagent default, so its lenses run on the session model. Existing hubs need nothing
  re-rendered: `bin/work` reads `HUB_SUBAGENT_MODEL` at launch, and an absent key means `sonnet`.
