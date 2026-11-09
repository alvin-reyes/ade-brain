# Developer knowledge

- 2026-11-09: a test that runs a fake `claude` must `unset CLAUDE_CONFIG_DIR HUB_CLAUDE_CONFIG_DIR` first. The agent's own shell exports `CLAUDE_CONFIG_DIR`, so a launch without the prefix inherits it, and a fake that writes `settings.json` there overwrites the developer's real Claude settings (it happened once in SP's mutation run). The fake in `tests/test_providers.sh` also refuses to write outside the test's temp dirs.
- 2026-11-09: bin/work's launcher runs through osascript; a stub must run it with plain `bash "$L"`, not `bash -l`, or the login profile resets PATH and the real `claude` runs.
- 2026-11-09: don't patch bin/ scripts with a shell heredoc whose delimiter is `PY`: bin/work embeds `<<'PY'` blocks, so the outer heredoc ends early. Put the patch script in a file.
- 2026-11-09: `bash tests/test_providers.sh <check> ...` runs single checks, which helps for red-first evidence.
