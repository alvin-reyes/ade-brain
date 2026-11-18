# W1b: inside ADE, bin/work never opens a window (sub-terminal stopgap until ADE types commands)

Status: **Built, awaiting QA** (branch `w1b-ade-no-window`). Owner's rule (2026-11-09), in their words: "everytime I spawn a new process or terminal on the ade, it needs to be INSIDE the ADE only". So when `bin/work` runs inside an ADE terminal, it never opens a Terminal or iTerm window.

Builds on W1 (`docs/stories/W1-bin-work-opens-sub-terminals-in-ade.md`) and replaces the parts of it that opened a window inside ADE: the fallback on `ade open` exit 3 and 4 (C6b), the window for an ADE without `capabilities: command` (C18), the window forced by `AGENT_TERMINAL=terminal|iterm` inside ADE (C9), and the exit-1 hint `AGENT_TERMINAL=terminal bin/work <folder>` (C6a). Everything else in W1 stands.

Verification command: `bash tests/run.sh` (`docs/architecture.md`, "Verification command"). Unchanged.

## Behaviour inside ADE (all four ADE variables set and the helper executable)

`bin/work` probes `"$ADE_HOOK_BIN" help` once (stdin `/dev/null`, at most 5 s, stdout only, exit status ignored) and classifies the answer:

1. **`capabilities: command`** (a line starting `capabilities:` with the word `command`, ADE story 9): unchanged from W1. `"$ADE_HOOK_BIN" open --cwd <checkout> --name <folder> --focus -- bash -l <launcher>`. Exit 0 hands off; exit 5 prints the command to run and keeps the launcher.
2. **No capability, but `usage: ade open`** (stories 4a/4c without 9, ADE v0.23.0): the stopgap. `"$ADE_HOOK_BIN" open --cwd <checkout> --name <folder> --focus`, no command. On exit 0 `bin/work` keeps the launcher (and any provider settings file), prints one stderr line `work: opened sub-terminal '<folder>' in ADE; paste this there to start the session: bash -l '<launcher>'` (the path quoted with `sq`), and exits 0.
3. **Neither** (a hook-mode build without `ade open`, which answers `{}` and 0 to anything so a bare `open` would silently open nothing, or no answer in 5 s): exit 1 with one `work:` line naming `ade open` and the outside-ADE hint. Nothing opened, no window. *Decision made here:* the owner's brief said to run the bare `open` whenever the capability is missing; for a hook-mode helper that would print "opened sub-terminal" when nothing opened, so `bin/work` fails instead.
4. **Any `ade open` failure** in either path (1, 2, 3, 4 or anything else; and 5 in the stopgap, which sends no command): one `work:` line with ADE's first stderr line and the hint `inside ADE bin/work never opens a window; for one, run bin/work <folder> from a terminal outside ADE`; the launcher and settings are removed; `bin/work` exits with ADE's code. No window.
5. **`AGENT_TERMINAL=terminal|iterm`**: exit 2, before any probe: `work: AGENT_TERMINAL=<v>: inside ADE every session opens in ADE; run bin/work from a terminal outside ADE for a window`. `AGENT_TERMINAL=ade` (or any other value) is the same as unset.
6. **`WORK_DRY=1`**: prints the command line as today, then two `work:` lines with the typed-command `open` and the stopgap `open`. Never calls the helper (no `help`, no `open`).

Outside ADE: unchanged (Terminal or iTerm window; `AGENT_TERMINAL=ade` is exit 2).

## Acceptance criteria

All in `tests/test_ade_open.sh`. The `osascript` stub logs any call made with the four ADE variables set to `$S/osa.inade`, and the runner fails the check that caused it ("osascript ran inside ADE"), so no check can pass if a window was opened inside ADE.

| AC | Criterion | Automated test |
|---|---|---|
| C6a | Exit 1: exit 1, no window, one `work:` line with ADE's reason and the outside-ADE hint, never `AGENT_TERMINAL=terminal`. | `exit_1_refuses_with_a_hint_and_opens_no_window` |
| C6b | Exit 3 and 4: exit 3 or 4, no window, one `work:` line with ADE's reason and the outside-ADE hint, no launcher or settings left. | `exit_3_4_fail_and_open_no_window` |
| C9 | `AGENT_TERMINAL=terminal|iterm` inside ADE (also with `WORK_DRY=1`): exit 2, the message above, no probe, no open, no window. Outside ADE both still open their window. | `a_forced_window_inside_ade_is_refused` |
| C12 | Dry run inside ADE prints both `open` commands, never the word "window", and never calls the helper. | `dry_run_inside_ade_calls_nothing` |
| C16 | The osascript stub's inside-ADE guard fires inside ADE and stays quiet outside it. | `the_checks_use_only_stubs` |
| C17 | README "Deep work inside ADE" states the no-window rule, the stopgap paste line, the refused forced window and `usage: ade open`; rows `1` and `3`, `4` say no window; no row hints `AGENT_TERMINAL=terminal bin/work`. | `readme_documents_the_ade_path` |
| C18 | cli-4c and cli-near (usage, no capability), auto or `AGENT_TERMINAL=ade`: one probe, one bare `open` with exactly `open --cwd <checkout> --name <folder> --focus`, one `work:` line, exit 0, no window. Hook mode and a hanging `help`: exit 1 within 15 s, no `open`, no window, one line naming `ade open`. Hook mode on a never-closing stdin pipe finishes in under 4 s with exit 1. | `an_ade_without_typed_commands_never_uses_a_window` |
| C20 | Stopgap exit 0 (provider session with a prompt): the paste line names the launcher; launcher and settings are kept; prompt and key are not in the line or the helper argv; running the launcher runs the fake claude and removes both. A `TMPDIR` with a quote and a space is quoted so the line parses to `bash -l <launcher>`. | `the_stopgap_opens_a_bare_sub_terminal_and_prints_the_command` |
| C21 | Stopgap `open` answering 1, 2, 3, 4, 5 or 7: that exit code, one `work:` line with ADE's message and the outside-ADE hint, no paste line, nothing left, no window. | `stopgap_open_failures_never_open_a_window` |
| C22 | Sweep: helper modes cli, cli-4c, hook × `open` answers 0, 1, 3, 5 × `AGENT_TERMINAL` unset, ade, terminal, iterm, other, each run and dry run: `osascript` is never called; a dry run never calls `open`. | `osascript_never_runs_inside_ade` |

W1's other checks (C1 to C5, C7, C8, C10, C11, C13 to C15, C19) are unchanged and still pass.

## Files touched

- `bin/work`: the probe (`ade_level`: command, bare or none), the inside-ADE rules above, the dry-run lines, the header comment.
- `tests/test_ade_open.sh`: the osascript guard, the fake helper refusing `-- COMMAND` in cli-4c/cli-near (as v0.23.0 does), the checks above.
- `README.md`: "Deep work inside ADE" rewritten for the rule; the "Deep work" bullet says "never a window".
- `docs/stories/W1-bin-work-opens-sub-terminals-in-ade.md`: a pointer to this story.
- `.ade/knowledge/developer.md`: one line.

## Verification

Filled by QA only.
