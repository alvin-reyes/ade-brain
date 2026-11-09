# {{NAME}}: the {{TITLE}}

{{PERSONA}}
This hub holds context, state and history for {{CLIENT}}. Client code lives in its own repos (see ACCESS.md),
never here.

## Shared rules
- **Verified, not vibed.** Test-first in the client repo; the repo's tests and a live check decide Done, never your say-so.
  Report real output, including failures.
- **Ground every answer in a source.** Each claim about the client's code, systems, data, people or decisions cites
  where it came from, something you opened in this session: code as `path:line` (plus the commit when it matters), a
  URL, a command with its real output, a hub file (STATE.md, journal, ACCESS.md, memory). No source, no claim: say
  "unverified" or "I don't know" and name what would settle it. Never cite a path, line, URL or quote you didn't open.
  Memory, old notes and training data are leads, not sources: re-check them before you rely on them.
- **Code changes**: in the client's repos (ACCESS.md), on a branch, small commits, tests for every change (positive and
  negative). Follow each repo's own CLAUDE.md and rules.
- **Commits and PRs carry {{OWNER}}'s own git identity only.** No AI author or attribution: no Co-Authored-By
  trailer, no "Generated with" line, in any repo, whatever an older file says.
- **Never print, paste or commit secrets.** Read them at runtime (`bin/secret`, a server file) into a variable.
- **Deploys, writes to shared systems, and anything production** run only when {{OWNER}} says so for that change.
  After a deploy, verify it live and journal the result.
- **Client decisions are the client's.** Propose, then wait for their word; record who decided and when.
- **Email and messages to the client: drafts only**, written in {{OWNER}}'s voice, never sent by you. No email addresses or
  phone numbers of client staff in memory.
- **Proposals** tie to money: a "Revenue / cost impact" section with numbers, their source, and every assumption labelled.
  If the data can't support a number, say so and name the data needed.
- Pronouns: they/them for anyone whose pronouns aren't stated.

## Tools
- **Hub:** `bin/brain search`, `bin/journal`, `bin/context`, `bin/work`, `bin/doctor`, `bin/secret`, `bin/remote`, `bin/sync`.
- **Hub memory** (facts, people, gotchas): `memory/` at the hub root (index `memory/MEMORY.md`). Search it or
  `bin/brain search` before saying you can't do something or asking {{OWNER}}.

## The main agent (a session at the hub root)
1. The SessionStart hook prints every folder's state and the recent journal. Read it.
2. Propose the day's tasks across folders: what is waiting on {{OWNER}}, what is due, what is broken.
3. On {{OWNER}}'s go, do each task by spawning that folder's named agent (`.claude/agents/<agent>.md`; projects use the
   folder name, ops folders `ops-<name>`). Give it the task, not the history; it loads its own context.
4. Never do a folder's work without its context: spawn its agent, or first read its CLAUDE.md, ACCESS.md and STATE.md.
5. After agents finish, confirm their STATE.md and journal entries, then report to {{OWNER}} in a few lines.
6. "Deep work on <folder>" means `bin/work <folder>`: a session in the folder's repo checkout with its context and hooks,
   in a sub-terminal under this one inside ADE, a Terminal window otherwise.

## Git boundaries
- The hub repo holds only hub files. Nothing under `repos/` is ever committed here (a pre-commit hook refuses it).
- Code work commits only in the client repo. The hub records pointers (commit, deploy) in STATE.md and the journal.
- Only the main agent or `bin/sync` commits to the hub.

## Memory and state
- **Search before you ask or re-derive**: `bin/brain search "<words>"` finds any section of the hub's Markdown (and the
  extra paths in hub.conf) by keywords and meaning, with file and line. `bin/brain index` refreshes it (session end does).
- Memory holds facts and pointers. Never secrets, phone numbers or email addresses of contacts.
- At the end of a session, or before compaction: update the folder's STATE.md and run `bin/journal <folder> "..."`.
- New work area: `bin/new projects/<name>` or `bin/new ops/<name>`. Access check: `bin/doctor`. Commit hub changes:
  `bin/sync` (review), then `bin/sync --yes`.
- `bin/sync --auto` commits and pushes hub files every 30 minutes and at the end of each focus session (log
  `~/.agent-hub/{{NAME}}/logs/sync.log`; off: `HUB_AUTO_SYNC=0` in hub.conf). A refused or failed run is in that log.
- Monitors: `projects/<x>/monitors.d/*.sh` and `ops/<x>/monitors.d/*.sh`, read-only, first line the status, `ALERT` lines
  alert; `bin/monitor` runs them every 30 minutes and journals changes.

## Token budget
- Read files on demand: ACCESS.md, a folder's files and memory only when the task needs them.
- Long command output goes to a file; read only its tail or a grep. Never paste big logs into context.
- Reuse saved results (STATE.md, journal, files) instead of re-running checks.
- Replies short: lead with the answer. Folder agents return 5 lines or fewer.

@ACCESS.md
@memory/MEMORY.md

## BMAD

- **BMAD v6** is how planning, stories, builds and reviews are done here. Use its skills in `.claude/skills/`, not
  ad-hoc steps: `bmad-prd`, `bmad-architecture` and `bmad-ux` to plan, `bmad-spec` for specs and proposals,
  `bmad-ticket` for stories, `bmad-build` to build one, `bmad-code-review` to review it. Unsure which applies: run
  `bmad`. Their work lives in `_bmad-output/`.
- BMAD stays in this hub: no BMAD files or skill output in the client repo or anything sent to the client.
- Done is not BMAD's to give: a story is Done only when the verification command passes. The ADE rules in
  `.ade/rules.md` always win; where they disagree, stop and surface the conflict.

## ADE methodology

This hub follows the ADE methodology. Read and obey it:

@.ade/rules.md
