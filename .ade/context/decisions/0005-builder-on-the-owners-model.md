# 0005: The builder runs on the owner's model (default Opus 5.5), from ade-method

- Status: Accepted (owner, 2026-11-21). Supersedes the "code is still written only by Opus" part of ADR 0003.
- Context: ADR 0003 had bmad-build pass an explicit `opus` to its implementation subagent. Since story C1 the hub takes
  `_bmad/custom/` from ade-method (ADR 0004), and ade-method v2.0.0's `bmad-build.toml` makes the builder the model the
  owner configured: any provider, default Anthropic Opus 5.5. A non-Anthropic builder model is not launched through
  the Agent tool; the coordinator runs the build as a focus session on that model.
- Decision: code is written by the builder model the owner configures (default Opus 5.5), as ade-method's overrides
  say. Review scales with the change's risk (rules.md section 3): low has no review lenses; medium runs the quick
  review on the subagent default model (no model passed); high runs the thorough review on the builder's model. The
  rest of ADR 0003 (the subagent default, quick bmad-code-review) stands.
- Consequences: the hub no longer promises Opus for every build; a hub whose owner sets another builder model gets
  that model. Changing this wording is done in ade-method and reaches the hub through `bin/method sync`.
