# ai-agent-hub-template

A template for an **AI technical persona that remembers your work**: a staff software engineer, DevOps/SRE, data
engineer, QA, security engineer, architect, tech lead, PM or fractional CTO, for one client. It runs on Claude Code.

The hub is a private repo of Bash and Markdown that holds the **context, state and history** of the work. Every
session starts with what is live, open and waiting; agents keep it up to date; the client's code stays in its own repos.

**Guide:** [`docs/index.html`](docs/index.html) walks through making a hub, the daily flow, hooks, the brain, auto sync,
monitors and every setting, with flow diagrams.

## Make a hub

```bash
# on GitHub: create a private repo from this template, then clone it
gh repo create my-acme-sre --private --template alvin-reyes/ai-agent-hub-template --clone
cd my-acme-sre
bin/init --list                                   # the personas
bin/init --persona devops-sre --client "Acme Corp" --owner "Sam Lee" \
  --repo acme/infra=~/code/infra --remote deploy@staging.acme.com:22 --remote-key ~/.ssh/acme \
  --staging-url https://staging.acme.com --secret grafana-token --briefing 08:00
git add -A && git commit -m "Initialize the hub" && git push -u origin main   # once, by hand
bin/setup && bin/doctor
claude
```

Commit `hub.conf` by hand: `bin/init` commits nothing, and `bin/sync` leaves `hub.conf` out. Without it, a fresh clone
falls back to the folder name for the hub name (a different state folder, launchd labels and Keychain service) and has
no secret names to check. `push -u` also sets the upstream auto sync needs. Commit it again whenever you edit it.

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
| `--brain-path <path>` | extra folders, files or globs the brain indexes (e.g. `~/client/docs`, `'~/client/*.md'`), repeatable |
| `--embed-model M`, `--ollama-url URL` | the local embedding model (default `nomic-embed-text`) and Ollama address |
| `--auto-sync on\|off` | `HUB_AUTO_SYNC`: push the hub every 30 minutes and at each focus session end (default `on`) |

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

## The brain: searchable memory (SQLite + vectors)

`bin/brain` keeps every Markdown section of the hub (STATE, memory, journal, notes, docs, plus `HUB_BRAIN_PATHS`) in
one SQLite file, `.local/brain.db` (gitignored, one per hub, so clients never mix). Search ranks two signals together:
SQLite FTS5 keywords (names, numbers, IDs) and vectors from a **local Ollama** embedding model (meaning). Nothing leaves
the Mac; no Python packages; without Ollama it still works, keyword only.

```bash
ollama pull nomic-embed-text        # once per Mac
bin/brain index                     # incremental; session end runs it too; --full rebuilds
bin/brain search "what did the client decide about SMS"   # file:line, heading, snippet; --json, -n N
bin/brain status                    # sections, embedded, stale files
```

Files stay the source of truth: agents write STATE, memory and notes as before; the index is rebuilt from them. Sections
that look like they hold a secret are never indexed. `bin/doctor` checks the index is fresh and the model is pulled.

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

## Providers behind Claude Code

A focus session can run Claude Code against DeepSeek instead of Anthropic. The CLI stays Claude Code, so hooks,
`--agents` and session end work as before; only the endpoint and models change. Rows live in `bin/lib.sh`
(contract: `.ade/context/providers.md`).

- **Choose it in `hub.conf` only:** `HUB_PROVIDERS_ALLOWED="anthropic deepseek"` (default `anthropic`) and, for every
  session, `HUB_PROVIDER=deepseek`; or one session with `bin/work --provider deepseek <folder>`. Both are ignored when
  set in the environment.
- **Owner's own hubs only.** DeepSeek's terms allow training on API data and store it in the People's Republic of
  China, so it is refused unless `hub.conf` has `HUB_OWNED_BY_OWNER=1` (never set it in a client hub). `bin/doctor`
  flags a client hub whose allowlist lists deepseek. See ADR 0002.
- **The key:** `bin/secret --set deepseek-api-key`. `bin/doctor` shows whether it is stored, never its value. With no
  key, `bin/work` stops before Claude Code starts.
- **Exposure (credential option 1):** the key is read by Claude Code's `apiKeyHelper` (`bin/secret deepseek-api-key`)
  only, so it is never in the environment, argv or a file; hooks and tool commands cannot see it.
- **Models:** `--model` is a slot alias (`opus`, `sonnet`, `haiku`) or a row id (`deepseek-flash`, `deepseek-v4-pro`);
  `HUB_DEEPSEEK_MODEL` and `HUB_DEEPSEEK_SMALL_MODEL` change the defaults. `HUB_MODEL` and `HUB_AGENT_MODEL` are not
  used (they may be Anthropic ids). There is no base URL override.
- **Remote Control is off** for a provider session (it needs a claude.ai login), and `--resume`/`--continue` are
  refused: resuming would send an earlier session's history to the new provider.
- **Wrappers:** a provider session needs plain `claude`; `--claude`, `HUB_CLAUDE` or `AGENT_CLAUDE` naming anything else
  is refused.
- **Own config dir:** the session runs with `CLAUDE_CONFIG_DIR=.local/providers/deepseek`, so `/model` cannot change
  your Anthropic default. Claude Code's first-run prompts may show once there.
- **Data sharing:** everything the session reads goes to DeepSeek (code, notes, tool output). That is the owner's
  decision per hub, recorded in ADR 0002; do not use it for client work.
