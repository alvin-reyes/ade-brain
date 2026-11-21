# 0004: The better-ade repos: method, agents, brain, skills, app

- Status: Accepted for ade-method and ade-brain (owner, 2026-11-21). ade-skills: Proposed, until its first plugin ships
  (design note `docs/plans/2026-11-21-ade-skills.md`).
- Context: ade-method (named ade-setup until 2026-11-21) and ade-brain had started to overlap (`.ade/rules.md` here differs from ade-method's `rules.md` only
  by section 5, lean mode, which exists only here), and model assignments were split across ADE, ade-method and the hub.
  Merging the two repos was considered and rejected: ADE vendors ade-method into every project at a pinned ref, while
  ade-brain is copied once per hub and changes daily on main.
- Decision: one job per repo, all in the better-ade GitHub org.

| Repo | Job | Holds | Never holds |
|---|---|---|---|
| ade-method | How agents work | `rules.md`, the 4 core roles (product, architect, developer, reviewer), BMAD v6 overrides and skill lists, the *format* of the context store | stored context, secrets, BMAD v4 |
| ade-brain | What agents know | memory, journal, folder `STATE.md`, brain index, session logs, personas, and the orchestrator (`bin/work`, `sessions`, `models`, `keys`, `agent`, `sync`) | the methodology (it takes `rules.md` from ade-method) |
| ade-agent-registry | Specialist agents, loaded only when a task needs one | frontend, backend, devops, sysadmin, qa, security-reviewer, analyst, monitor, support | the core roles (ade-method) |
| ade-skills | What agents can do | predefined skills, plugins and MCP server configs devs use (git, Gmail, ClickUp, custom MCP servers); devs add more by PR | BMAD (ADE ships v6), secrets |

  1. **Project context stays in each project's repo.** `.ade/context/` and `.ade/knowledge/` are checked in with the code,
     so a teammate without the hub still has them and they change in the same commit as the code. ade-brain indexes
     them read-only; it never writes back.
  2. **The orchestrator stays in ade-brain.** It is neither methodology nor storage, but it is what reads and writes the
     storage; personas stay here too, because they carry `{{CLIENT}}` and `{{OWNER}}` and are per hub.
  3. **Secrets live only in ade-brain's Keychain service** (`bin/keys`, `bin/secret`). ade-skills names a key, never
     holds one, and follows ADR 0002's rule that a key is never placed in the environment: OAuth for remote MCP servers
     where offered, otherwise a helper command that calls `bin/secret`.

| ade-terminal | The app (was better-agentic-ide) | terminals, picker, project setup; vendors ade-method | the method itself |
| ade-website | The public site | ade.ardata.tech; copies the installers from ade-terminal | project documents |

  4. **Later decisions (owner, 2026-11-21):** ade-method v2 was rebuilt from scratch (v1 tagged `v1-final`); BMAD v6
     only, tracking the latest upstream; review scales with risk; the orchestrator and builders run on any provider,
     default Anthropic Opus 5.5; every work order is a BMAD ticket (trackers such as ClickUp as stores, via plugins);
     users include tech support people. A task queue (ade-queue) was considered and dropped.

- Consequences:
  - Follow-up stories: (a) `bin/brain index` reads `.ade/context/**` and `.ade/knowledge/**` from each folder's
    checkouts; (b) lean mode moves into ade-method's `rules.md` and the hub takes `rules.md` from ade-method at a pinned
    ref, with a test that fails on drift (needs the owner's go-ahead, it changes ade-method); (c) the ade-skills repo, per
    its design note.
  - Until (b) ships, a change to `.ade/rules.md` here must be made in ade-method too.
