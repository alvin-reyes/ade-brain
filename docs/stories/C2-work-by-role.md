# C2: `bin/work --role` opens a focus agent on its role's model

Status: **Done (2026-11-21)**: `bash tests/run.sh` green (28 of 28 test files ok, exit 0) after the quick review's 3 fixes. Risk: medium.
Owner's intent (2026-11-21): the orchestrator and builders run on the models the owner picks, any provider; default
Anthropic Opus 5.5. Roles table: `bin/lib.sh` `role_pick` (contract `.ade/context/providers.md`, "Roles").
Verification command: `bash tests/run.sh`.

## Goal
`bin/work --role <role> <folder>` resolves the role with `role_pick` and opens the focus session on that provider and
model, through the existing `--provider`/`--model` path and all its gates (key pre-check, hub refusal, no-go features).

## Acceptance criteria (`tests/test_work.sh`, fake claude and terminal as today)
| AC | Criterion | Test |
|---|---|---|
| 1 | `--role builder` opens the session with the provider and model `role_pick builder` returns | `role_sets_provider_and_model` |
| 2 | `HUB_ROLE_BUILDER` in hub.conf changes the pick (e.g. a deepseek model) and the session follows it | `role_follows_hub_conf` |
| 3 | `--role` with `--model` or `--provider` exits 2 (one way to choose) | `role_excludes_model_and_provider` |
| 4 | An unknown role exits 2 naming the known roles | `unknown_role_refused` |
| 5 | No usable candidate (all refused) exits 1 with each skip reason, and nothing opens | `no_usable_candidate` |
| 6 | The chosen provider's gates still apply (a missing key refuses before launch) | `role_keeps_provider_gates` |
| 7 | `bin/sessions` shows the role for a session started with `--role` | `sessions_show_role` |
| 8 | Default `builder` with no hub.conf entry is `anthropic:opus` | `builder_default_opus` |

## Verification
Reviewer run (2026-11-21, after merging main): `bash tests/run.sh` → 28 ok, 0 FAIL, exit 0. Quick review: 3 findings fixed (`[1m]` models, focus gate falls back, `--claude` used for the pick).
