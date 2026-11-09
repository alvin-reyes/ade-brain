# Scrum Master knowledge

- 2026-11-09: macOS has no `timeout` on PATH by default. A test that wraps a command needs lib.sh's `timeout` (it has a fallback) or a manual watchdog; a bare `timeout` exits 127 and looks like a pass-or-fail for the wrong reason.
- 2026-11-09: bin/work launches through osascript in Terminal and the launcher file deletes itself on exit, so provider tests need an osascript stub that copies the launcher before running it. The provider's plain-claude rule is by name, so a fake named claude on PATH passes it.
