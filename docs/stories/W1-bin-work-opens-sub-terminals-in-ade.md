# W1: bin/work opens sub-terminals in ADE

Status: **built; in review** (PR #11, branch `w1-bin-work-ade`). Owner's intent (2026-11-09): "when the developer uses ADE, it starts a claude code session. On the claude code session, developer can spawn focus work using our ai-agent template `bin/work` … terminals should spawn INSIDE ADE … it needs to open a sub tab with the main persona open too … `bin/work` starts the session in it."

Verification command: `bash tests/run.sh` (`docs/architecture.md`, "Verification command"). Changing it needs the owner's approval.

## Goal

Inside an ADE terminal, `bin/work <folder>` opens the deep-work session as a **sub-terminal of the caller's tab** in ADE, not as a new Terminal.app or iTerm window. Outside ADE nothing changes.

The session is started by the same launcher file `bin/work` writes today. Inside ADE, the launcher's path is the one command ADE types into the new sub-terminal:

```
"$ADE_HOOK_BIN" open --cwd <checkout> --name <folder> --focus -- bash -l <launcher>
```

`bash -l` is what the Terminal path already runs (`osascript … do script "bash -l $L"`), so the launcher runs the same way in both places.

## Dependencies (none blocks the build)

- **Build and tests:** none. Every test uses a fake `$ADE_HOOK_BIN` on `PATH` that records its argv and returns the exit code the test sets. Real ADE, real `claude`, real `osascript` and the real Keychain are never run.
- **Live flow:** needs ADE's `ade open` on the ADE build, from stories 4a and 4c (PRs #96 and #97 in `better-agentic-ide`, still open on 2026-11-09), and the typed command from story 9 (`ade open -- COMMAND`, in refinement). Until story 9 is on the build, ADE's `help` has no `capabilities: command` line, so `bin/work` opens a Terminal window with one `work:` line (criterion C18), on builds with or without `ade open`. Story 9 adds that line.
- **ADE story 9, task T10** (the ADE side has been told, 2026-11-09): `ade help` must print the `capabilities:` line on **stdout**, at **column 0**, and exit **0**. `bin/work` reads only stdout (stderr goes to `/dev/null`), matches `^capabilities:` and ignores the exit status, so a line on stderr or an indented one leaves every session in a window (C18).

## Decisions (made here, reviewable)

- **Detection.** Inside ADE means all four are set: `ADE_HOOK_BIN` (an executable file), `ADE_HOOK_PORT`, `ADE_HOOK_TOKEN` and `ADE_PTY_ID` (non-empty). The owner named `ADE_HOOK_BIN` and `ADE_PTY_ID`. The other two are required too, because `ade open` exits 3 without them, so a partial environment would always fall back. Claude Code's Bash tool inherits all four from an ADE terminal.
- **Focus.** The sub-terminal is opened with `--focus`. ADE's default is to add it in the background (U1); `bin/work` is a deliberate launch, and the Terminal path activates its window, so `--focus` is the equivalent.
- **Name.** `--name` is the folder's basename, `${F##*/}`, the name Remote Control already uses (`projects/acme` → `acme`). `bin/work` has no agent name at launch (agents are chosen inside Claude Code), so the folder is the name.
- **Exit codes from `ade open`.** Per the contract in ADE's `.ade/context/terminal-open.md`:
  - **0** (opened, command typed): done. `bin/work` exits 0 and the new shell runs the launcher.
  - **5** (opened, not typed): **no fallback.** A shell is already open, so a second session would duplicate it. `bin/work` prints the one command the user runs in the new sub-terminal, `bash -l <launcher>`, and exits 5. The launcher is kept for that run.
  - **1** (ADE refused: an error, the sub-terminal cap, an ADE too old, or no answer in time): **no window** (owner decision, 2026-11-09: inside ADE, `bin/work` never opens a window outside ADE because ADE refused). `bin/work` prints ADE's error and the hint `AGENT_TERMINAL=terminal bin/work <folder>` to open a window instead, and exits 1. The EXIT trap removes the launcher.
  - **3, 4** (ADE unreachable: stale variables, for example under tmux; connection refused; the terminal is gone): **fall back** to the Terminal window, with one warning line. The contract says these answers open nothing, so there is no duplicate.
  - **Any other code** (outside the contract): fail with that code, no window.
- **An ADE that cannot type the command** (2026-11-09, from the owner's rule and the onboarding PRD review). Before `open`, `bin/work` runs `"$ADE_HOOK_BIN" help </dev/null` under lib.sh's `timeout 5` and ignores its exit status. The probe runs only after the arguments and the folder are checked, so a typo'd folder fails at once, without probing (C19). It uses the ADE path only when the output has a line starting `capabilities:` that contains the word `command` (`capabilities: command`, or `capabilities: command split` on a later build). Story 9 adds that line to ADE's help.
  - Otherwise `bin/work` behaves as outside ADE: one `work:` info line, then a window. With `AGENT_TERMINAL=ade` it is exit 2. A dry run does not probe.
  - This covers a build without `ade open` (such as v0.22.0: hook mode reads stdin to its end, so the probe's stdin is `/dev/null`, then answers `{}` and 0 to anything, so `open` would silently do nothing), stories 4a/4c without 9 (`-- CMD` is exit 1, which would open nothing under the owner's rule), and a helper that does not answer within 5 seconds.
  - **2** (usage: our own argument or a bad `--cwd`): **fail**, exit 2, nothing opened. Falling back would hide a bug in `bin/work`.
- **Forced values.** `AGENT_TERMINAL=terminal` and `=iterm` always use a window, even inside ADE. `AGENT_TERMINAL=ade` always uses ADE: inside ADE it never falls back (exit 1, 3 or 4 is returned as is); outside ADE, or on an ADE without `capabilities: command` (C18), it is exit 2 with a message. An unset or unrecognised value is "auto": ADE inside ADE, a window outside (an unrecognised value used to mean a window; inside ADE it is now auto, and this is the only change of behaviour outside a forced value).
- **Launcher lifetime.** `bin/work`'s EXIT trap removes the launcher and the merged settings file (`MS`) unless they were handed off. A hand-off happens when ADE has typed the command (exit 0) or when the user has been told to run it (exit 5). After a hand-off, `bin/work` never deletes them, because the new shell still needs them. The launcher removes itself when it exits, as today.
- **Nothing sensitive on the command line.** The typed command is `bash -l <path>`. The prompt, the agents JSON, the `claude` arguments and the provider settings stay inside the launcher file (as today), never in ADE's argv or the typed line.

## Acceptance criteria

All checks live in `tests/test_ade_open.sh` (new), using `make_hub` from `tests/helpers.sh`. Every check runs under `env -i` with `HOME` and `TMPDIR` in temp dirs, and a stub directory first on `PATH`. The stub directory holds `ade-hook` (the fake `$ADE_HOOK_BIN`), `osascript` (records argv), `security` (provider cases only, as in `tests/test_providers.sh`) and `claude` (a fake, for the launcher-run case only). Nothing else reaches a real tool.

| AC | Criterion | Automated test |
|---|---|---|
| C1 | Inside ADE means all four variables are set and `ADE_HOOK_BIN` is executable. Each missing or empty one, on its own, gives the window path, and the fake helper is never called. | `ade_is_detected_only_with_all_four` |
| C2 | Inside ADE, `bin/work <folder>` calls `"$ADE_HOOK_BIN" open --cwd <checkout> --name <folder> --focus -- bash -l <launcher>` exactly once and opens no window (`osascript` is not called). `<checkout>` is the resolved `$dir` from `ACCESS.md`. | `inside_ade_opens_one_sub_terminal_and_no_window` |
| C3 | `--name` is the folder basename, also for a trailing slash (`projects/demo/` → `demo`). `--cwd` is the repo checkout, or the hub folder for a folder with no repo. | `name_is_the_folder_and_cwd_is_the_checkout` |
| C4 | The launcher written inside ADE is byte-identical to the one written for a window, for the same arguments (the osascript stub copies it). It passes `bash -n` and starts with `#!/bin/bash` and the same `trap`. | `ade_and_window_launchers_are_identical` |
| C5 | Exit 0: `bin/work` exits 0, does not delete the launcher or the merged settings file (provider case), and running the launcher (`bash "$L"`, with the fake `claude` first on `PATH`) runs the fake and then removes both files. | `exit_0_keeps_the_launcher_until_the_shell_runs_it` |
| C6a | Exit 1: `bin/work` exits 1, never calls `osascript`, and prints exactly one stderr line starting `work: ` with ADE's error (the first line of ADE's stderr only: the fake prints the reason and then a usage block, which never shows) and the hint `AGENT_TERMINAL=terminal bin/work <folder>`. No launcher is left. A TMPDIR with a non-ASCII character gives 422 from ADE, which is exit 1, with the same result. | `exit_1_refuses_with_a_hint_and_opens_no_window` |
| C6b | Exit 3 and 4 each open a Terminal window (`osascript` called once with `do script "bash -l <launcher>"`, then `activate`), print exactly one stderr line starting `work: ` (ADE's first stderr line only, never its usage block), and exit 0. | `exit_3_4_fall_back_to_one_window_with_one_warning_line` |
| C7 | Exit 5: `bin/work` exits 5, prints on stderr one line naming the reason and the command `bash -l <launcher>` to run in the new sub-terminal, keeps the launcher and the settings file, and opens no window. | `exit_5_prints_the_command_and_keeps_the_launcher` |
| C8 | Exit 2: `bin/work` exits 2, opens no window, prints one `work:` line with ADE's first stderr line only (never its usage block), and leaves no launcher or settings file (the EXIT trap removes them). An exit outside the contract does the same with its own code. | `exit_2_fails_and_opens_nothing` |
| C9 | `AGENT_TERMINAL=terminal` and `AGENT_TERMINAL=iterm` open a window even inside ADE, and the fake helper is never called. An unrecognised value inside ADE is auto: the ADE path, with the C2 argv. | `a_forced_window_never_calls_ade`, `an_unrecognised_value_inside_ade_is_auto` |
| C10 | `AGENT_TERMINAL=ade` inside ADE: exit 1 (or 3, 4) is returned, with its message, and no window opens. `AGENT_TERMINAL=ade` outside ADE: exit 2 with a message naming the four variables, no window, no helper call. | `forced_ade_never_falls_back`, `forced_ade_outside_ade_is_exit_2` |
| C11 | Outside ADE nothing changes: the window path runs with the same `osascript` argv as today, the helper is never called, and `tests/test_work.sh` and `tests/test_providers.sh` pass unchanged. | `outside_ade_is_the_window_path_unchanged` (plus the two existing files, unedited) |
| C12 | Dry run inside ADE (`WORK_DRY=1`): prints the same command line as today, prints on stderr `work: if this ADE lists capabilities: command, this runs: ` and the ADE argv it would use, and does not call the helper or `osascript`. No launcher is left behind. | `dry_run_inside_ade_calls_nothing` |
| C13 | Provider session under ADE (`--provider deepseek`, with the same stubs as `tests/test_providers.sh`): the helper's argv contains the launcher path and none of the key value, the settings file path, the `--prompt` text or `ANTHROPIC_`. The launcher contains the `env -u` scrub and `CLAUDE_CONFIG_DIR`. | `provider_session_under_ade_passes_only_the_launcher_path` |
| C14 | A non-interactive run: `bin/work` under `bash --noprofile --norc`, stdin from `/dev/null`, stdout to a pipe, no TTY, inside ADE, exits 0 on exit 0. (This is the owner's case: a Claude Code Bash tool calls `bin/work`.) | `runs_from_a_non_interactive_shell_without_a_tty` |
| C15 | A prompt containing spaces, quotes, `$`, backticks and a newline appears in the launcher file only: never in the helper's argv or `bin/work`'s stderr. stdout keeps today's full-command echo (owner decision 2026-11-09). | `prompt_stays_out_of_the_typed_command` |
| C16 | Hermetic: the test checks that `command -v osascript`, `command -v security` and `command -v claude` resolve to the stubs, and that `ADE_HOOK_BIN` is the fake. | `the_checks_use_only_stubs` |
| C18 | The ADE path needs a `help` line starting `capabilities:` with the word `command`. Each of a hook-mode helper (reads stdin to its end, `{}`, exit 0), a CLI helper whose help has no such line (stories 4a/4c), a near miss (`capabilities: commands split`, or an indented `capabilities: command`), and a helper whose `help` never answers: `bin/work` never calls `open`, probes once, opens one window, prints one `work:` line, exits 0 within 15 seconds; with `AGENT_TERMINAL=ade` it exits 2, names the capability, opens nothing. A helper printing `capabilities: command` or `capabilities: command split` takes the ADE path. The hook-mode helper with stdin on a pipe that never closes (a Claude Code Bash tool) and a GNU-style `timeout` (a fake that runs the command in the foreground, so it inherits stdin) finishes in under 4 seconds: the probe never reads `bin/work`'s stdin. | `an_ade_without_typed_commands_uses_the_window` |
| C19 | The probe runs after the arguments and the folder are checked: a typo'd folder, inside ADE with a helper whose `help` never answers, auto or `AGENT_TERMINAL=ade`, exits 2 with the usage line in under 4 seconds, without probing, opening or a window. | `a_bad_folder_fails_before_the_probe` |
| C17 | README: a section "Deep work inside ADE" lists the detection rule, the four exit codes and what each does, `AGENT_TERMINAL=ade`, and that the sub-terminal needs ADE's `ade open` (and its typed command) on the ADE build. The section's exit-code table is checked for its six rows (`0`; `1` with the hint; `3`, `4`; `2`; `5`; any other), and the section explains the `ade help` probe. | `readme_documents_the_ade_path` |

## Test notes (TDD order)

1. Write `tests/test_ade_open.sh` with the stubs and C1 first (fails until detection exists), then C2 and C3 (the argv), C4 (identical launchers).
2. C5 and C8 (hand-off and trap), then C7 (exit 5), then C6 (fallback, one warning line).
3. C9 and C10 (forced values), C11 (outside ADE unchanged, with the two existing files run unedited), C12 (dry run).
4. C13 to C15 (provider, non-interactive, prompt), C16 (stub check), C17 (README text last).

Each check prints its name on failure. A check that cannot run in the environment prints `SKIP: <reason>` and asserts nothing else, never a silent pass.

## Files touched

- `bin/work`: detection (C1); the ADE branch in place of the `osascript` lines at the end (C2, C5, C7, C8, C10, C12); exit-code handling and the one warning line (C6); the header comment and the usage text mention `AGENT_TERMINAL=ade` (C17). The launcher writing, the provider path and the argument parsing do not change.
- `tests/test_ade_open.sh` (new): all checks above.
- `README.md`: the "Deep work inside ADE" section (C17), next to the "Deep work" line.
- `docs/stories/W1-bin-work-opens-sub-terminals-in-ade.md`: this file. The Verification section is filled by QA only.
- `.ade/session.md`: one dated line when the story is sharded and one when it is Done (the hub's journal rule).

Not touched: `bin/lib.sh`, `bin/monitor`, `bin/briefing` (their `osascript` notifications are not terminal launches), `tests/test_work.sh`, `tests/test_providers.sh` (read only, as the stub pattern), any ADE code (it lives in `better-agentic-ide`).

## Coding standards

- Bash 3.2 compatible (macOS `/bin/bash`): no associative arrays, no `mapfile`, no `read -t`.
- The helper is called with exactly the argv listed under Goal, in that order, and nothing else. Its stdout is discarded; its stderr is captured by command substitution and only its first line is folded into the one warning. A secret never goes to argv, a file that is not the launcher, or the output.
- Keep `WORK_DRY=1`, `AGENT_TERMINAL=iterm` and the no-ADE output identical to today (C11, C12).
- No `tty`, `read` or `[ -t 0 ]` anywhere in the ADE path: it must not need a terminal (C14).

## Dependencies and shared contracts

- **ADE contract:** `.ade/context/terminal-open.md` in `better-agentic-ide` (exit codes 0 to 5; the four variables; `--cwd`, `--name`, `--focus`, `-- COMMAND`). This story reads it and does not write it.
- **Remote Control name:** `${F##*/}` (the folder), as in `bin/work` today. Unchanged.

## Open before Done

1. Resolved: `--focus` is always passed; ADE honours it by its own rule (only when the caller's tab is the active tab; it never switches tabs, exit 0 either way). The fallback rule was decided on 2026-11-09: exit 1 gives no window; 3 and 4 fall back.
2. Live check on the owner's Mac, once ADE has story 9 on its build: from a Claude Code session in an ADE terminal, `bin/work projects/<folder>` opens a sub-terminal in the tab, the session starts in it, and the caller session keeps running. This is a manual check and does not gate Done.
3. The ADE team's build with story 9 is the one that makes the live flow work; until it is installed, the live run opens a Terminal window with one `work:` line (C18), which is the expected result.

## Verification

```
bash tests/run.sh
```

Plus: every check named in C1 to C19 appears by name in the output of `tests/test_ade_open.sh` and passes, and `tests/test_work.sh` and `tests/test_providers.sh` pass unedited.

## Verification (QA)

_Empty until QA runs the verification command against the story's work. QA records the real output here._
