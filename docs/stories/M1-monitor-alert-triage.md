# M1: an ALERT wakes the monitor role to triage it

Status: Ready for development (2026-11-21). Risk: medium (runs a model unattended on alert text).
Owner's intent (2026-11-21): a monitor sub-orchestrator watches tools and delegates to focus agents; it is separate
from the main orchestrator (the developer's personal assistant), which approves anything that changes something.
Role: `monitor` in ade-agent-registry. Verification command: `bash tests/run.sh`.

## Goal
When `bin/monitor` raises a **new** ALERT, it runs one read-only triage with the `monitor` role through `bin/agent`, and
journals and notifies the verdict. Polling stays model-free; a model runs only once per alert. Delegation to focus
sessions (runbooks) is a later story (M2).

## Scope
- `bin/monitor`: after it records a new ALERT (the existing `$ST/<key>.alert` transition), and only when
  `HUB_MONITOR_TRIAGE=1` in hub.conf (default off), run `bin/agent --role triage --folder <folder>` with the task on
  stdin: the role text (the hub's `.ade/agents/monitor.md` if present, else a built-in five-line version of the
  registry role) followed by the monitor's output, marked as untrusted data.
- The report goes to `reports/monitor/<folder>/<UTC time>-<monitor>.md`; one journal line names the verdict line and the
  report path; the existing notification gains the verdict.
- A triage failure (exit 1 or 2) journals `monitor triage failed: <monitor> exit <n>` and the alert still notifies.
- Triage never blocks the run: at most one triage per run starts at a time, each capped by `AGENT_TIMEOUT`.

## Acceptance criteria (tests in `tests/test_monitor.sh`, with a fake `bin/agent`)
| AC | Criterion | Test |
|---|---|---|
| 1 | `HUB_MONITOR_TRIAGE` unset: a new ALERT behaves exactly as today (no `bin/agent` call). | `triage_off_by_default` |
| 2 | With triage on, a new ALERT calls `bin/agent --role triage --folder <folder>` once. | `new_alert_triaged_once` |
| 3 | The same ALERT on the next run (still alerting) is not triaged again. | `repeat_alert_not_retriaged` |
| 4 | The task arrives on stdin, contains the role text and the monitor output, and the output is marked untrusted; nothing from it is in argv. | `task_on_stdin_marked_untrusted` |
| 5 | The report is written under `reports/monitor/<folder>/` and the journal line names its path. | `report_written_and_journaled` |
| 6 | A failing `bin/agent` (exit 1 and exit 2) journals `monitor triage failed: <monitor> exit <n>`; bin/monitor exits 0. | `triage_failure_journaled` |
| 7 | `.ade/agents/monitor.md` in the hub replaces the built-in role text. | `hub_role_file_wins` |
| 8 | A status change without ALERT never triggers triage. | `no_triage_without_alert` |

## Out of scope
Starting focus sessions or work orders (M2); any write action; new monitors or MCP connections; changing `bin/agent`.

## Verification
Command: `bash tests/run.sh` (must print `ok    test_monitor.sh` and exit 0). Real output recorded by the reviewer:
