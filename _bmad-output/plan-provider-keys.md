---
title: 'bin/keys: set a key for each AI tool'
type: 'feature'
ticket: ''
created: '2026-11-19'
status: 'built'
baseline_revision: '0f7eeb91958fecffc7165a11c74b89fc7b253024'
route: 'oneshot'
route_source: 'auto'
risk: 'medium'
review: 'quick'
review_source: 'pinned'
lenses_ran: ['quick']
review_loop_iteration: 0
context:
  - '{project-root}/.ade/context/providers.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** A developer has to know each vendor's Keychain name to store a key, and cannot see in one place which keys are set or why a tool is still unusable.

**Approach:** `bin/keys` lists DeepSeek, GLM, Muse and Gemini with stored or missing status, and `bin/keys set <tool>` and `bin/keys forget <tool>` manage the key through `bin/secret`. A key is taken only from a hidden prompt or stdin and never reaches a process argument; storing a key does not enable a tool.

</frozen-after-approval>

## Implementation Notes

Oneshot: about 100 lines. `bin/secret --set` passed the value to `security` as an argument; it now uses `security -i` on stdin and reads the value back. Round trip proven against the real Keychain with a throwaway item, deleted afterwards.

## Review Triage Log

- medium, patched: a key typed as the tool name was repeated in the error.
- low, patched: argument errors exited 1 without `security`; "ready" did not say it means `bin/agent`; contract gaps; missing tests for empty value, failed store and forgetting one tool.
- false: argv assertions are weak. A direct `security add-generic-password -w` is logged by the stub, so the check catches it.
- false: `security -i` parsing unproven. Quotes, backslash, dollar, leading dash, hash, single quote and 400 characters round-tripped in the real Keychain with throwaway items, and a mismatch fails the read-back.

## Verification

**Commands:**
- `bash tests/run.sh` -- expected: exit 0, every test file `ok`.
