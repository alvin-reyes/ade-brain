# Design note: ade-skills

Status: Draft (2026-11-21). Decision record: ADR 0004. Lean mode: this note replaces a PRD and architecture.

## Goal

One shared catalogue of skills and tools developers use every day (git, Gmail, ClickUp, custom MCP servers), installed
the same way in every hub and project, and grown by developers through pull requests.

## Shape

A Claude Code plugin marketplace (format checked against code.claude.com plugin docs, 2026-11-21):

```
.claude-plugin/marketplace.json    name, owner.name, plugins[] (name, source: ./plugins/<name>)
plugins/
  _template/                       copied (or generated with bmad-toolsmith) to start a plugin
  git/                             conventions: commit as the user, no AI attribution, branch and PR flow (gh)
  gmail/                           drafts by default; sending needs the user's confirmation
  clickup/                         task conventions; writes need confirmation
  custom/<server>/                 teams' own MCP servers
    .claude-plugin/plugin.json     name, description, version
    skills/<skill>/SKILL.md
    .mcp.json                      mcpServers
tests/run.sh                       the verification command for this repo
```

- **Install:** `/plugin marketplace add better-ade/ade-skills`, then `/plugin install <plugin>@ade-skills`. A project
  pre-declares them for teammates in its committed `.claude/settings.json` (`extraKnownMarketplaces`, `enabledPlugins`);
  each teammate still installs on their own machine. `bin/init` in ade-brain can write these entries (later story).
- **Versions:** each plugin sets `version` in its `plugin.json` only (never also in the marketplace entry); a change
  that does not bump it does not reach users. Hubs may pin the marketplace with a `ref` or `sha`.
- **Secrets:** none in the repo. Remote MCP servers use OAuth where offered (`/mcp` sign-in; tokens kept by Claude Code).
  Keyed servers use a `headersHelper` command that calls ade-brain's `bin/secret <name>`, not `${VAR}` env expansion,
  so the key is never in the environment (ADR 0002). Open: the docs do not say outright that OAuth works the same for a
  server declared in a plugin's `.mcp.json`; check it with the first remote server.

## Adding a skill (developers)

1. Copy `plugins/_template/` (or run `bmad-toolsmith`), fill in the skill and plugin manifest, bump `version`.
2. Open a PR. CI runs `tests/run.sh`: manifests valid, names unique, `version` set in one place, gitleaks finds no
   secret, and every skill that sends or changes something outside (email, task, push) states that it asks first.
3. A reviewer approves; nothing is published unreviewed.

## Out of scope

BMAD skills (ADE ships v6); support for providers other than Claude (plugins are Claude Code only; the MCP servers in
`custom/` remain usable by other tools directly).

## First slice

The repo with `marketplace.json`, `_template/`, `tests/run.sh` and one plugin, `git`, which needs no MCP server and no
secret. Gmail and ClickUp follow, then the first custom server.
