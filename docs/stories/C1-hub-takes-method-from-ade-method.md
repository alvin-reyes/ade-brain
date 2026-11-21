# C1: the hub takes the method from ade-method

Status: **Done (2026-11-21)**: `bash tests/run.sh` green (29 of 29 test files ok, exit 0) after the quick review's fixes. Risk: medium. Depends on: ade-method v2 merged and tagged (`v2.0.0`).
Owner's intent (2026-11-21): ade-method is the only home of the method (ADR 0004); the hub keeps no copy of its own.
Verification command: `bash tests/run.sh`.

## Goal
`bin/method sync [ref]` copies ade-method's `rules.md` to `.ade/rules.md` and `bmad/custom/*.toml` to `_bmad/custom/`,
from `better-ade/ade-method` at `HUB_METHOD_REF` (hub.conf; default the tag the template pins), and records the ref.
A test fails when the hub's copies differ from the pinned ref's files, so they cannot drift.

## Acceptance criteria (`tests/test_method.sh`, against a local fixture repo via `AGENT_METHOD_REPO`, never the network)
| AC | Criterion | Test |
|---|---|---|
| 1 | `bin/method sync` writes `.ade/rules.md` and `_bmad/custom/bmad-build.toml`, `bmad-code-review.toml` from the ref | `sync_copies_method` |
| 2 | `.ade/method-version` holds the ref and the commit it resolved to | `version_recorded` |
| 3 | `HUB_METHOD_REF` in hub.conf picks the ref; an argument overrides it | `ref_from_conf_or_arg` |
| 4 | An unknown ref or unreachable repo exits 1, and no file is changed | `bad_ref_changes_nothing` |
| 5 | `bin/method check` exits 1 naming each file that differs from the recorded ref, 0 when all match | `check_finds_drift` |
| 6 | `bin/doctor` reports method drift as one row (name only) | `doctor_reports_drift` |
| 7 | `bin/init` runs `bin/method sync` at the pinned ref, so a new hub starts in step | `init_syncs_method` |
| 8 | The template's own `.ade/rules.md` and `_bmad/custom/` equal the pinned ref's (no lean-mode section of its own) | `template_matches_pin` |

## Out of scope
Personas, hub CLAUDE.md, ADE's vendoring, skills selection by `ade.json` (later).

## Verification
Reviewer run (2026-11-21, after merging main): `bash tests/run.sh` → 29 ok, 0 FAIL, exit 0. Quick review: ADR 0005 supersedes 0003's Opus-only rule, README updated, stale overrides removed on sync, failed init sync recorded; 2 findings rejected (network-free pin test by design; mid-write failure unlikely).
