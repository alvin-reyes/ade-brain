# C3: `bin/dispatch` starts focus agents for ready tickets

Status: Ready for development (2026-11-21). Risk: high (starts agents unattended). Depends on: C2.
Owner's decisions (2026-11-21): every work order is a BMAD ticket; the orchestrator runs one or two agents at a time;
high-risk tickets stop for the owner before building and before Done, medium and low do not; a ticket may opt in with
`hitl`. Verification command: `bash tests/run.sh`.

## Goal
`bin/dispatch <folder>` reads the folder checkout's `tickets next`, and for each `ready_to_start` ticket, up to the free
slots, opens `bin/work --role builder --name <ref> --prompt "bmad-build <ref>" <folder>`. High-risk and `hitl` tickets
are listed as waiting for the owner instead; `bin/dispatch --approve <ref> <folder>` starts one of them.

## Acceptance criteria (`tests/test_dispatch.sh`, fake `tickets` output and fake `bin/work`)
| AC | Criterion | Test |
|---|---|---|
| 1 | Two ready medium/low tickets and `HUB_DISPATCH_MAX` unset (1): one `bin/work` call, with `--role builder`, `--name <ref>` and the bmad-build prompt | `starts_one_by_default` |
| 2 | `HUB_DISPATCH_MAX=2` starts two; values above 2 are capped at 2 | `max_capped_at_two` |
| 3 | A ticket whose name already runs (`bin/sessions`) is not started again, and counts against the slots | `running_ticket_not_restarted` |
| 4 | A high-risk or `hitl` ticket is not started; it is printed and journaled once as "waiting for the owner" | `high_risk_waits` |
| 5 | `--approve <ref>` starts that one ticket even when high-risk, and only when it is ready | `approve_starts_one` |
| 6 | Blocked, in-progress and to-refine tickets are never started | `only_ready_started` |
| 7 | `tickets next` failing (no BMAD, bad tree) exits 1 with its message and starts nothing | `bad_tree_starts_nothing` |
| 8 | One journal line per run lists what started and what waits | `run_journaled` |

## Out of scope
The Done checkpoint for high-risk tickets (bmad-build's present step already stops); a schedule for dispatch (run by the
orchestrator or by hand); trackers other than the repo store (plugins, later).
