# 0002: Other providers and engines

- Status: Proposed (provider section written by story SP, 2026-11-09; the owner's data-sharing rule below is the owner's
  decision of 2026-11-09). The engines section is S2a's to append; S2a does not create a second 0002.
- Context: the plan `docs/plans/2026-11-09-other-ai-cli-agents.md` runs hub sessions on other providers (SP) and other
  CLIs (S2a onward). Both send client code and hub notes to vendors other than Anthropic.
- Decision: see the sections below.
- Consequences: see each section.

## Providers (story SP)

Claude Code stays the CLI; only the endpoint changes (`ANTHROPIC_BASE_URL` from the `bin/lib.sh` table). DeepSeek ships;
GLM ships disabled (no go in S0 item 21); Meta is not offered. Findings: `.ade/context/engines.md`. Contract:
`.ade/context/providers.md`.

### Credential option

Credential option 1, `apiKeyHelper`, chosen on S0 item 21's evidence (runs d1, t3, t8):

- The provider layer of the merged `--settings` file sets `apiKeyHelper` to `'<hub>/bin/secret' <secret-name>`. Only
  Claude Code runs it, so no hook, Bash tool command or MCP server inherits the key. The key is never in the
  environment, argv, the launcher file or the settings file.
- `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` is set too, as defence in depth (option 2), not as the mechanism.
- `bin/work` runs `bin/secret` once before launch and refuses (exit 1) on failure or empty output, because Claude Code
  does not fail closed when the helper fails at startup, and with no key it sends the Anthropic login to the third
  party (engines.md, "apiKeyHelper failure", "No Anthropic credential sent").
- Consequence: a cached key keeps working after a later helper failure until a 401. The Keychain-stored Anthropic
  login was not tested (OPEN: live check on the owner's Mac before the first real session).

### Data sharing per hub

Owner rule, 2026-11-09: **DeepSeek may be enabled only in the owner's own, non-client hubs.**

- Mechanism: `HUB_OWNED_BY_OWNER=1` in `hub.conf` (absent = a client hub). It is read only from `hub.conf`; `bin/lib.sh`
  unsets it before sourcing, like `HUB_PROVIDER` and `HUB_PROVIDERS_ALLOWED`.
- In a client hub, `bin/work --provider deepseek` (or `HUB_PROVIDER=deepseek`) exits 2 naming this ADR, even when
  `HUB_PROVIDERS_ALLOWED` lists deepseek, and `bin/doctor` flags such an allowlist. Anthropic sessions are unaffected.
- The row field `owner_only` in `bin/lib.sh` carries the rule, so S3a's `bin/agent` applies the same check.
- GLM: no decision (disabled). A future provider gets its own owner decision before it ships.

### Vendor API terms

DeepSeek: reviewed 2026-11-09 from DeepSeek's own documents (a reading, not legal advice):

- Training: allowed. Terms of Use §4.3 (last update 2026-03-27,
  https://cdn.deepseek.com/policies/en-US/deepseek-terms-of-use.html): DeepSeek "may, to a minimal extent, use Inputs
  and Outputs to provide, maintain, operate, develop or improve the Services". ToU §1.1 covers APIs, and the Open
  Platform Terms of Service (effective 2026-04-29,
  https://cdn.deepseek.com/policies/en-US/deepseek-open-platform-terms-of-service.html) have no carve-out. The only
  documented opt-out is a chat-app toggle; no API opt-out is documented.
- Storage and law: the Privacy Policy (last update 2026-02-10,
  https://cdn.deepseek.com/policies/en-US/deepseek-privacy-policy.html) says data is collected, processed and stored
  "in People's Republic of China"; PRC mainland law governs (Platform ToS §10.1), with disputes in Hangzhou (§10.2).
- Retention: no fixed period ("for as long as necessary", inputs "for as long as you have an account"); no zero-retention
  option.
- Terms are not negotiable: the API is "self-service and standardized", and the offline framework agreement "cannot be
  modified" (help-centre FAQ, https://static.deepseek.com/faq/index.html?lang=en). No DPA is published.
- Consequence: client code and confidential notes must not go to `api.deepseek.com`; hence the owner rule above. The terms
  can change with 7 days' notice (Platform ToS §11.1); re-check before relying on this.

GLM (z.ai): not reviewed for SP (disabled). Meta: not reviewed (not offered).

## Engines (S2a)

Not written yet; S2a appends it here.
