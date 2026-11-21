---
title: 'More providers for delegated agents: GLM and Meta Muse'
type: 'feature'
ticket: ''
created: '2026-11-18'
status: 'draft'
baseline_revision: 'd0966c8'
route: 'full'
route_source: 'auto'
risk: 'high'
review: ''
review_source: ''
lenses_ran: []
review_loop_iteration: 0
context:
  - '{project-root}/.ade/context/providers.md'
  - '{project-root}/.ade/context/engines.md'
  - '{project-root}/.ade/context/decisions/0002-providers-and-engines.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Role routing can only send delegated work to Anthropic and DeepSeek, so the orchestrator cannot choose GLM or Muse for a role.

**Approach:** Add each vendor through the connection its own documentation supports, behind the same hub gates as DeepSeek, enabling one only once it has passed the provider checks.

## Boundaries & Constraints

**Owner decisions (2026-11-19):** Gemini ships separately through Gemini CLI. GLM and Muse are enabled only after a live check with the owner's keys, using dummy files only. Both stay limited to the owner's own hubs.

**Always:**
- The orchestrator stays on Anthropic; delegated agents stay read-only.
- Keys reach the engine only through `bin/secret`; a missing key stops the run before any call and never falls through to the Anthropic login.
- Base URLs live only in `bin/lib.sh`. `-contributor` Muse models are refused, because Meta trains on that traffic.
- No automatic move to another vendor after a run starts. Tests use fakes and never a real provider.

**Never:** a third-party or local translating gateway holding keys or client code; default roles that send work to a provider the owner has not enabled; write access.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| GLM enabled | owner's hub, allowed, key stored, `HUB_ROLE_X="glm:sonnet"` | runs on `api.z.ai/api/anthropic` | none |
| Muse enabled | same, `muse:sonnet` | runs on `api.meta.ai` with a standard model | none |
| Contributor model | `muse:muse-spark-1.3-contributor` | nothing runs | exit 2 |
| Provider without a go | listed in a role | skipped, `bin/roles` gives the reason | exit 2 if nothing else is usable |
| Key missing | allowed, no key | skipped before any call | reason shown |

</frozen-after-approval>

## Code Map

- `bin/keys`, `key_tools` in `bin/lib.sh` (branch `provider-keys`) -- keys are set here; base this work on that branch.
- `bin/lib.sh:79-105` -- `providers`, `provider_field`, `provider_feature_go`; glm row has `unconfirmed` models.
- `bin/lib.sh` `role_candidates`, `candidate_refusal` -- where a refused model id belongs.
- `bin/agent:35-50`, `bin/agent.py` -- assume the `claude` engine; a Gemini engine changes both.
- `tests/test_providers.sh:107-119,293-303,333-337,585` -- pin glm disabled and no `muse` row until a go; change only with the go.
- `tests/test_roles.sh:119` -- glm delegation refusal.
- `.ade/context/engines.md:204-270` -- recorded GLM and Muse findings and required canaries; add 2026-11-18 doc findings.
- `.ade/context/providers.md`, `decisions/0002-providers-and-engines.md:39,61`, `README.md:246` -- contract, per-provider owner decision, public wording.

## Tasks & Acceptance

**Execution:**
- [ ] `tests/test_providers.sh`, `tests/test_roles.sh` -- write first: matrix rows, Bearer-only and header behaviour seen by a fake server.
- [ ] `bin/lib.sh` -- GLM models, `muse` row, go lines per the live result, contributor refusal.
- [ ] `.ade/context/engines.md`, `.ade/context/providers.md`, `.ade/context/decisions/0002-providers-and-engines.md`, `README.md` -- findings, contract, owner decisions, docs.

**Acceptance Criteria:**
- Given a client hub, when a role lists an owner-only provider, then no process receives that provider's base URL.
- Given a provider without a recorded live pass, when `bin/agent` runs, then it does not start that provider.

## Implementation Notes

## Plan Change Log

## Review Triage Log

## Design Notes

Vendor documentation read 2026-11-18. GLM and Muse document Claude Code setup using `ANTHROPIC_AUTH_TOKEN`. `apiKeyHelper` sends both Bearer and `x-api-key`; neither vendor says whether that is accepted. Muse rejects unknown top-level fields, and Claude Code sends `context_management`, which Meta's page does not list. Google documents an OpenAI-compatible endpoint only, so Gemini cannot use the provider table.

## Verification

**Commands:**
- `bash tests/run.sh` -- expected: exit 0, every test file `ok`.
