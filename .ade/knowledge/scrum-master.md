# Scrum Master knowledge

- 2026-11-09: macOS has no `timeout` on PATH by default. A test that wraps a command needs lib.sh's `timeout` (it has a fallback) or a manual watchdog; a bare `timeout` exits 127 and looks like a pass-or-fail for the wrong reason.
- 2026-11-09: `bash tests/run.sh` captures each test's output with `$( )`, so a background child that keeps a test's stdout open makes the whole suite wait. Detached work must redirect its stdio. macOS has no `setsid` CLI; python3 `os.setsid()` does the job.
