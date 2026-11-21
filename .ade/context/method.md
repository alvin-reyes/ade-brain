# The method comes from ade-method (story C1)

ade-method (`https://github.com/better-ade/ade-method`) is the only home of the method (owner, 2026-11-21; the story cites ADR 0004). The hub keeps no
copy of its own: `bin/method sync` copies it in, and a test fails when the copies drift.

- **Files:** ade-method's `rules.md` becomes `.ade/rules.md`; its `bmad/custom/*.toml` become `_bmad/custom/*.toml`
  (`_bmad/custom/.gitignore` and `*.user.toml` are the hub's own and are left alone). Edit them in ade-method, not here.
- **Pin:** `method_pin` in `bin/lib.sh` (now `v2.0.0`) is the tag the template pins. `bin/init` writes it to hub.conf as
  `HUB_METHOD_REF` and syncs at it. To move the template to a new release: change `method_pin`, run
  `bin/method sync <tag>`, commit the result (`template_matches_pin` in `tests/test_method.sh` checks both agree).
- **Ref:** `bin/method sync [ref]` uses the argument, else `HUB_METHOD_REF`, else `method_pin`. A tag or branch name.
- **Repo:** `method_repo` in `bin/lib.sh`; `AGENT_METHOD_REPO` overrides it. Tests always point it at a local fixture
  (`make_hub` builds one from the template's own files; `method_repo` in `tests/helpers.sh` builds tagged fixtures).
- **Record:** `.ade/method-version` holds `ref <ref>`, `commit <sha>` and one `file <sha256> <path>` line per copied file.
- **Check:** `bin/method check` is offline: it compares each recorded file's sha256, prints `differs: <path>` for each
  changed or missing one and exits 1; 0 when all match. `bin/doctor` shows it as one `method` row (file names only).
- **Failure:** an unknown ref, an unreachable repo or a ref with no `rules.md` exits 1 before any hub file changes.
  `bin/init` offline warns and keeps the template's copy (which is the pinned ref's).
