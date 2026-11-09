# SP: DeepSeek behind Claude Code (GLM disabled, Meta left out)

Status: **QA passed, awaiting code review (2026-11-09); not Done.** Earlier: approved by the owner 2026-11-09, in build. Owner rule added the same day: DeepSeek only in the owner's own hubs
(AC31 to AC34).

Earlier status: **UNBLOCKED for DeepSeek** (2026-11-09). S0 item 21 answered for `deepseek` in `.ade/context/engines.md`: focus session,
`--agents`, delegation and `--effort` are go. `glm` ships disabled (no-go in the table, refused with the S0 reason). `meta` is
left out of SP (plan AC18: no feature has a go). The build can start now. Open owner items are listed under "Open before Done".

Source: `docs/plans/2026-11-09-other-ai-cli-agents.md`, section "Providers: DeepSeek, GLM and Meta Muse behind Claude Code
(story SP)", revision 7. Where this story and the plan differ, the plan wins; stop and ask.
Verification command: `bash tests/run.sh` (architecture verification command, `docs/architecture.md`).
Findings: `.ade/context/engines.md` (S0 item 21). SP reads it and does not write it.

## Prerequisite checklist: S0 item 21 (Claude only)

Each box is ticked only with the answer recorded in `.ade/context/engines.md` (section named in brackets). "OPEN" means not
answered here and not a build blocker unless stated.

- [x] **Auth variable.** DeepSeek: `ANTHROPIC_AUTH_TOKEN` per DeepSeek's Claude Code guide; `ANTHROPIC_API_KEY` and `x-api-key`
      also work per its Anthropic API page. SP does not set either env var (the key comes from `apiKeyHelper`). GLM: `ANTHROPIC_AUTH_TOKEN`
      per docs only. [Auth variable]
- [x] **Credential option 1 (`apiKeyHelper`) chosen.** It passes: DeepSeek accepted it (run d1, exit 0), and it sends
      `Authorization: Bearer` and `x-api-key` (fake server, run t3). Option 2 (`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`) is set as
      defence in depth, not as the mechanism. Option 3 not needed. [Credential option: 1]
  - [x] **Proof for the chosen option.** A `SessionStart` and a `PreToolUse` hook saw `ANTHROPIC_AUTH_TOKEN` and `ANTHROPIC_API_KEY`
        UNSET (real DeepSeek, run d1). A Bash tool `printenv` saw both UNSET (fake server, run t3). A Bash-tool proof against real
        DeepSeek was not run; the fake-server run covers it. [Children don't see the key]
- [x] **`apiKeyHelper` failure after startup.** Claude Code retried with empty credentials, printed "Your apiKeyHelper script is
      failing", exited 1, and did not fall back to the planted OAuth login (run t8). Option 1 is kept.
      Caveats recorded: a cached key keeps working after a helper failure until a 401 forces a refresh (run t6), and a helper that
      fails **at startup** does not fail closed (runs t3a, t5). So the launcher pre-check below is mandatory. [apiKeyHelper failure]
- [ ] **No Anthropic credential.** Passes for the planted file-based OAuth token: it was never sent with `apiKeyHelper`
      (runs t3, t5 to t8), but **was** sent when no key was configured (run t4). The owner's real login lives in the macOS
      Keychain, which was **not** tested.
      **OPEN:** a live check on the owner's Mac before the first real provider session: with `apiKeyHelper` set and the Keychain
      login present, the DeepSeek endpoint must receive no `sk-ant-oat` token. The launcher pre-check stops a session with no key;
      it does not prove the Keychain login stays unsent. Not a build blocker; a Done blocker for the first live use.
- [x] **`/model` leak: confirmed.** `/model deepseek-v4-pro` (interactive, run t14) wrote `{"model": "deepseek-v4-pro"}` to
      `$CLAUDE_CONFIG_DIR/settings.json`. In `-p` mode it writes nothing (run t11). Rule: scope "Provider config dir" below.
      [`/model` leak]
- [x] **`--resume` leak: confirmed.** Resuming an Anthropic session under a second server sent the full prior history
      (run t13). Rule: scope "Resume refused" below. [`--resume` leak]
- [x] **Settings precedence: the provider layer wins.** The `--settings` `env` block beat `ANTHROPIC_BASE_URL` and `ANTHROPIC_MODEL`
      in the user settings, the checkout's `.claude/settings.json` and `settings.local.json` (runs t9_*). A plain process env variable
      loses to the checkout's settings env (run t9_procenv), so the base URL must live in the `--settings` layer.
      Consequence: AC7 is skipped with this reason. Not tested: managed (policy) settings, and the slot variables (only `BASE_URL`
      and `MODEL` were tested in the precedence runs). [Settings precedence]
- [x] **Remote Control.** Not tested; recorded as no (it needs a claude.ai login). SP turns it off for every provider.
      [Remote Control]
- [x] **Thinking budgets (`--effort`).** DeepSeek accepts `adaptive` thinking and `output_config.effort` (runs d2, d3: success).
      Verdict: go for DeepSeek. [Thinking and `--effort`]
- [x] **Behaviour, not just errors (DeepSeek).** A `CLAUDE.md` canary was obeyed (`CANARY-7731`); a forced `Bash` and `Read` call
      happened; a `permissions.deny` rule for `Read(./secret.txt)` was respected (run d1). The Bash write was stopped by Claude
      Code's own permission check, not the model. [Behaviour canaries]
- [x] **Model IDs and slot mapping (DeepSeek).** From DeepSeek's pricing page and its Claude Code guide, checked in run d1-d3:
      main `deepseek-flash`, opus slot `deepseek-v4-pro`, sonnet, haiku and small-fast `deepseek-flash`. `deepseek-v4-flash` is retired
      and not used. The vendor guide's `[1m]` suffix was not tested, so SP does not use it. GLM slots: **unconfirmed** (the z.ai pages
      contradict each other). [Model IDs and slot mapping]
