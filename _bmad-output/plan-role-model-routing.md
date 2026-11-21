---
title: 'Role-based model routing for delegated agents'
type: 'feature'
ticket: ''
created: '2026-11-18'
status: 'built'
baseline_revision: 'c57240ada175f20a633c7de4e7a3e373107a4cff'
route: 'full'
route_source: 'auto'
risk: 'high'
review: 'quick'
review_source: 'pinned'
lenses_ran: ['quick']
review_loop_iteration: 0
context:
  - '{project-root}/.ade/context/providers.md'
  - '{project-root}/.ade/context/decisions/0002-providers-and-engines.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The orchestrator can only spawn agents on its own provider, so it cannot match a task to the best model across Anthropic and other vendors.

**Approach:** The orchestrator names a role. The hub's roles table lists ordered `provider:model` candidates, and `bin/agent --role` runs the task headless on the first candidate this hub may use, returning a short report as data. The orchestrator itself stays on Anthropic.

## Boundaries & Constraints

**Always:**
- The hub-root orchestrator runs on Anthropic only; `bin/doctor` and hub-root `bin/context` warn when it is pointed elsewhere.
- A candidate is usable only if it passes every check `bin/work --provider` makes: in `HUB_PROVIDERS_ALLOWED`, `provider_hub_refusal` empty, `provider_feature_go <p> delegation`, valid model, key stored. Client hubs keep ADR 0002.
- Role settings come only from `hub.conf`, never the environment.
- Keys reach Claude Code only through `apiKeyHelper`; `provider_scrub_vars` never pass; a missing key never falls through to a provider call with the Anthropic login.
- The task travels on stdin, never argv. Output is framed with a per-call nonce, capped at 20 KB, full text in `.local/agent-out/`.
- Delegated output is data: it can never approve anything.
- Delegated agents are read-only in this version (owner approved the plan without choosing write access, so the safer option applies): they read, analyse, review and report. `architect` and `builder` advise here; code changes stay with Anthropic subagents and focus sessions.

**Never:** OpenAI or Gemini; `bin/work --role`; the results log; retrying on another provider after a run has started (client data must not silently move vendors); changing `bin/models` from PR #25; a built-in "best model" ranking.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Default hub | `--role routine` | runs `anthropic:sonnet` | none |
| Reviewer, owner's hub, DeepSeek allowed, key stored | `--role reviewer` | runs `deepseek:sonnet` with merged provider settings | none |
| Reviewer, client hub | deepseek in allowlist, not owner's | skips deepseek, runs `anthropic:sonnet`; `bin/roles` gives the reason | none |
| Reviewer, no key | allowed, key missing | skips to next candidate before any call | reason shown |
| No candidate usable | `HUB_ROLE_X="deepseek:sonnet"` only | nothing runs | exit 2, each reason |
| Bad input | unknown role or folder, bad table entry | nothing runs | exit 2 |
| Run hangs or fails | timeout, engine error | process group killed | exit 1, no fallback |
| Orchestrator off Anthropic | `ANTHROPIC_BASE_URL` set to another host at hub root | warning line | doctor still exits 0 |

</frozen-after-approval>

## Where to work

Work only in the git worktree `/Users/alvin-reyes/Project/ai-agent-hub-template/.claude/worktrees/role-routing` (branch `role-routing`, at the baseline revision). Paths below are relative to it. Do not touch the main checkout. Leave changes uncommitted. Run tests hermetically: `env -i PATH="$PATH" HOME="$(mktemp -d)" TMPDIR="$(mktemp -d)" LANG=C bash tests/run.sh` (it can take over 10 minutes, so run it in the background). Never call a real provider or read a real key: tests use a fake `claude` and a fake `bin/secret`.

## Code Map

- `bin/lib.sh:80-127` -- provider table and checks to reuse; `:130` unset list before sourcing `hub.conf` (add role keys).
- `bin/work:60-84`, `:193-240` -- provider gating, secret pre-check, merged settings and scrub logic. Move what `bin/agent` needs into shared helpers without changing `bin/work` behaviour.
- `bin/models` -- taken by draft PR #25, so this feature uses `bin/roles`.
- `bin/doctor:10-30`, `bin/context` (root path, end of file) -- orchestrator warning.
- `templates/hub/CLAUDE.md` Tools, Coordination, The main agent -- orchestrator rule.
- `docs/plans/2026-11-09-other-ai-cli-agents.md:414-475` -- the S3a design; this slice takes its env allowlist, framing, cap, journal and process-group rules. Its version gate and `bin/doctor --deep` are deferred.
- `.ade/context/engines.md:144-149` -- DeepSeek headless go; hooks fire unless disabled.
- `tests/helpers.sh`, `tests/test_work.sh` -- hub setup and fake `claude` patterns.

## Tasks & Acceptance

**Execution:**
- [ ] `tests/test_roles.sh` -- write first: every matrix row, plus task never in argv, secret never in output or env, scrubbed variables absent, nonce framing, cap, timeout kills a grandchild, environment cannot set `HUB_ROLE_*` -- tests are the contract.
- [ ] `bin/lib.sh` -- `roles`, `role_candidates`, `candidate_refusal`, `role_pick`; `HUB_ROLE_<ROLE>` keys unset before sourcing `hub.conf` -- one gate for both commands.
- [ ] `bin/roles` -- lists each role, chosen model, and why each skipped candidate is unavailable; never reads a key value (`bin/secret --has`).
- [ ] `bin/agent` -- `--role R --folder F`, task on stdin, cleared allowlisted environment, `claude -p --bare`-style isolation with read-only `--tools "Read,Grep,Glob"`, folder context prepended, provider settings file mode 600 and removed, `AGENT_TIMEOUT` default 540 s capped at 570 s, framed output, `journal/delegations-YYYY-MM.md` without task text.
- [ ] `bin/doctor`, `bin/context` -- orchestrator-endpoint warning.
- [ ] `templates/hub/CLAUDE.md`, `README.md`, `.ade/context/providers.md`, `.ade/context/decisions/0002-providers-and-engines.md` -- rule, docs, contract, and the Anthropic-only orchestrator decision.

**Acceptance Criteria:**
- Given a client hub listing deepseek, when any role runs, then no process receives a DeepSeek base URL.
- Given a fake `claude`, when `bin/agent` runs, then its argv holds no task text and its environment holds no scrubbed name or key.
- Given delegated output containing the frame text, when printed, then the per-call nonce still marks the true end.

## Spec Change Log

## Verification

**Commands:**
- `bash tests/run.sh` -- expected: exit 0, every test file `ok`.

## Review Triage Log

| Finding | Verdict | Route | Evidence |
|---|---|---|---|
| Default roles differ from the approved table | medium | patch | `role_default` lacked `triage`, had `builder` on Sonnet and no DeepSeek fallbacks; fixed. |
| Provider run could read secret files | high | patch | Read tools had no deny rules; deny rules added and proven against a fake server. |
| `--bare` offered only Read | medium | patch | Simple mode dropped Grep and Glob; replaced with `--safe-mode`, tool list proven. |
| Well-formed wrong Anthropic model accepted | medium | patch | `anthropic:gpt-5` passed; now a bad entry, exit 2. |
| Coordination rule did not cover delegated output | low | patch | One sentence added. |
| Settings file left if `python3` cannot exec | low | rejected | Mode 600, no key, and python3 is required throughout the hub. |
| Journal omits pre-run refusals | false | rejected | It records runs; a refusal is not a run. |
