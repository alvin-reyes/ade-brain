# Providers behind Claude Code (contract, story SP)

Claude Code stays the CLI; a provider changes only the endpoint and models. Written by SP; S3a (`bin/agent`) reads the
same table, never a copy. Findings: `engines.md`. Decision and terms: `decisions/0002-providers-and-engines.md`.

## Ids
`anthropic` (default; Claude Code's own login; no row), `deepseek`, `glm` (disabled). `meta` is absent.

## The table (`bin/lib.sh`)
- `providers` prints the row ids. `provider_field <p> <field>` prints a field; it returns 1 for an unknown pair.
- Fields: `base_url` (https, no trailing `/` or `/v1`), `secret` (Keychain name for `bin/secret`), `label` (doctor),
  `model`, `opus`, `sonnet`, `haiku`, `small` (slot values), `owner_only` (`1` = only in a hub with `HUB_OWNED_BY_OWNER=1`).
- deepseek: `https://api.deepseek.com/anthropic`, `deepseek-api-key`, main/sonnet/haiku/small `deepseek-flash`, opus
  `deepseek-v4-pro`, `owner_only` 1. glm: `https://api.z.ai/api/anthropic`, `zai-api-key`, models `unconfirmed`.
- `provider_feature_go <p> <focus|agents|delegation|effort|remote>`: exit 0 = go. deepseek: focus, agents, delegation,
  effort go; remote no. glm: all no. One go per `case` line.
- `provider_no_go_reason <p> <feature>` names "S0 item 21, .ade/context/engines.md".
- `provider_model_ok <p> <m>`: a slot alias (`opus`, `sonnet`, `haiku`) or a row id. `provider_model_id` resolves an alias.
- `provider_hub_refusal <p>`: prints the reason this hub may not use `<p>` (empty = it may).
- No base URL override exists (`HUB_<P>_BASE_URL` is never read).

## `hub.conf` keys
- Read only from `hub.conf` (unset in `lib.sh` before sourcing): `HUB_PROVIDER` (default `anthropic`),
  `HUB_PROVIDERS_ALLOWED` (space-separated, default `anthropic`), `HUB_OWNED_BY_OWNER` (`1` = the owner's own hub).
- `HUB_<P>_MODEL`, `HUB_<P>_SMALL_MODEL` (`<P>` upper-case, `-` as `_`): main and small-fast slot overrides, checked
  like `--model`.
- `HUB_MODEL` and `HUB_AGENT_MODEL` are not passed to a provider session.

## A provider session (`bin/work --provider <p>`)
- Refused (exit 2): not allowed; no row; owner-only in a client hub; a command other than plain `claude`; a feature
  without a go; `--resume`, `--continue`, `-r`, `-c`; a model not allowed. Missing or empty key: exit 1 with the
  `bin/secret --set <secret>` hint, before Claude Code starts. Dry runs never read the key.
- Command: `cd '<dir>' && AGENT_FOLDER='<F>' CLAUDE_CONFIG_DIR='<hub>/.local/providers/<p>' claude --settings '<merged>'`,
  no `--remote-control`.
- Merged settings (mktemp, mode 600, removed by the launcher's trap): the folder's settings plus `apiKeyHelper`
  (`'<hub>/bin/secret' <secret>`), `skipWebFetchPreflight: true`, and an `env` block (provider keys win) with
  `ANTHROPIC_BASE_URL`, `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL`, `ANTHROPIC_SMALL_FAST_MODEL`,
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`. Never `CLAUDE_CODE_SUBAGENT_MODEL`,
  never a key.
- Config dir `<hub>/.local/providers/<p>` holds memory links like `bin/setup`'s:
  `projects/<encode_path hub>/memory -> <hub>/memory`, `projects/<encode_path dir>/memory -> <hub>/<F>/memory`.
- Agents: front matter `provider:` absent or equal stays in `--agents`; another provider is left out, with
  `work: delegatable (not in --agents): <name> (provider <p>)` on stderr.