- [x] **Unsupported features (DeepSeek).** Ignored: `anthropic-beta`, `cache_control` (no prompt-cache savings), `top_k`,
      `container`, `mcp_servers`, `citations`. `tool_choice: any` acts as `auto`; a named tool is a 400 in thinking mode. Images
      in assistant messages are a 400. `document` and `redacted_thinking` are unsupported. Web search is billed by DeepSeek. None of
      these broke a run in S0; image, web search and document paths were **not exercised**. [Unsupported features]
- [x] **Hooks and `--agents` (DeepSeek).** Hooks fire (`SessionStart`, `PreToolUse`, runs d1, d2). `--agents` sub-agent with
      `model: haiku` resolved through the slot to `deepseek-flash` and answered (run d2). [Behaviour canaries]
- [x] **Bad key: exit code 1.** Real DeepSeek returned `401 Authentication Fails` after about 3 minutes of retries (run d4).
      The fake server gave a misleading "Not logged in" message (run t10). [Bad key]
- [x] **Nonessential traffic.** From the 2.1.319 binary (not observed on the wire): WebFetch domain pre-check
      (`api.anthropic.com/api/web/domain_info`, turned off by `skipWebFetchPreflight: true`), telemetry (covered by the flag), OAuth
      login flows and desktop redirects. SP sets `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` and `skipWebFetchPreflight: true`.
      Server-side web search goes to DeepSeek, not Anthropic. [Nonessential traffic]
- [ ] **Meta.** Not met for SP. Meta's docs were read (host `https://api.meta.ai`, `POST /v1/messages`, Bearer auth, model IDs
      `muse-spark-1.3` and others are OFFICIAL). But no request was made, and the fields Claude Code sends (`context_management`,
      `output_config`, `thinking: adaptive`) are not confirmed as accepted. No feature is a go, so **`meta` is left out of SP**
      (AC18). Re-open in a later story. [Meta, docs only]
- [x] **Feature go/no-go, per provider per feature.** Recorded in `.ade/context/engines.md` (table at top): deepseek go on focus,
      `--agents`, delegation and `--effort`, no on remote; glm no-go on everything until tested; meta no-go. SP mirrors this in the
      table in `bin/lib.sh` (scope 1). [Go/no-go]
- [x] **Tool restriction.** None needed for DeepSeek (engines.md, "Tool restriction (AC19): none needed for DeepSeek"). AC19 is
      skipped with that reason.
- [ ] **Owner decision: data sharing per hub and vendor API terms.** The owner asked for DeepSeek (plan rev 7). The per-hub decision
      that client code and hub notes go to DeepSeek is **not recorded**, and DeepSeek's API terms on training and retention
      were **not researched** in S0. **OPEN:** the owner records the decision, and someone reads DeepSeek's terms, before ADR 0002's
      provider section is accepted (AC21 checks that the section exists and names both items). Not a build blocker; a Done blocker.

## Goal

A hub can run a Claude Code focus session, or Claude sub-agents, against DeepSeek instead of Anthropic. The CLI stays Claude
Code, so the hub's hooks, `--agents` and session end keep working. Only the provider behind it changes. GLM is present in the
table, disabled. Meta is absent.

## Scope (SP only)

1. **Provider table in `bin/lib.sh`.** Ids: `anthropic` (default, Claude Code's own login), `deepseek`, `glm`. (`meta` is absent,
   see AC18.)
   - `deepseek`: base URL `https://api.deepseek.com/anthropic`; Keychain secret `deepseek-api-key` (doctor label "DeepSeek API key");
     models: main `deepseek-flash`, `ANTHROPIC_DEFAULT_OPUS_MODEL=deepseek-v4-pro`, `ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-flash`,
     `ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-flash`, `ANTHROPIC_SMALL_FAST_MODEL=deepseek-flash`.
   - `glm`: base URL `https://api.z.ai/api/anthropic`; Keychain secret `zai-api-key` (doctor label "z.ai API key"); models
     `unconfirmed` (not used, the row is refused). Shipped disabled.
   - Go/no-go is a function in `lib.sh`, `provider_feature_go <provider> <feature>` (features: `focus`, `agents`, `delegation`,
     `effort`, `remote`), written as a `case` (Bash 3.2, no associative arrays). Values from engines.md:
     - deepseek: `focus` go, `agents` go, `delegation` go, `effort` go, `remote` no;
     - glm: all no.
     `delegation` is in the table because S3a reads the same rows; SP itself has no delegation.
   - A `provider_no_go_reason <provider> <feature>` names the S0 finding (`S0 item 21, .ade/context/engines.md`) for the refusal.
   - **No base URL override.** Base URLs live only in the table; there is no `HUB_<P>_BASE_URL`, now or later.
