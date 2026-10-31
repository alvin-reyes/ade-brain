# ai-agent-hub-template

A template for an **AI technical persona that remembers your work**: a staff software engineer, DevOps/SRE, data
engineer, QA, security engineer, architect, tech lead, PM or fractional CTO, for one client. It runs on Claude Code.

The hub is a private repo of Bash and Markdown that holds the **context, state and history** of the work. Every
session starts with what is live, open and waiting; agents keep it up to date; the client's code stays in its own repos.

## Make a hub

```bash
# on GitHub: create a private repo from this template, then clone it
gh repo create my-acme-sre --private --template alvin-reyes/ai-agent-hub-template --clone
cd my-acme-sre
bin/init --list                                   # the personas
bin/init --persona devops-sre --client "Acme Corp" --owner "Sam Lee" \
  --repo acme/infra=~/code/infra --remote deploy@staging.acme.com:22 --remote-key ~/.ssh/acme \
  --staging-url https://staging.acme.com --secret grafana-token --briefing 08:00
bin/setup && bin/doctor
claude
```

Or locally, without GitHub: `bin/init ... --dest ~/Project/acme-sre` copies the template to a new folder first.

| `bin/init` option | Sets |
|---|---|
| `--persona <slug>` | the role (see `personas/`); `--list` shows them |
| `--client`, `--owner` | who the work is for, and who the agent works for (required) |
| `--name` | the hub name (default `<client>-<persona>`) |
| `--folders "projects/a ops/b"` | the work areas (default: the persona's) |
| `--repo owner/name[=checkout]` | code repos; the first folder gets the first repo for deep work |
| `--code-owner <org>` | the GitHub owner for repos named without one |
| `--remote user@host[:port]`, `--remote-key`, `--remote-dir` | the box `bin/remote` reaches over SSH |
| `--staging-url` | checked by `bin/doctor` |
| `--secret <name>` | secret **names** `bin/doctor` checks for in the Keychain (never values) |
| `--briefing HH:MM` | weekday morning-briefing time, this Mac's local time |
| `--claude <cmd>` | the Claude install to run: `claude`, or a wrapper such as `claude-personal` that sets its own `CLAUDE_CONFIG_DIR` |
| `--claude-config-dir <dir>` | that install's config dir (default: read from the wrapper, else `~/.claude`); memory and skills are linked there |
| `--model M`, `--effort E` | the default model and effort for sessions (`bin/work`) and the persona agent (default: the persona's) |
| `--agent-model M` | the folder agents' model (default `sonnet`) |
| `--briefing-model M` | the morning briefing's model (default `haiku`) |

## Personas

| Slug | Role | Default folders | Model |
|---|---|---|---|
| `data-engineer` | Data Engineer | projects/pipelines, projects/warehouse, projects/reporting, ops/data-quality | sonnet |
| `devops-sre` | DevOps / Site Reliability Engineer | ops/environments, ops/ci-cd, ops/monitoring, ops/security | sonnet |
| `engineering-manager` | Engineering Manager | projects/team, projects/delivery, projects/client | sonnet |
| `fractional-cto` | Fractional CTO | projects/strategy, projects/proposals, projects/vendors, projects/client | opus |
| `frontend-engineer` | Frontend Engineer | projects/web, projects/design-system, projects/client | sonnet |
| `ml-ai-engineer` | ML / AI Engineer | projects/models, projects/agents, projects/evals, projects/proposals | opus |
| `mobile-engineer` | Mobile Engineer | projects/ios, projects/android, projects/releases | sonnet |
| `qa-test-engineer` | QA / Test Engineer | projects/app, projects/test-plans, ops/environments | sonnet |
| `security-engineer` | Security Engineer | ops/security, ops/access, projects/app, projects/reviews | opus |
| `solutions-architect` | Solutions Architect | projects/architecture, projects/proposals, projects/client | opus |
| `staff-software-engineer` | Staff Software Engineer | projects/app, projects/proposals, projects/client, ops/environments | opus |
| `tech-lead` | Tech Lead | projects/app, projects/planning, projects/client | sonnet |
| `technical-product-manager` | Technical Product Manager | projects/roadmap, projects/specs, projects/client | sonnet |

Add a persona: copy one in `personas/`, keep the front matter (`title`, `folders`, `model`, `briefing_focus`) and the
`{{CLIENT}}`/`{{OWNER}}` placeholders, and write its habits.

## Models and Claude installs

Every hub pins one Claude install (`HUB_CLAUDE`) and its config dir (`HUB_CLAUDE_CONFIG_DIR`), so `bin/setup` links
memory and skills into the right place wherever you run it, and `bin/doctor` says when the link is missing. Defaults in
`hub.conf`, all overridable per run:

| Setting | Used by | Override |
|---|---|---|
| `HUB_MODEL`, `HUB_EFFORT` | deep-work sessions, the persona agent | `bin/work --model M --effort E` |
| `HUB_AGENT_MODEL` | folder agents (`.claude/agents/*.md`) | `bin/work --agent-model [name=]M`, or edit the agent file |
| `HUB_BRIEFING_MODEL` | `bin/briefing` | `AGENT_BRIEFING_MODEL=M bin/briefing` |
| `HUB_CLAUDE` | every session the hub starts | `bin/work --claude CMD`, `AGENT_CLAUDE=CMD` |

Other providers (OpenRouter, Ollama, a second account) work through a wrapper command passed as `--claude`.

## What a hub has

- **The persona** in `CLAUDE.md` and `.claude/agents/<persona>.md`, with shared rules: verified not vibed, secrets never
  printed, deploys and messages only on the owner's word, client decisions recorded with who and when.
- **One folder per work area** (`projects/<name>`, `ops/<name>`): `CLAUDE.md`, `ACCESS.md` (names and locations, never
  values), `STATE.md` (Live, Staged, Open, Waiting on, Next session starts with), `memory/`, and a named agent.
- **The journal** (`journal/<UTC date>.md`): the shared timeline every agent and hook appends to.
- **Hooks**: SessionStart prints the state, UserPromptSubmit reports other terminals' changes, and in deep work Stop asks
  for a STATE update after new commits and SessionEnd journals the commits.
- **Deep work**: `bin/work <folder>` opens a Terminal in the folder's repo checkout with its context and hooks.
- **The morning briefing**: `bin/briefing` (Haiku, read-only) and `bin/schedule install` for weekdays.
- **BMAD v6** skills in `.claude/skills/` for PRDs, specs, stories, builds and reviews, under the ADE rules (`.ade/rules.md`).
- **Access tools**: `bin/remote` (SSH to the box), `bin/secret` (macOS Keychain), `bin/doctor` (what this Mac can reach).

Does a checkout know my work? Yes, as far as the hub's files go: STATE.md, memory, the journal and ACCESS.md are
committed, so a fresh clone (plus `bin/setup`) starts with full context. Secrets, SSH keys and files outside the repo
(downloads, PDFs) are not in it; `bin/doctor` says what is missing on a new Mac.

## Tests

`bash tests/run.sh` (macOS, Bash 3.2+). Every `bin/` script has a test run against a throwaway copy with stubbed tools.