- GLM is disabled until it passes the same checks as DeepSeek. Meta is not offered.

## What a hub has

- **The persona** in `CLAUDE.md` and `.claude/agents/<persona>.md`, with shared rules: verified not vibed, secrets never
  printed, deploys and messages only on the owner's word, client decisions recorded with who and when.
- **One folder per work area** (`projects/<name>`, `ops/<name>`): `CLAUDE.md`, `ACCESS.md` (names and locations, never
  values), `STATE.md` (Live, Staged, Open, Waiting on, Next session starts with), `memory/`, and a named agent.
- **The journal** (`journal/<UTC date>.md`): the shared timeline every agent and hook appends to.
- **Hooks**: SessionStart prints the state; UserPromptSubmit, in every terminal (hub root and deep work), reports what
  other terminals changed since the last prompt (STATE.md updates, new journal entries with their text, new or updated
  memory files with their description); in deep work Stop asks for a STATE update after new commits, and SessionEnd
  journals the commits, commits the folder and starts `bin/sync --auto`, which pushes.
- **Deep work**: `bin/work <folder>` opens a Terminal in the folder's repo checkout with its context and hooks (a folder with no repo, such as an ops watcher, opens in the hub folder itself). `--prompt "<task>"` starts that session with its first message. Every session starts with Remote Control on, named after the folder, so you can follow it from your phone; `--no-remote` turns that off (use it with an API-key wrapper such as an OpenRouter or Ollama one: Remote Control needs a claude.ai login).
- **Scheduled jobs** (`bin/schedule install`, launchd): the weekday morning briefing (`bin/briefing`, Haiku, read-only);
  `bin/monitor` every 30 minutes; and `bin/sync --auto` every 30 minutes.
- **Auto sync**: `bin/sync --auto` commits and pushes the hub's files unattended: one run at a time, skipped while git
  is busy, refused without gitleaks or without the git hooks (`bin/setup`), every commit to push scanned first, one
  rebase retry, never a force push. One line per run in `~/.agent-hub/<name>/logs/sync.log`. Off: `HUB_AUTO_SYNC=0`
  in `hub.conf` (or `bin/init --auto-sync off`), then `bin/schedule install` again.
  `bin/sync --yes` and the session-end commit share the same lock (`~/.agent-hub/<name>/sync.lock`) and wait at least
  `AGENT_LOCK_WAIT` seconds (default 30) for it; `bin/sync --yes` now exits 1 (`another sync is running`) when the lock
  stays busy. `bin/session-end <folder> --since <epoch>` (run by hand or a launcher) logs one line per run to
  `~/.agent-hub/<name>/logs/session-end.log` (`AGENT_SESSION_END_LOG` overrides it).
- **Monitors**: any executable `projects/<x>/monitors.d/*.sh` or `ops/<x>/monitors.d/*.sh`. Each is read-only; its first
  output line is the status (a leading timestamp such as `Fri 10:05 UTC |` is ignored), and lines starting with `ALERT`
  alert. `bin/monitor` journals a status change and each new ALERT once, and shows a notification for an ALERT. Under
  launchd a monitor gets the plist's PATH only (`~/.local/bin`, Homebrew, system), not your shell profile, and is
  killed after `MONITOR_TIMEOUT` seconds (300).
- **BMAD v6** skills in `.claude/skills/` for PRDs, specs, stories, builds and reviews, under the ADE rules (`.ade/rules.md`).
- **Access tools**: `bin/remote` (SSH to the box), `bin/secret` (macOS Keychain), `bin/doctor` (what this Mac can reach).

Does a checkout know my work? Yes, as far as the hub's files go: STATE.md, memory, the journal and ACCESS.md are
committed, so a fresh clone (plus `bin/setup`) starts with full context. Secrets, SSH keys and files outside the repo
(downloads, PDFs) are not in it; `bin/doctor` says what is missing on a new Mac.

**A new Mac: clone to the same absolute path.** Several committed files hold the first Mac's absolute paths: each
folder's `.claude/settings.json` (the hook commands), `HUB_CLAUDE_CONFIG_DIR` in `hub.conf`, and `output_folder` in
`_bmad/config.toml`. Use the same user name and folder. Otherwise fix those values: move each folder's
`.claude/settings.json` aside and run `bin/new <folder>` again, edit `hub.conf` and `_bmad/config.toml`, then run
`bin/setup` and `bin/schedule install`.

## Upgrading a hub made before auto sync

After pulling these scripts into a hub made earlier:

1. Folder sessions hear hub changes only with the new `UserPromptSubmit` hook, and `bin/new` keeps an existing
   `projects/<x>/.claude/settings.json` (or `ops/<x>/...`). For each folder, either move that file aside and run
   `bin/new <folder>` again (it remakes only missing files), or add this line under `"hooks"` by hand, with your hub's
   path and the folder:
   `"UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "\"/path/to/hub\"/bin/changes projects/<x>" }] }],`
2. Run `bin/schedule install` again to load the monitor and sync jobs.
3. Auto sync is on unless `hub.conf` says `HUB_AUTO_SYNC=0`. It needs gitleaks and `bin/setup` (git hooks); without
   them every run is refused and logged in `sync.log`.

## Tests

`bash tests/run.sh` (macOS, Bash 3.2+). Every `bin/` script has a test run against a throwaway copy with stubbed tools.