2. **Choosing a provider.**
   - `HUB_PROVIDER` (sessions, default `anthropic`) and `HUB_PROVIDERS_ALLOWED` (space-separated, default `anthropic`) are read
     **only from `hub.conf`**. `bin/lib.sh` unsets both immediately before the `hub.conf` line (currently line 47), exactly like the
     plan's `HUB_ENGINES_ALLOWED` mechanism. A provider not in the list exits 2.
   - `bin/work --provider <p> <folder>` for one session. `--model` is that provider's slot alias or row id.
   - `HUB_<P>_MODEL` and `HUB_<P>_SMALL_MODEL` (for deepseek: `HUB_DEEPSEEK_MODEL`, `HUB_DEEPSEEK_SMALL_MODEL`) override the row's
     defaults per hub. Each is checked like `--model` (a slot alias or a row id); a stale value exits 2 at launch.
   - `HUB_MODEL` and `HUB_AGENT_MODEL` are **not passed** to a provider session (either may be a full Anthropic id).
   - Agent front matter `provider:` is read by `bin/work` for the `--agents` check only. Delegation through `bin/agent` is S3a.
3. **How a provider session starts** (`bin/work`, in this order):
   1. Parse arguments; resolve the provider; refuse a provider not in `HUB_PROVIDERS_ALLOWED` (exit 2).
   2. Refuse a wrapper: the resolved command must be exactly `claude` (name, not path) for any non-`anthropic` provider. This covers
      `--claude`, `HUB_CLAUDE` and `AGENT_CLAUDE` alike. Otherwise exit 2.
   3. Refuse a no-go: `provider_feature_go <p> focus` (and `agents` when `--agents` is generated, `effort` when `--effort` is
      present) must be go, else exit 2 with the reason.
   4. Model and effort rules (scope 5). Refuse `--resume`, `--continue`, `-r`, `-c` (scope 6).
   5. **Key pre-check (non-dry runs only).** `key="$("$H/bin/secret" <secret-name>)"` in a subshell. If it fails or prints nothing,
      print `bin/secret --set <secret-name>` as the hint and exit 1. Unset `key` afterwards. Claude Code never starts without a key.
      Dry runs never read the key.
   6. **Merged settings file.** Build one JSON file with `python3` (a mktemp file, mode 600, removed by the launcher's trap). It takes
      the folder's `.claude/settings.json` (exit 2 if missing) and adds the provider layer:
      - `apiKeyHelper`: `'<H>/bin/secret' <secret-name>`, with the hub path single-quoted, since `/bin/sh` runs it;
      - `skipWebFetchPreflight: true` (top level);
      - `env` block: the row's base URL and slot variables, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`,
        `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`. The provider's `env` keys win over same-named keys in the folder's `env`.
      - `CLAUDE_CODE_SUBAGENT_MODEL` is **not** set.
      - It never contains a key value.
   7. **Command.** `cd '<dir>' && AGENT_FOLDER='<F>' CLAUDE_CONFIG_DIR='<H>/.local/providers/<p>' <claude> --settings '<merged>'`
      plus `--agents`, `--model`, `--effort` as today. The `CLAUDE_CONFIG_DIR` prefix is the only provider value in the process
      environment (scope 4). `--remote-control` is never added. The command goes into a launcher file, as today.
   8. The folder's memory is linked for this provider's config dir (scope 4).
4. **Provider config dir (closes the `/model` leak).** A provider session runs with `CLAUDE_CONFIG_DIR=$H/.local/providers/<p>`,
   never `claude_home()`. `/model` then writes to that dir, not the owner's `settings.json`, and the next Anthropic session is
   unaffected. Within that dir, `bin/work` creates the memory links that `bin/setup` makes for Anthropic sessions, with the
   same encoding (`encode_path`): `projects/<enc $H>/memory -> $H/memory` and `projects/<enc $dir>/memory -> $H/$F/memory` for
   the launched checkout (a no-repo folder's `$dir` is `$H/$F`). Provider config dirs are under `.local/`, which is gitignored.
   Expected first-run cost: Claude Code's first-run prompts may appear once per provider dir. The spike used fresh dirs (interactive
   `/model` ran through a pty), so this is expected to be the same behaviour, not verified in a live launch.
5. **Models in a provider session.** `--model` (and `HUB_<P>_MODEL`) must be a slot alias (`opus`, `sonnet`, `haiku`) or an id in the
   row (`deepseek-flash`, `deepseek-v4-pro`); anything else exits 2. Agent `model:` values follow the same rule, except `inherit`
   and absent. `--agent-model` is checked the same way. `--effort` (and `HUB_EFFORT`, `--agent-effort`) is refused exit 2 unless
   `provider_feature_go <p> effort` is go.
6. **Resume refused.** `--resume`, `--continue`, `-r` and `-c` exit 2 for a provider session with the reason: a provider session
   does not resume history (engines.md, "`--resume` leak"). Simplest safe rule; no per-provider history check.
7. **Remote Control off** for every provider other than `anthropic`. `--provider` implies `--no-remote`.
8. **`--agents` provider check** in `bin/work`'s agent JSON step: an agent with no `provider:` inherits the session's provider and stays
   (under scope 5); an agent whose `provider:` names the same provider stays; one naming a different provider is left out of
   `--agents`, and `bin/work` prints one stderr line per left-out agent: `work: delegatable (not in --agents): <name> (provider <p>)`.
9. **Doctor.** One row per allowed provider (not `anthropic`): `DeepSeek API key   OK` or `MISSING` (showing the secret name and
   presence, never the value), via `bin/secret --has`. `bin/doctor --deep` endpoint checks are S0's and S3a's, not SP's.
10. **README.** A provider section: how to choose (`HUB_PROVIDERS_ALLOWED`, `--provider`), `bin/secret --set deepseek-api-key`,
    Remote Control off, the wrapper rule, the data-sharing note (open owner item), the exposure statement for the chosen credential
    option (option 1: the key is read by Claude Code's helper only, and is never in the environment, argv or a file), and that GLM
    is disabled and Meta is not offered.
11. **ADR 0002, provider section.** `.ade/context/decisions/0002-*.md` does not exist on this branch (only `0001`). S2a plans to create
    ADR 0002 for engines. Whichever story lands first creates the file; the other appends its own section. Check with the architect
    before creating a second `0002`. The provider section records the credential option, the per-hub data-sharing decision (OPEN, as
    written), and the vendors' API-terms note (DeepSeek not yet reviewed).
12. **Provider contract, in Context Store.** Record the provider ids, row fields, go/no-go values, the provider config dir layout and
    the `HUB_*` names in a new `.ade/context/providers.md` (short, factual). S3a reads it. This is the only `.ade/context/` file SP
    writes.

## Out of scope

- `bin/agent`, delegation, its env handling, its fail-closed key read, its no-go check and its `provider:` handling (S3a).
- `bin/doctor --deep` requests and the behavioural canary per provider (S0 item 21 and S3a).
- `bin/briefing` (stays on Anthropic).
- Enabling GLM. It needs its own canary runs with a z.ai key; it then flips its go values in the table and in engines.md.
- `meta` in any form (AC18).
- Codex and Gemini engines.
- Any `HUB_<P>_BASE_URL` override (never).
- Unofficial bridges that drive a muse.ai browser session (never).
- Storing any key in the hub, `hub.conf`, the launcher file, the merged settings file, argv or a file.
- Live calls to DeepSeek or any vendor in `tests/run.sh`.

## Acceptance criteria

All checks live in `tests/test_providers.sh` (new), using `make_hub` from `tests/helpers.sh`. `make_hub` excludes `hub.conf` and
`.local`, so each provider test writes its own `hub.conf` (for example `HUB_PROVIDERS_ALLOWED="anthropic deepseek"`) when it needs one.

Hermetic rules:
- Every provider check puts a `security` stub (as in `tests/test_secret.sh`, with a value that is never printed) and an `osascript`
  stub on PATH. The `osascript` stub copies the launcher file and the merged settings file to a capture dir, then runs the launcher
  synchronously, so the fake engine runs inside the test.
- The fake engine is a bash script named `claude` in a temp dir placed first on PATH, and the test sets `AGENT_CLAUDE=claude`. The
  wrapper rule is by name, so the fake passes as plain `claude`; the real `claude` is never run. The fake writes its argv, its
  selected env names and a marker file.
- A `bin/secret` stub, when used, is a script in the same temp dir; it counts its calls in a file.

| AC | Criterion | Automated test |
|---|---|---|
| AC1 | Static, over **every** row in the table (deepseek, glm): base URL is `https://`, has no trailing `/` and does not end in `/v1`; every row has a Keychain secret name. | `provider_rows_static` |
| AC2 | `WORK_DRY=1 bin/work --provider deepseek projects/demo` (with `HUB_PROVIDERS_ALLOWED="anthropic deepseek"`) prints a command with `CLAUDE_CONFIG_DIR` set to `$H/.local/providers/deepseek` and no `--remote-control`. The dry run keeps no merged settings file: it prints the JSON after the command (story SP review, m1), and that JSON contains the base URL exactly, `https://api.deepseek.com/anthropic`, the five model variables with the values in scope 1, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` `"1"`, and no `CLAUDE_CODE_SUBAGENT_MODEL`. No key value appears in the output or the JSON (the stub's value is absent). A non-dry run's merged settings file is mode 600. | `dry_run_deepseek` |
| AC3 | A non-dry run (osascript stub) captures a launcher file and a merged settings file. Neither contains the stub's key value nor `ANTHROPIC_AUTH_TOKEN=`. | `launcher_file_holds_no_key` |
| AC4 | The fake engine's argv contains no key value. | `engine_argv_holds_no_key` |
| AC5 | Fail closed: with a `bin/secret` stub that exits 1, and another that prints nothing, `bin/work --provider deepseek` exits 1, prints `bin/secret --set deepseek-api-key`, and the fake engine's marker is absent. | `fail_closed_on_missing_key`, `fail_closed_on_empty_key` |
| AC6 | The key is read once, before the launch: the `bin/secret` stub's call count is exactly 1, and the call happened before the osascript stub ran. The merged settings file's `apiKeyHelper` is `HUB='<H>' AGENT_KEYCHAIN_SERVICE='<svc>' '<H>/bin/secret' deepseek-api-key` (each value single-quoted; AC38) and the file still contains the folder's hook entries from `projects/demo/.claude/settings.json`. | `key_checked_once_before_launch`, `single_merged_settings_keeps_hooks` |
| AC7 | Settings precedence: **skipped** with the recorded reason "S0 item 21: the provider layer's `env` wins over checkout and user settings (engines.md, Settings precedence)". The test prints the skip and asserts that engines.md still records `wins`. | `checkout_base_url_conflict_refused` (skip) |
| AC8 | `--provider deepseek` implies `--no-remote`: the dry-run command has no `--remote-control`. | `provider_implies_no_remote` |
| AC9 | Wrapper refusal from each source: `--claude mywrap`, `HUB_CLAUDE=mywrap` (in hub.conf) and `AGENT_CLAUDE=mywrap` each with `--provider deepseek` exit 2. `AGENT_CLAUDE=claude` (plain, from each source) is accepted. | `provider_rejects_wrapper_from_each_source` |
| AC10 | Model rules, deepseek: `--model sonnet` and `--model deepseek-v4-pro` are accepted; `--model claude-sonnet-4-5` exits 2; `HUB_MODEL=claude-sonnet-4-5` and `HUB_AGENT_MODEL=sonnet` in hub.conf are not passed to a provider session; an agent with `model: claude-sonnet-4-5` exits 2 under `--provider deepseek`, an agent with `model: inherit` does not. | `provider_model_rules`, `hub_model_not_passed` |
| AC11 | `--effort high` with deepseek is accepted and passes `--effort high`. In a hub copy whose `bin/lib.sh` marks deepseek `effort` no-go, `--effort high` (and `HUB_EFFORT=high`) exits 2 naming the S0 reason. | `provider_effort_accepted`, `provider_effort_refused` |
| AC12 | `HUB_DEEPSEEK_MODEL=deepseek-v4-pro` and `HUB_DEEPSEEK_SMALL_MODEL=deepseek-flash` in hub.conf replace the main and small-fast slots in the merged settings file. A stale value (`HUB_DEEPSEEK_MODEL=deepseek-v4-flash`, not a slot alias or row id) exits 2 at launch. | `hub_provider_model_override`, `hub_provider_model_checked` |
| AC13 | No base URL override: `HUB_DEEPSEEK_BASE_URL` in hub.conf **and** in the environment does not change `ANTHROPIC_BASE_URL` in the merged settings file. | `no_base_url_override` |
| AC14 | `HUB_PROVIDER` and `HUB_PROVIDERS_ALLOWED` set only in the environment change nothing (a default `bin/work` run stays on anthropic). `--provider deepseek` with `HUB_PROVIDERS_ALLOWED` unset or `anthropic` only exits 2. | `provider_env_not_trusted`, `provider_not_allowed` |
| AC15 | Go/no-go refusal, unedited table: `bin/work --provider glm` exits 2 with a message naming "S0 item 21". In a hub copy whose `lib.sh` marks deepseek `focus` no-go, `bin/work --provider deepseek` exits 2 naming the S0 reason. | `no_go_pair_refused_by_work` |
| AC16 | `--agents` provider check: in a folder with three agents (no `provider:`; `provider: deepseek`; `provider: glm`), a deepseek session's `--agents` JSON keeps the first two, omits the third, and stderr names the omitted agent: `delegatable (not in --agents): <name> (provider glm)`. | `agents_provider_check` |
| AC17 | `DOCTOR_OFFLINE=1 bin/doctor` with `HUB_PROVIDERS_ALLOWED="anthropic deepseek"` prints one provider row for deepseek (`deepseek-api-key`, `OK` or `MISSING`), no row for glm (not allowed), and never the stub's value. | `doctor_provider_rows_name_only` |
| AC18 | `meta` is absent: no `meta` row in the `lib.sh` provider table, and no `meta` provider entry in the README provider section (the word may appear only in a sentence saying it is not offered). | `meta_row_only_with_a_go` |
| AC19 | Tool restriction: **skipped** with the recorded reason "none needed for DeepSeek (engines.md, Tool restriction)". The test asserts that line exists in engines.md. | `allowed_tools_applied` (skip) |
| AC20 | Static: `README.md` provider section contains `--provider`, `bin/secret --set deepseek-api-key`, that Remote Control is off, the data-sharing note, and the exposure statement for option 1. | `readme_provider_section` |
| AC21 | Static: ADR 0002 exists and its provider section has headings for the credential option (option 1, with the helper and the scrub variable), the per-hub data-sharing decision (the owner rule of 2026-11-09, `HUB_OWNED_BY_OWNER=1`) and the vendors' API-terms note (DeepSeek reviewed 2026-11-09: Terms of Use §4.3 with its URL, storage in the People's Republic of China). | `adr_0002_provider_section` |
| AC22 | Scope guard: `bin/briefing` is unchanged and `bin/agent` does not exist. Checked in review (`git diff --stat main...` on the PR), **not** in `tests/run.sh`: the permanent suite must pass on a fresh shallow clone, which has no base ref (code review M2, 2026-11-09). | review only (removed from `tests/test_providers.sh`) |
| AC23 | Hermetic guard: every provider check asserts the fake `claude` was the engine that ran (marker present and written by the fake), and no provider test runs a `claude` other than the fake on PATH. | `hermetic_fake_engine_only` |
| AC24 | Existing suites still pass: `tests/test_work.sh`, `tests/test_doctor.sh`, `tests/test_secret.sh`, `tests/test_models.sh`, `tests/test_briefing.sh`, unchanged. | existing files, run by `tests/run.sh` |
| AC25 | `/model` leak closed: the fake engine writes `{"model":"deepseek-v4-pro"}` to `$CLAUDE_CONFIG_DIR/settings.json`. After the run, `$CLAUDE_HOME/settings.json` is absent or unchanged, and the write landed in `$H/.local/providers/deepseek/settings.json`. | `provider_config_dir_isolated` |
| AC26 | Memory is linked in the provider config dir: after a non-dry run of a no-repo folder, `$H/.local/providers/deepseek/projects/<enc $H>/memory` and `.../projects/<enc $H/projects/demo>/memory` are symlinks to `$H/memory` and `$H/projects/demo/memory`. | `provider_memory_linked` |
| AC27 | Resume refused: `bin/work --provider deepseek projects/demo --resume`, `--continue`, `-r` and `-c` each exit 2 and name the rule. | `provider_resume_refused` |
| AC28 | Provider layer flags: the merged settings file has `skipWebFetchPreflight` `true` (top level) and `env.CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` `"1"`; neither the file nor the command contains `CLAUDE_CODE_SUBAGENT_MODEL`. | `provider_layer_flags` |
| AC29 | Anthropic path unchanged: `bin/work --provider anthropic projects/demo` prints a command identical to `bin/work projects/demo`, with no `CLAUDE_CONFIG_DIR` prefix and no merged settings file (`--settings` names the folder's own `settings.json`). | `anthropic_path_unchanged` |
| AC31 | Owner rule (2026-11-09): in a client hub (no `HUB_OWNED_BY_OWNER=1` in hub.conf), `bin/work --provider deepseek` and `HUB_PROVIDER=deepseek` exit 2 even when `HUB_PROVIDERS_ALLOWED` lists deepseek, naming `HUB_OWNED_BY_OWNER`, ADR 0002 and the reason (training on API data, storage in China); no key is read and the engine does not run. Anthropic sessions still run. | `deepseek_client_hub_refused` |
| AC32 | In an owned hub (`HUB_OWNED_BY_OWNER=1` in hub.conf) deepseek is allowed, by `--provider` and by `HUB_PROVIDER`. | `deepseek_owned_hub_allowed` |
| AC33 | `HUB_OWNED_BY_OWNER=1` exported in the environment is ignored (unset before sourcing hub.conf), by `bin/work` and `bin/doctor`. | `owned_by_owner_env_not_trusted` |
| AC34 | `DOCTOR_OFFLINE=1 bin/doctor` prints a `MISSING  client hub` row when the allowlist of a client hub lists deepseek, and none in an owned hub or a hub without deepseek. | `doctor_flags_client_hub_deepseek` |
| AC30 | The only key read `bin/work` performs is the pre-check (AC6), and no file or argv value it writes holds a key: the launcher file, the merged settings file and the engine argv are all key-free. Mapped to the existing tests rather than a new one. | `key_checked_once_before_launch`, `launcher_file_holds_no_key`, `engine_argv_holds_no_key` |
| AC35 | (Review B1) Claude Code's auth order is `ANTHROPIC_AUTH_TOKEN` > `ANTHROPIC_API_KEY` > `apiKeyHelper` > OAuth, and the launcher is `bash -l`. With every `provider_scrub_vars` name (`ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`, `ANTHROPIC_CUSTOM_HEADERS`, `CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_VERTEX`, `CLAUDE_CODE_USE_FOUNDRY`, `CLAUDE_CODE_OAUTH_TOKEN`) planted with fake values in the launching environment, a provider launch runs, the launcher runs `claude` through `env -u <name>` for each, and the fake engine's environment, argv and settings hold none of them. The anthropic command is unchanged. | `provider_env_creds_scrubbed` |
| AC36 | (B1) Each of those names planted in the folder's `.claude/settings.json` `env` is absent from the merged settings (dry-run JSON and the launched file); other folder env keys are kept. | `folder_env_creds_dropped` |
| AC37 | (B1) The checkout's `.claude/settings.json` or `.claude/settings.local.json` setting any of those names in `env` (checked for each name and each file) is refused before the key is read: exit 2, naming the file and the key, never the value; the engine does not run. A no-repo folder works in its own folder, so a name in its own settings is refused too. A checkout env without them is accepted; the anthropic path does not check. | `checkout_env_creds_refused` |
| AC38 | (M1) `apiKeyHelper` pins the hub and the Keychain service the pre-check used: `HUB='<H>' AGENT_KEYCHAIN_SERVICE='<svc>' '<H>/bin/secret' deepseek-api-key`, for a service from `hub.conf` (`HUB_KEYCHAIN_SERVICE`) and from `AGENT_KEYCHAIN_SERVICE`. The pre-check's `bin/secret` saw the same hub and service, and the helper run by `/bin/sh` from a bare environment reads the same. | `helper_pins_hub_and_service` |
| AC39 | (M3) After the (stub) launcher exits, the merged settings file it named and the launcher file are gone. | `merged_settings_removed_after_launch` |
| AC40 | (M3) In a hub copy whose `lib.sh` marks deepseek `agents` no-go, a folder with agents exits 2 naming S0 item 21; a folder without agents still runs. | `agents_no_go_refused` |
| AC41 | (m1) No `agent-settings.*` file is left by a dry run, and no `agent-settings.*` or `agent-work.*` file is left when the hand-off (osascript) fails, for a provider and an anthropic session. | `no_settings_left_behind` |
| AC42 | (m2) A provider session exits 2, naming `HUB=`, when `HUB` in the environment is another hub than the script's own; the same hub by its real path, and `HUB` unset, run. | `hub_env_mismatch_refused` |
| AC43 | (m3) glm is `owner_only` 1 (z.ai is China-based). A row with no `owner_only` value is refused in a client hub (naming `HUB_OWNED_BY_OWNER`) and runs in an owned hub. | `owner_only_default_refuses` |
| AC44 | (m4) The provider config dir, its `projects/`, or the hub's `.local` symlinked to a temp "fake ~/.claude" is refused (exit 2, before the key read, engine not run), and nothing is written there; a real config dir runs. | `config_dir_symlink_refused` |
| AC45 | (m5) The suite uses a temp `HOME`, never inherits `ANTHROPIC_*`, `CLAUDE_CODE_USE_*` or `CLAUDE_CODE_OAUTH_TOKEN` from the tester's shell (`make_hub` unsets them), and removes every temp dir it made: a child run of the suite, given planted fake values, reports a temp `HOME` and a clean environment, leaves its listed temp dirs gone and its given `HOME` and `TMPDIR` empty. | `suite_hermetic_and_clean` |

Not tested in `tests/run.sh` (they belong to S0 item 21 and S3a): the canary behaviour and the real `claude` against a fake
Anthropic-compatible server, the `apiKeyHelper` failure after startup, the Keychain-login live check (OPEN above), and `bin/agent`'s
fail-closed read and no-go check.

## Test notes (TDD order)

1. Write `tests/test_providers.sh` with AC1 first (static; fails until the table exists), then AC2 to AC4 (dry run, launcher, argv).
   Confirm each fails for the right reason before the code exists.
2. AC5 and AC6 (fail closed, pre-check once, merged settings), AC25 and AC26 (config dir and memory), then AC8 to AC14 (option rules),
   AC15 (go/no-go), AC16 (`--agents`), AC17 (doctor).
3. AC18 to AC21 are static checks: write them before the README and ADR text, so they fail first.
4. AC7 and AC19 are skips: they print the reason and assert the engines.md line exists. Never a silent pass.

## Files touched

- `bin/lib.sh`: provider table (deepseek and glm rows), `provider_feature_go`, `provider_no_go_reason`, `HUB_PROVIDER` and
  `HUB_PROVIDERS_ALLOWED` added to the unset-before-sourcing list, immediately before the `hub.conf` line (line 47 on this branch).
- `bin/work`: `--provider`, the start order in scope 3, merged settings file, key pre-check, config dir and memory links, wrapper,
  model, effort and resume rules, go/no-go check, `--agents` provider filter, `--no-remote` implication.
- `bin/doctor`: one row per allowed provider (name and presence only).
- `README.md`: provider section.
- `.ade/context/decisions/0002-*.md`: provider section (created here only if S2a has not landed).
- `.ade/context/providers.md`: new, the provider contract (scope 12).
- `tests/test_providers.sh`: new.
- `tests/helpers.sh`: `make_hub` unsets `ANTHROPIC_*`, `CLAUDE_CODE_USE_*` and `CLAUDE_CODE_OAUTH_TOKEN` (review B1).
- `docs/stories/SP-providers.md`: this file. The Verification section is filled by QA only.

Not touched: `bin/agent` (S3a), `bin/briefing`, `bin/session-end`, `bin/sync`, `bin/changes`, `tests/run.sh`, `.ade/context/engines.md`.
`.gitignore` already ignores `.local/`, so provider config dirs need no new entry.

## Dependencies and shared contracts

- **S0 item 21:** answered for deepseek in `.ade/context/engines.md`. SP reads it and does not write it. Its GLM and Meta answers are
  "not tested" and stay that way for SP.
- Shared with S1: `bin/lib.sh` (the unset list and helpers). S1 is not a dependency of SP; coordinate the edit to `lib.sh` if S1 lands first.
- Shared with S3a: the provider table and `provider_feature_go`. S3a's `bin/agent` must read the same rows, not a copy.
- Shared with S2a: ADR 0002 (scope 11) and the `hub.conf` unset list (S2a extends the same list).

## Coding standards

- Bash 3.2 compatible (macOS `/bin/bash`): no associative arrays, no `mapfile`. JSON handling in `python3`, as `bin/work` does today.
- A secret goes to stdout only through `bin/secret`, inside `$(...)` at the point of use: never in argv, a file, the launcher, the
  merged settings file, a commit, a log or a URL. The key pre-check's variable is unset right after the check.
- The test value of the `security` stub must not appear in any output or file a test writes; the tests assert this.
- No real vendor call and no real `claude` in `tests/run.sh`.
- Keep `--provider anthropic` and no-flag runs byte-identical (AC29, and `tests/test_work.sh` unchanged).

## Open before Done

1. Done in the build: the owner's rule (DeepSeek only in the owner's own hubs, 2026-11-09) and DeepSeek's terms (reviewed
   2026-11-09) are recorded in ADR 0002, which stays Proposed until the owner accepts it.
2. Owner: a live check on the owner's Mac that the Keychain-stored Anthropic login is not sent to `api.deepseek.com` when the helper
   is set (S0 item 15/21 gap).
3. First live use: the first run of a provider session may show Claude Code's first-run prompts (expected, once per provider dir).

## Verification

Command: `bash tests/run.sh` (must print `ok    test_providers.sh` and every existing test file as `ok`, and exit 0).

Real output recorded by QA:

Status: **QA passed, awaiting code review** (2026-11-09). Not Done: the adversarial code review is still open.

Run (hermetic, as required): `S=$(mktemp -d); mkdir -p "$S/home" "$S/tmp"; env -i PATH="$PATH" HOME="$S/home" TMPDIR="$S/tmp" LANG=C bash tests/run.sh`
(no `CLAUDE_CONFIG_DIR` / `HUB_CLAUDE_CONFIG_DIR`). Exit 0. Real output:

```
ok    test_brain.sh
ok    test_briefing.sh
ok    test_changes.sh
ok    test_context.sh
ok    test_doctor.sh
ok    test_init.sh
ok    test_lib.sh
ok    test_models.sh
ok    test_monitor.sh
ok    test_new.sh
ok    test_precommit.sh
ok    test_providers.sh
ok    test_remote.sh
ok    test_report.sh
ok    test_root.sh
ok    test_schedule.sh
ok    test_secret.sh
ok    test_session_end.sh
ok    test_setup.sh
ok    test_sync.sh
ok    test_work.sh
```

`tests/run.sh` hides a passing suite's output, so the SKIP lines come from `bash tests/test_providers.sh` alone (same hermetic
env, exit 0, last line `ok`):

```
SKIP AC7 checkout_base_url_conflict_refused: S0 item 21: the provider layer's env wins over checkout and user settings (engines.md, Settings precedence)
SKIP AC19 allowed_tools_applied: none needed for DeepSeek (engines.md, Tool restriction)
```

Safety: `shasum ~/.claude-caiden/settings.json ~/.claude/settings.json` before and after the runs are identical
(`5f36b2ea...` and `7d2a7b7e...`).

Criteria map (QA read each check's body, not only the exit code): AC1 `provider_rows_static`; AC2 `dry_run_deepseek`; AC3
`launcher_file_holds_no_key`; AC4 `engine_argv_holds_no_key`; AC5 `fail_closed_on_missing_key` and `fail_closed_on_empty_key`;
AC6 `key_checked_once_before_launch` and `single_merged_settings_keeps_hooks`; AC8 `provider_implies_no_remote`; AC9
`provider_rejects_wrapper_from_each_source`; AC10 `provider_model_rules` and `hub_model_not_passed`; AC11
`provider_effort_accepted` and `provider_effort_refused`; AC12 `hub_provider_model_override` and `hub_provider_model_checked`;
AC13 `no_base_url_override`; AC14 `provider_env_not_trusted` and `provider_not_allowed`; AC15 `no_go_pair_refused_by_work`; AC16
`agents_provider_check`; AC17 `doctor_provider_rows_name_only`; AC18 `meta_row_only_with_a_go`; AC20 `readme_provider_section`;
AC21 `adr_0002_provider_section`; AC22 `scope_guard_briefing_and_agent`; AC23 `hermetic_fake_engine_only`; AC25
`provider_config_dir_isolated`; AC26 `provider_memory_linked`; AC27 `provider_resume_refused`; AC28 `provider_layer_flags`; AC29
`anthropic_path_unchanged`; AC30 mapped to the AC3/AC4/AC6 checks; AC31 `deepseek_client_hub_refused`; AC32
`deepseek_owned_hub_allowed`; AC33 `owned_by_owner_env_not_trusted`; AC34 `doctor_flags_client_hub_deepseek`. AC24: the five
named suites are unchanged against `origin/s0-providers` (empty diff) and each printed `ok` above.

SKIPs: AC7 and AC19 print the recorded reason and first assert the engines.md line (`The env block of the --settings layer
**wins**`, and `Tool restriction (AC19): none needed for DeepSeek.`); both lines exist in `.ade/context/engines.md`, so the reasons
match. Neither is a silent pass.

Weak spots (not failures): AC22 depends on a local `origin/s0-providers` ref and fails with a clear message if it is absent
(needs `git fetch`). AC23's "no other `claude` ran" is shown by the nonce marker plus PATH, not by tracing every process.

