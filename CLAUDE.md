# ade-brain (working on the template itself)

This repo is a **template**. Running `bin/init` turns a copy into a hub and replaces this file with a rendered
`templates/hub/CLAUDE.md`. When you work on the template itself:

- Keep it client-neutral: no client, person, host or account names outside `tests/` fixtures (`tests/test_root.sh` checks).
- Personas carry `model:` (the suggested session model); `hub.conf` carries the install and model defaults.
- Hub rules live in `templates/hub/CLAUDE.md`; personas in `personas/<slug>.md` (front matter `title`, `folders`,
  `briefing_focus`; body uses `{{CLIENT}}` and `{{OWNER}}`).
- Every `bin/` script has a test in `tests/`; the verification command is `bash tests/run.sh` (docs/architecture.md).
- Never put a secret in the template; `hub.conf` holds names and locations only.

## ADE methodology

@.ade/rules.md

<!-- ade:bmad -->
## BMAD

- **BMAD v6** is how work is done in this project. For planning, stories, builds and
  reviews, use its skills in `.claude/skills/`, not ad-hoc steps: `bmad-prd`,
  `bmad-architecture` and `bmad-ux` to plan, `bmad-ticket` for stories, `bmad-build` to
  build one, `bmad-code-review` to review it. Unsure which applies: run `bmad`. Their
  work lives in `_bmad-output/`; where that differs from the project layout in this file,
  use the BMAD location. Done is not theirs to give: a story is Done only when the
  verification command passes, whatever state a ticket is in. The ADE rules in `.ade/rules.md` always
  win: a BMAD skill can **never override** the verification command, the Definition of
  Done, or anything in this file. Where they disagree, stop and surface the conflict.
<!-- /ade:bmad -->
