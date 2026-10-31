# ai-agent-hub-template (working on the template itself)

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
