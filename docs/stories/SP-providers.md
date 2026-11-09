# SP: DeepSeek, GLM and Meta (Muse) as providers behind Claude Code

Status: **BLOCKED on S0 item 21** (the owner's API keys, and the compatibility and behaviour checks). Do not start the build
until every box in the prerequisite checklist is ticked with its answer recorded in `.ade/context/engines.md`.
Source: `docs/plans/2026-11-09-other-ai-cli-agents.md`, section "Providers: DeepSeek, GLM and Meta Muse behind Claude Code
(story SP)", the final approved text (after review). Where this story and the plan differ, the plan wins; stop and ask.
Verification command: `bash tests/run.sh` (architecture verification command, `docs/architecture.md`).

## Prerequisite checklist: S0 item 21 (Claude only, owner's keys)

Each item is answered on the current Claude Code and recorded in `.ade/context/engines.md`. Tick a box only with that answer.

- [ ] **Auth variable:** `ANTHROPIC_AUTH_TOKEN` versus `ANTHROPIC_API_KEY`, per provider.
- [ ] **Credential option, in this order (first that passes wins):**
  1. [ ] `apiKeyHelper` in a provider settings layer calling `bin/secret <name>`. Check it sends the auth header each endpoint expects.
  2. [ ] Subprocess environment scrub (Claude Code's current setting name recorded), so hooks, Bash tool commands and MCP servers
         do not receive `ANTHROPIC_AUTH_TOKEN`.
  3. [ ] Neither works: the key goes in `ANTHROPIC_AUTH_TOKEN`; the exposure is written into ADR 0002 as an owner decision and the README says so.
  - [ ] Proof for the chosen option: a hook and a Bash tool command that try to read the token must not see it.
- [ ] **`apiKeyHelper` failure after startup** (Keychain locked after sleep): Claude Code errors and does not fall back to the
      OAuth login against the third-party URL. If it falls back, option 1 is rejected.
- [ ] **No Anthropic credential:** with a valid key the endpoint receives no Anthropic credential header; an existing Anthropic login
      neither interferes nor gets sent.
- [ ] **`/model` leak:** whether `/model` writes a provider model id into shared user settings (breaking the next Anthropic session).
- [ ] **`--resume` leak:** whether `--resume` of an Anthropic session under a provider sends its history to the provider.
- [ ] **Settings precedence:** whether the provider layer's `env` wins over an `env` block in the checkout's or the user's settings.
      If not, provider sessions are refused in a checkout whose `.claude/settings*.json` sets `ANTHROPIC_BASE_URL` (AC7 becomes live).
- [ ] **Remote Control** and **thinking budgets** (`--effort`) through each endpoint.
- [ ] **Behaviour, not just errors:** a canary instruction in the system prompt or rules is obeyed; a forced tool call happens; a deny
      rule is respected. A provider that fails any of these gets a no-go for delegation.
- [ ] **Model IDs and slot mapping** per provider, from the vendor's own Claude Code guide (DeepSeek, z.ai). Plan values are starting points.
- [ ] **Unsupported features** through each endpoint (tool use, images, extended thinking, web search, prompt caching, token counting),
      and how Claude Code fails when used.
- [ ] **Hooks and `--agents`** still work through each endpoint.
- [ ] **Bad key:** the exit code Claude Code returns.
- [ ] **Nonessential traffic:** any remaining Anthropic data path with `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` (WebFetch domain
      checks, server-side tools). List them.
- [ ] **Meta, from Meta's own developer docs, before any request carries the key:** the host, path and model IDs (the plan's `api.meta.ai`
      and `muse-spark-1.3` are third-party sourced); every Claude Code request field the endpoint rejects or ignores.
      The `meta` row ships in SP only if at least one feature has a go; otherwise `meta` moves to a later story.
- [ ] **Feature go/no-go, per provider per feature** (focus session, `--agents` sub-agents, delegation), recorded in `.ade/context/engines.md`
      and mirrored in the machine-readable table in `bin/lib.sh` (SP builds the table from these answers).
- [ ] **Tool restriction:** if S0 finds one is needed, the `--allowedTools` set for that provider is written down (AC19).
- [ ] **Owner decision:** per hub, the client's code and the hub's notes go to DeepSeek, Zhipu and Meta. Recorded in ADR 0002 with each
      vendor's API terms on training and retention of inputs.

## Goal

A hub can run a Claude Code focus session, or Claude sub-agents, against DeepSeek, GLM or Meta instead of Anthropic. The CLI stays
Claude Code, so the hub's hooks, `--agents` and session end keep working. Only the provider behind it changes.

## Scope (SP only)

1. **Provider table in `bin/lib.sh`.** Ids: `anthropic` (default, Claude Code's own login), `deepseek`, `glm`, `meta` (`meta`, not
   `muse`, so it is not confused with the `muse` CLI login or muse.ai). Each row: base URL, Keychain secret name, default model slots,
   and a go/no-go per feature. Rows: deepseek `https://api.deepseek.com/anthropic` / `deepseek-api-key`; glm
   `https://api.z.ai/api/anthropic` / `zai-api-key`; meta `unconfirmed` (host from Meta's docs in S0 item 21) / `meta-model-api-key`
   (doctor label "Meta Model API key"). Model values are confirmed by the checklist, not copied from the plan.
2. **Choosing a provider.**
   - `HUB_PROVIDER` (sessions, default `anthropic`) and `HUB_PROVIDERS_ALLOWED` (default `anthropic`), read only from `hub.conf`, unset
     before sourcing (`bin/lib.sh:47`), like `HUB_ENGINES_ALLOWED`. A provider not in the list exits 2.
   - `bin/work --provider <p> <folder>` for one session; `--model` is that provider's model name.
   - `HUB_<P>_MODEL` and `HUB_<P>_SMALL_MODEL` override the row's defaults per hub, and are checked like `--model` (a slot alias or an
     id from the row); a stale value exits 2 at launch.
   - Agent front matter `provider:` is read by `bin/work` for the `--agents` check only. Delegation through `bin/agent` is S3a.
   - **No base URL override.** Base URLs live only in the table; there is no `HUB_<P>_BASE_URL`, now or later.
3. **How a session starts** (`bin/work`, in the launch environment and settings only):
   - Endpoint and models from the row: `ANTHROPIC_BASE_URL`, `ANTHROPIC_MODEL`, slot variables (`ANTHROPIC_DEFAULT_OPUS_MODEL`,
     `ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL`, `ANTHROPIC_SMALL_FAST_MODEL`), and
     `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`. `CLAUDE_CODE_SUBAGENT_MODEL` is **not** set.
   - **One merged settings file.** The provider layer (`apiKeyHelper` and the base URL and slot variables in its `env` block) is merged
     with the folder's `.claude/settings.json` into one generated temp file passed as the single `--settings`, so the folder's hooks are kept.
   - **Key:** by the credential option chosen in the checklist. The launcher file holds the `bin/secret` call, never the key; the key never
     goes in argv or a file.
   - **Fail closed:** the launcher reads the key (or runs the helper once as a check) before starting Claude Code. If `bin/secret` fails or
     prints nothing (missing key, locked Keychain, denied prompt), it prints the `bin/secret --set <name>` hint and exits non-zero. Claude Code
     never starts against a third-party base URL without that provider's key.
4. **Remote Control off** for every provider other than `anthropic`. `--provider` implies `--no-remote`.
5. **Models in a provider session:** `HUB_MODEL` is not passed to a provider session (it may be a full Anthropic id). `--model` must be a
   slot alias (`opus`, `sonnet`, `haiku`) or an id from the row; anything else exits 2. `--effort` is refused unless the checklist's
   thinking-budget answer is a go for that provider.
6. **Wrappers.** `--provider` other than `anthropic` needs plain `claude`. If the resolved command is anything else, whichever source set it
   (`--claude`, `HUB_CLAUDE` or `AGENT_CLAUDE`), exit 2.
7. **Feature go/no-go, enforced in `bin/work`.** `bin/work --provider p` for a feature (focus session, `--agents`) that the table marks no-go
   for p exits 2, naming the S0 finding. (The same check in `bin/agent` is S3a.) If a tool restriction is needed, it is a `--allowedTools`
   value in the row, applied by `bin/work`, not a README sentence.
8. **`--agents` provider check** in `bin/work`'s agent JSON step: an agent with no `provider:` inherits the session's provider and stays
   (under the model rule in Scope 5); an agent whose `provider:` names the same provider stays; one naming a different provider is left out
   of `--agents` and listed as delegatable.
9. **Doctor:** one row per allowed provider, `OK` or `MISSING`, showing the Keychain secret **name** and whether it is stored. Never the
   value. `bin/doctor --deep` endpoint checks are S0's and S3a's, not SP's.
10. **README:** a provider section: how to choose, `bin/secret --set deepseek-api-key` (and the other names), Remote Control off, the wrapper
    rule, the data-sharing note, and the exposure statement for the chosen credential option.
11. **ADR 0002, provider section.** `.ade/context/decisions/0002-*.md` does not exist yet (only `0001-auto-sync-on-by-default.md`). S2a
    plans to create ADR 0002 for engines. Whichever story lands first creates it; the other appends its own section. Check with the
    architect before creating a second `0002`.

## Out of scope

- `bin/agent`, delegation, its env handling, its fail-closed key read, its no-go check and its `provider:` handling (S3a).
- `bin/doctor --deep` requests and the behavioural canary per provider (S0 item 21 and S3a).
- `bin/briefing` (stays on Anthropic).
- Codex and Gemini engines.
- Any `HUB_<P>_BASE_URL` override (never).
- Unofficial bridges that drive a muse.ai browser session (never).
- Storing any key in the hub, `hub.conf`, the launcher file, argv or a file.

## Acceptance criteria

All checks live in `tests/test_providers.sh` (new), using `make_hub` from `tests/helpers.sh`. Hermetic rule (plan): `tests/run.sh` never
runs the real `claude` and never calls a vendor. Every provider check sets `AGENT_CLAUDE` to a fake that records its argv, its selected
env names and a marker file, and puts a `security` stub (as in `tests/test_secret.sh`) and an `osascript` stub on PATH. Each provider test
asserts the fake was the engine that ran.

| AC | Criterion | Automated test |
|---|---|---|
| AC1 | Static, over **every** row in the table: no base URL ends in `/v1` or `/`, and every row has a Keychain secret name. | `provider_rows_static` |
| AC2 | One dry-run case per row (deepseek, glm, and meta if its row ships): `WORK_DRY=1 bin/work --provider <p> projects/demo` prints that row's base URL exactly, the slot variable names and `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, and no key value (the stub's secret is absent from the output). | `dry_run_each_row` |
| AC3 | A non-dry run writes a launcher file that contains no key value and no literal `ANTHROPIC_AUTH_TOKEN=` assignment. | `launcher_file_holds_no_key` |
| AC4 | The fake engine's argv contains no key value. | `engine_argv_holds_no_key` |
| AC5 | Fail closed: with a `bin/secret` stub that exits 1, and another that prints nothing, `bin/work --provider glm` exits non-zero, prints the `bin/secret --set` hint, and the fake engine never runs (its marker is absent). | `fail_closed_on_missing_key`, `fail_closed_on_empty_key` |
| AC6 | One merged settings file: the `--settings` path in the launch command is a single generated file, and it contains both the folder's hook entries (from `projects/demo/.claude/settings.json`) and the provider layer (`apiKeyHelper` or `env`), with no key value. | `single_merged_settings_keeps_hooks` |
| AC7 | Settings precedence (live only if the checklist says the provider layer's `env` does **not** win): with `ANTHROPIC_BASE_URL` set in the checkout's `.claude/settings.json`, `bin/work --provider glm` exits 2. Skipped with a recorded reason if the checklist says it wins. | `checkout_base_url_conflict_refused` |
| AC8 | `--provider glm` implies `--no-remote`: the dry-run command has no `--remote-control`. | `provider_implies_no_remote` |
| AC9 | Wrapper refusal from each source: `--claude <wrapper>`, `HUB_CLAUDE=<wrapper>` and `AGENT_CLAUDE=<wrapper>` each with `--provider glm` exit 2; plain `claude` from any one of them is accepted. | `provider_rejects_wrapper_from_each_source` |
| AC10 | Model rules: a slot alias (`sonnet`) and a row id are accepted; a full Anthropic id (for example `claude-sonnet-4-5`) exits 2; `HUB_MODEL=<anthropic id>` in `hub.conf` is not passed to a provider session. | `provider_model_rules`, `hub_model_not_passed` |
| AC11 | `--effort high` with a provider exits 2 unless the table marks that provider's thinking budgets as a go. | `provider_effort_refused` |
| AC12 | `HUB_GLM_MODEL` and `HUB_GLM_SMALL_MODEL` in `hub.conf` replace the row's model and small-model slot in the dry-run output; a stale value (not a slot alias or a row id) exits 2 at launch. | `hub_provider_model_override`, `hub_provider_model_checked` |
| AC13 | No base URL override: `HUB_GLM_BASE_URL` in `hub.conf` and in the environment does not change `ANTHROPIC_BASE_URL` in the dry-run output. | `no_base_url_override` |
| AC14 | `HUB_PROVIDER` and `HUB_PROVIDERS_ALLOWED` are read only from `hub.conf`: setting them in the environment changes nothing; `--provider p` with `p` not in `HUB_PROVIDERS_ALLOWED` exits 2. | `provider_env_not_trusted`, `provider_not_allowed` |
| AC15 | Go/no-go refusal: in the hub's copy of `bin/lib.sh`, the test edits the table to mark `glm` no-go for focus sessions; `bin/work --provider glm` exits 2 with a message naming the S0 finding. The unedited table permits the go cases in AC2. | `no_go_pair_refused_by_work` |
| AC16 | `--agents` provider check: in a folder with three agents (no `provider:`; `provider: glm` on a glm session; `provider: deepseek` on a glm session), the `--agents` JSON keeps the first two, omits the third, and the dry-run names the omitted agent as delegatable. | `agents_provider_check` |
| AC17 | `bin/doctor` (with `DOCTOR_OFFLINE=1`) prints one provider row per allowed provider, showing the secret name and `OK` or `MISSING`, and never the stub's secret value. | `doctor_provider_rows_name_only` |
| AC18 | The `meta` row ships only with a go: if the table has a `meta` row, at least one of its features is a go in the table and in `.ade/context/engines.md`; if it has none, `meta` is absent from the table and from the README. | `meta_row_only_with_a_go` |
| AC19 | Tool restriction (live only if the checklist names one): the row's `--allowedTools` value appears in the dry-run command for that provider. Skipped with a recorded reason otherwise. | `allowed_tools_applied` |
| AC20 | Static: `README.md` has a provider section containing `--provider`, `bin/secret --set deepseek-api-key`, that Remote Control is off, the data-sharing note, and the exposure statement for the chosen credential option. | `readme_provider_section` |
| AC21 | Static: ADR 0002 has a provider section recording the credential option, the per-hub data-sharing decision and the vendors' API-terms note. | `adr_0002_provider_section` |
| AC22 | Scope guard: `bin/briefing` is unchanged (no diff against the story's base), and `bin/agent` does not exist after SP. | `scope_guard_briefing_and_agent` |
| AC23 | Hermetic guard: each provider check asserts the fake `AGENT_CLAUDE` was the engine that ran, and no provider check sets `AGENT_CLAUDE` to the real `claude`. | `hermetic_fake_engine_only` |
| AC24 | Existing suites still pass: `tests/test_work.sh`, `tests/test_doctor.sh`, `tests/test_secret.sh`, `tests/test_models.sh`, `tests/test_briefing.sh`. | existing files, run by `tests/run.sh` |

Not tested in `tests/run.sh` (they belong to S0 item 21 and S3a): the canary behaviour, the real `claude` against a fake
Anthropic-compatible server, the `apiKeyHelper` failure after startup, and `bin/agent`'s fail-closed read and no-go check.

## Test notes (TDD order)

1. Write `tests/test_providers.sh` with AC1 first (static, fails until the table exists), then AC2 to AC4 (the dry run and launcher).
   Confirm each fails for the right reason before the code exists.
2. AC5 (fail closed) and AC6 (merged settings), then AC8 to AC14 (option rules), AC15 (go/no-go), AC16 (`--agents`), AC17 (doctor).
3. AC18 to AC21 are static checks; write them before the README and ADR text, so they fail first.
4. AC7 and AC19 are conditional on S0 answers; record the skip reason in the test output, never silently pass.

Test fakes: `tests/test_secret.sh`'s `security` stub; `WORK_DRY` for the dry run; a bash fake engine that writes its argv and selected
env names to a file and creates a marker.

## Files touched

- `bin/lib.sh`: provider table (with the go/no-go per feature), `HUB_PROVIDER` and `HUB_PROVIDERS_ALLOWED` added to the
  unset-before-sourcing list (before `bin/lib.sh:47`), helpers. Shared with S1 and S2a; S2a extends the same list, not a second mechanism.
- `bin/work`: `--provider`, provider environment, merged settings file, fail-closed key check, `--no-remote` implication,
  model/wrapper/effort rules, go/no-go check, `--agents` provider filter.
- `bin/doctor`: one row per allowed provider (name and presence only).
- `README.md`: provider section.
- `.ade/context/decisions/0002-*.md`: provider section (created here only if S2a has not landed).
- `tests/test_providers.sh`: new.
- `docs/stories/SP-providers.md`: this file. The Verification section is filled by QA only.

Not touched: `bin/agent` (S3a), `bin/briefing`, `bin/session-end`, `bin/sync`, `bin/changes`, `tests/run.sh`.

## Dependencies and shared contracts

- **Blocked on S0 item 21.** It supplies the credential option, the settings-precedence answer, the per-feature go/no-go, the
  thinking-budget answer, the model IDs, the Meta host, and `.ade/context/engines.md`, which SP reads and does not write.
- Shared with S1: `bin/lib.sh` (see Files touched). Coordinate the `hub.conf` unset list with S2a.
- Shared with S3a: the provider table and the go/no-go table. S3a's `bin/agent` must read the same rows, not a copy.
- Shared with S2a: ADR 0002 (see Scope 11).

## Coding standards

- Bash 3.2 compatible (macOS `/bin/bash`).
- A secret goes to stdout only through `bin/secret` inside `$(...)` at the point of use: never in argv, a file, the launcher, a commit,
  a log or a URL.
- The test value of the `security` stub must not appear in any output or file a test writes; the tests assert this.
- No real vendor call and no real `claude` in `tests/run.sh`.

## Verification

Command: `bash tests/run.sh` (must print `ok    test_providers.sh` and every existing test file as `ok`, and exit 0).

Real output recorded by QA:

_(empty; QA fills this in. Dev agents do not write here.)_
