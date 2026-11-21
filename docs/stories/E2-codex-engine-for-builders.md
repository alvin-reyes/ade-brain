# E2: Codex CLI (GPT) as an engine for builders and focus agents

Status: Ready for development (2026-11-21). Risk: high (a second CLI with its own keys, sandbox and data terms).
Owner's decisions (2026-11-21): builders and focus agents can use DeepSeek, GLM, Muse (through Claude Code, as today)
and **GPT**; the orchestrator stays on Claude Code; GPT through the Codex CLI (this story). Depends on E1 (the engine table). Earlier record: ADR 0002 (providers and
engines), `.ade/context/engines.md`, deferred-work "GPT through GPT CLI" (2026-11-19).
Verification command: `bash tests/run.sh`.

## Goal
A role can name `gpt:<model>` (e.g. `HUB_ROLE_BUILDER="gpt:<model> anthropic:opus"`). `bin/work --role`
and `bin/agent --role` then run that work in the **Codex CLI** (OpenAI) inside the same checkout, with the hub's rules, and
with every safety rule the Claude Code path has.

- **Engine table** in `bin/lib.sh`: `claude` (today) and `gpt`. Each engine defines its command, how it gets the
  project rules (Codex: `AGENTS.md`, pointing at `.ade/rules.md`), how the model is
  passed, its approval mode, and how it is signed in.
- **Sign-in:** a ChatGPT account login (the CLI's own) or an OpenAI API key stored with `bin/keys set gpt` and given
  to the CLI only in the way that keeps it out of child processes where the CLI allows; where it does not, document the
  residual risk in engines.md (the builder verifies against the GPT CLI docs at build time).
- **Never yolo:** the CLI's auto-approve-everything mode is refused, like `--dangerously-skip-permissions`.
- **Data sharing:** GPT is opt-in per hub and owner-only by default (`HUB_PROVIDERS_ALLOWED`, `owner_only`), like
  DeepSeek: a customer's hub uses it only when that customer approved it.
- **Gaps stated plainly:** no Claude Code hooks (C6 events), plugins, BMAD skills or Telegram channel in a GPT
  session; the reviewer (Claude Code) still runs the verification command that decides Done.

## Acceptance criteria (`tests/test_engines.sh`, fake `gpt` CLI, no network)
| AC | Criterion |
|---|---|
| 1 | A role entry `gpt:<model>` is accepted by the role table; `bin/roles` shows it with its engine |
| 2 | `bin/work --role builder` with a gpt pick launches the fake `gpt` in the checkout with the model and the rules file, never Claude Code flags |
| 3 | The full-auto, no-sandbox mode (`--dangerously-bypass-approvals-and-sandbox` or equivalent) is refused (argument or setting), exit 2 |
| 4 | No sign-in and no stored key: refused before launch with the `bin/keys set gpt` hint; nothing falls back silently |
| 5 | A stored key reaches only the gpt process, never argv, a file in the repo or a log; a fake child sees it only where engines.md says it must |
| 6 | GPT is refused in a hub that does not allow it (`HUB_PROVIDERS_ALLOWED`) and in a client hub unless enabled |
| 7 | `bin/agent --role` with a gpt pick runs read-only, as the Claude path does |
| 8 | `bin/sessions` shows the engine for a gpt session; `bin/dispatch` can start a gpt builder |
| 9 | engines.md and ADR 0002 record the GPT engine, its sign-in, its data terms and its gaps |
