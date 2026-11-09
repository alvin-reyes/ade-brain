# Auto sync and monitors (config keys and contracts)

- `HUB_AUTO_SYNC` (hub.conf, written by `bin/init --auto-sync on|off`): `1` (default when absent) or `0`. `0` turns off
  the session-end push (`bin/session-end`), the launchd sync job (`bin/schedule install` leaves it out and removes an
  earlier one) and `bin/sync --auto` itself (logs "skipped: auto sync is off", exit 0).
- Env overrides (tests): `AGENT_AUTO_SYNC` (session-end only; wins over `HUB_AUTO_SYNC`), `AGENT_SYNC_CMD` (replaces
  the command session-end starts), `AGENT_SYNC_LOG` (default `$(state_dir)/logs/sync.log`), `AGENT_SYNC_LOCK`
  (default `$(state_dir)/sync.lock`). `tests/helpers.sh` sets all three off/temp in `make_hub`.
- `bin/sync --auto` exit: 0 = synced, nothing to do or skipped (lock held, git busy, off); 1 = refused or failed.
  One log line per run.
- The sync lock (`AGENT_SYNC_LOCK`) is taken by `bin/sync --auto` (never waits), `bin/sync --yes` and the
  `bin/session-end` commit step. `AGENT_LOCK_WAIT` (default 30): seconds `--yes` and session-end wait for a busy lock
  (attempts are counted, so the wait is at least that long). `bin/sync --yes` exits 1 with `another sync is running`
  on stderr when the lock stays busy (it used to never wait or fail on the lock). A stale lock (owner pid dead, or over
  120 minutes old) is removed under a guard dir `<lock>.gc`; only a lock whose pid file is the caller's own pid is
  released by it.
- `AGENT_SESSION_END_LOG` (default `$(state_dir)/logs/session-end.log`): one line per `bin/session-end --since` run:
  UTC time, folder, `since=<epoch>`, outcome (`committed`, `nothing to commit`, `failed: commit refused`,
  `skipped: sync lock busy`, `refused: <reason>`).
- launchd jobs: `ai.agent-hub.<hub name>.{briefing,monitor,sync}`, templates `launchd/<job>.plist.template`.
- Monitors: executable `projects/*/monitors.d/*.sh`, `ops/*/monitors.d/*.sh`; read-only; first output line = status
  (leading `Ddd HH:MM TZ |` or `YYYY-MM-DD HH:MMZ |` stripped before comparing); `ALERT...` lines alert. State in
  `$(state_dir)/monitor-state/`. `MONITOR_TIMEOUT` (300 s), `MONITOR_QUIET=1` (no notification).
- `bin/changes [folder]` (UserPromptSubmit in the hub root and every folder): one snapshot per session,
  `$(state_dir)/changes-seen.<session_id>` (from the hook JSON on stdin), removed after 7 days.
