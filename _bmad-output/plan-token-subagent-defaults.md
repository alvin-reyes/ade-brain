---
title: 'Token-efficient subagent defaults: Sonnet subagents, Sonnet build review, quick code review'
type: 'feature'
ticket: ''
created: '2026-11-11'
status: 'in-progress'
baseline_revision: 'c72160ff76cd3fae27b35f7a2538c1bdfc3e5b93'
route: 'oneshot'
route_source: 'auto'
risk: 'low'
review: ''
review_source: ''
lenses_ran: []
review_loop_iteration: 0
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Token use is high. About 15 BMAD skills launch subagents without naming a model, so in an Opus session they all run on Opus. bmad-build's review step tells its reviewers to match the session's model. bmad-code-review runs 4–5 "thorough" lenses on every review.

**Approach:** (owner-approved, 2026-11-11)
1. Subagents default to Sonnet: `CLAUDE_CODE_SUBAGENT_MODEL` goes in the `env` of the hub root `.claude/settings.json` and of `templates/folder-settings.json`, so `bin/work` sessions get it too. It is configurable through a new `HUB_SUBAGENT_MODEL` in hub.conf, which `bin/init` writes (`--subagent-model M`, default `sonnet`). No `_FORCE`, so an explicit model still wins (bmad-build's Opus implementation subagent).
2. A bmad-build override (`_bmad/custom/bmad-build.toml`): its review-lens subagents run on Sonnet, which overrides "same model capability as the session".
3. A bmad-code-review override (`_bmad/custom/bmad-code-review.toml`): `review = "quick"` by default; thorough when the diff is over 200 lines or the user asks.
Personas keep their models. Tests first; the verification command is `bash tests/run.sh`. README and docs cover the new flag.

</frozen-after-approval>

## Implementation Notes

Oneshot route: about 40 changed lines across init, new, two settings files, two BMAD overrides, one test and the docs; Opus session.

- The review selection is picked when the workflow is rendered (`workflow.md` checks `workflow.review`; `step-02-review.md` uses `{% if workflow.review == "quick" %}`), so a fact cannot switch lenses mid-run. "Thorough over 200 lines" is done as a persistent fact: a quick review of a diff over 200 changed lines says so and offers a thorough run (`bmad-code-review thorough`). An explicit "thorough" already selects the thorough lenses (SKILL.md `--set workflow.review=thorough`).

## Verification

**Commands:**
- `bash tests/run.sh` -- expected: every test prints `ok`, exit 0

## Session handoff (2026-11-11)

**State:** item 1–3 built as frozen above; `bash tests/run.sh` green (exit 0, every test `ok`); NOT committed (held by
the owner). Uncommitted files: `.claude/settings.json`, `templates/folder-settings.json`, `bin/init`, `bin/new`,
`_bmad/custom/bmad-build.toml`, `_bmad/custom/bmad-code-review.toml`, `tests/test_models.sh`, `README.md`,
`.ade/context/model-defaults.md`, `.ade/context/decisions/0002-subagents-on-sonnet.md`.

**Quick review (one Sonnet lens), accepted, not yet fixed:**
- `docs/index.html` (flag table ~281, hub.conf tables ~629/658) and `templates/hub/README.md:34` lack `--subagent-model` / `HUB_SUBAGENT_MODEL`.
- ADR 0002 says existing hubs get the folder default by re-running `bin/new`; `bin/new` keeps an existing settings file, and the root settings have no refresh path.
- "Thorough over 200 lines" is only an offer, not automatic (review lenses are chosen at render time). Owner to accept or not.
- Tests don't cover `bin/new` refusing a bad `HUB_SUBAGENT_MODEL`, or the 200-line / Opus-review facts.

**New owner requirement: models configurable via ADE.** Owner's split: ADE (the terminal) sets the models;
`ade-setup` holds BMAD (and the ADE roles); this repo holds the persona/agent templates.
Docs (code.claude.com/docs/en/env-vars.md#precedence): a settings `env` value replaces the shell's, so the `env` block
written here would override ADE. Subagent model order: Agent-tool `model` > definition `model:` >
`CLAUDE_CODE_SUBAGENT_MODEL` > session model; no settings key or CLI flag.

**Revised plan, awaiting the owner's go:**
- This repo: drop the `env` blocks from `.claude/settings.json` and `templates/folder-settings.json`; keep
  `HUB_SUBAGENT_MODEL`/`--subagent-model` as a fallback only, applied by `bin/work` at launch as
  `CLAUDE_CODE_SUBAGENT_MODEL=${CLAUDE_CODE_SUBAGENT_MODEL:-$HUB_SUBAGENT_MODEL}` (ADE's value wins). Personas unchanged.
  Fix the review findings above. Then re-run `bash tests/run.sh` and commit.
- ade-setup (only on the owner's word): roles keep no `model:` except `developer: opus`; the BMAD overrides move there
  and say "pass no model" for review lenses (they follow ADE's default), code writer stays explicit `opus`; quick
  review default moves with them. Open: whether ADE vendors a `_bmad/custom/` from ade-setup (ADE source not on this
  machine). Until confirmed, the overrides stay here, edited to "pass no model".

## Session handoff 2 (2026-11-11)

Revised plan built for this repo (owner said "continue"): no settings `env` blocks; `bin/new` reverted; `bin/init`
keeps `--subagent-model`/`HUB_SUBAGENT_MODEL` as a fallback; `bin/work`'s launcher exports
`CLAUDE_CODE_SUBAGENT_MODEL="${CLAUDE_CODE_SUBAGENT_MODEL:-<inherited, else HUB_SUBAGENT_MODEL, else sonnet>}"`
(bad values exit 2). BMAD overrides: review lenses "pass no model"; Opus code writer and quick review unchanged.
Docs (README, templates/hub/README.md, docs/index.html), `.ade/context/model-defaults.md` and ADR 0002 updated; tests
cover the fallback, ADE-wins, empty/bad values and the BMAD facts. `bash tests/run.sh`: exit 0, all 20 `ok`.
Not committed. Still open: the 200-line rule is an offer only; ade-setup changes need the owner's word.

## Code Review

### 2026-11-11 (PR #13, quick, aaee59a vs main da9cf7a)

Code review complete. 0 decision-needed, 1 patch, 0 defer, 6 rejected.

- [x] [Review][Patch] A person's name in two template files that every hub copies: "(Alvin, 9 Nov 2026)" breaks CLAUDE.md "no person names"; tests/test_root.sh only checks templates/ [_bmad/custom/bmad-build.toml:1, _bmad/custom/bmad-code-review.toml:1]

Rejected:
- false: "thorough over 200 lines" is only an offer. The owner accepted that on 2026-11-11; lenses are chosen at render time.
- false: the hub root gets no subagent default. That is the owner-approved revised plan (ADE sets models); ADR 0003 records it. Fixing it would edit the plan.
- false: scope beyond the plan. PR #13 deliberately carries 506562c and c72160f (in its description), and the trap change is the merge combining main's launcher with the session record.
- false: the "Opus review" exception is new. It came from 8baa9e0 (9 Nov, owner-approved) and is unchanged in intent.
- low, rejected: the launcher's own CLAUDE_CODE_SUBAGENT_MODEL wins over the caller's and is not validated. That is by design (commented). The value is an env var, never interpolated into shell, so a bad one is the user's own shell setting; a fix adds guards.
- false: no test for a missing HUB_SUBAGENT_MODEL key. `${HUB_SUBAGENT_MODEL:-sonnet}` treats unset and empty the same, and the empty-value test covers that expansion. The grep-only BMAD checks are the limit of what a shell test can show about instructions to an LLM.

### 2026-11-11 (PR #13, quick, second run, aaee59a vs main da9cf7a)

Code review complete. 0 decision-needed, 3 patch, 0 defer, 4 rejected.

- [x] [Review][Patch] A person's name in two template files that every hub copies (again; not yet fixed) [_bmad/custom/bmad-build.toml:1, _bmad/custom/bmad-code-review.toml:1]
- [x] [Review][Patch] bin/work refuses a valid inherited model with a bracket suffix (e.g. `sonnet[1m]`, used in engines.md). The `[A-Za-z0-9._:/-]` check exits 2, which breaks "ADE's value wins". The first run's rejected note said the caller's value is not validated; it is [bin/work:46]
- [x] [Review][Patch] `bin/sessions` and `bin/work --force` are in no docs (README.md, docs/index.html, templates/hub/README.md) [README.md, docs/index.html, templates/hub/README.md]

Rejected:
- low, rejected: the one-session guard keys on the folder basename (`ops/acme` and `projects/acme` collide), and a wrapper not named claude* is not seen. The Remote Control name is already the basename, so such folders collide there too; the guard fails open for odd wrappers. Fixing it would change session naming.
- low, rejected: tests that run bin/work without --no-remote/--force read the real process table (test_models.sh:68,72; test_init.sh:32). They fail only while a real `claude --remote-control planning|environments` runs. A fake-ps fixture would add test plumbing. (test_models.sh's `sub()` uses --no-remote, so that part of the claim is false.)
- false: the frozen intent states the abandoned design. The owner approved the revision (handoff sections); fixing it would edit the plan.
- false: scope beyond the plan / the WORK_NO_OPEN hook. Same as the first run: the PR deliberately carries 506562c and c72160f, and the hook came with them.

### 2026-11-12 (PR #13, quick, third run, deac74c vs main)

Code review complete. 0 decision-needed, 2 patch, 0 defer, 6 rejected.

- [x] [Review][Patch] bin/init refuses `--subagent-model 'sonnet[1m]'` (exit 2), which bin/work accepts since deac74c, so HUB_SUBAGENT_MODEL cannot be set to it through init; untested [bin/init:39]
- [x] [Review][Patch] bin/work header comment breaks mid-sentence ("before anything" / "is opened or changed") [bin/work:8]

Rejected:
- false: the frozen Intent describes the settings `env` design. The owner approved the revision (handoff sections), and fixing it would edit the plan (third time raised).
- false: scope beyond the plan (bin/sessions, --force, WORK_NO_OPEN, trap change). PR #13 deliberately carries 506562c and c72160f; already rejected twice.
- low, rejected: the one-session guard misses `--remote-control=name`, non-claude* wrappers and basename collisions. bin/work itself always passes the name as a separate token; the basename collision is the Remote Control name's own; rejected on the second run.
- false: grep-only BMAD checks. The facts are instructions to an LLM; a shell test can only show the text is there (rejected on the first run).
- false: the 200-line rule is only an offer. The owner accepted the offer on 2026-11-11.
- low, rejected: the first handoff section names ADR 0002. It is a dated historical note, and fixing it would edit the plan; handoff 2 and the repo carry 0003.
