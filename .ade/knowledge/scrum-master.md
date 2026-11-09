# Scrum Master knowledge

- 2026-11-09: macOS has no `timeout` on PATH by default. A test that wraps a command needs lib.sh's `timeout` (it has a fallback) or a manual watchdog; a bare `timeout` exits 127 and looks like a pass-or-fail for the wrong reason.
