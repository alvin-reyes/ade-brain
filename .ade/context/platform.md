# The platform layer (contract, story V1)

The same hub runs on macOS and on Linux (Ubuntu, a VPS). Every macOS-only call in `bin/` goes through `bin/lib.sh`;
`tests/test_platform.sh` greps `bin/` (comments aside) for `security `, `launchctl`, `osascript` and `stat -f` outside it.

## Detection
- `platform` prints `macos` or `linux` (`uname -s` Darwin = macos). `AGENT_PLATFORM=macos|linux` overrides it (tests:
  `make_hub` exports `macos`, so the suite tests the macOS behaviour with its stubs on any machine;
  `tests/test_platform.sh` sets `linux` with fakes).
- File facts follow the machine's own `stat` (GNU `-c` or BSD `-f`, probed once): `file_mtime`, `file_inode`,
  `file_mode` (octal bits, `700`), `file_owner` (uid).

## Secrets (`bin/secret`, `bin/keys`, `bin/doctor`)
- `secret_store`: `keychain` (macOS), else `pass` when `pass` is on PATH and `${PASSWORD_STORE_DIR:-~/.password-store}/.gpg-id`
  exists, else `file`. `secret_store_label`, `secret_store_refusal` (empty = usable).
- pass: entries `ade/<service>/<name>` (service = `keychain_service`); set with `pass insert -m -f` on stdin.
- file store: `${AGENT_SECRETS_DIR:-${XDG_CONFIG_HOME:-~/.config}/ade/secrets}/<service>/<name>`; folders made 0700,
  values 0600, written through a 0600 temp file and `mv`. A folder that is not 0700 and the user's, or a value file that
  is not 0600, refuses (exit 1, with the `chmod`). `bin/doctor` shows it as `WARN secrets ... the weaker store`.
- `secret_get`, `secret_has`, `secret_put <name> <value>` (a shell function argument, then read back), `secret_forget`,
  `secret_names`. Names outside the Keychain are `[A-Za-z0-9][A-Za-z0-9._-]*` (exit 2 otherwise). A value is never an
  argument of another program, in a child's environment, or in a log.

## Scheduled jobs (`bin/schedule`)
- macOS: launchd, unchanged (`launchd_bootout`, `launchd_bootstrap`, `launchd_loaded` in `bin/lib.sh`).
- Linux: systemd **user** units in `${AGENT_SYSTEMD_USER_DIR:-${XDG_CONFIG_HOME:-~/.config}/systemd/user}`:
  `ade-<hub>-<job>.service` (oneshot, `ExecStart=/bin/bash "<hub>/bin/<job>"`, sync with `--auto`, logs appended to
  `$(state_dir)/logs/<job>.log`) and `ade-<hub>-<job>.timer` (briefing `Mon..Fri *-*-* HH:MM:00`, monitor and sync
  `*:0/30`, `Persistent=true`). With `HUB_CHAT=telegram`: `ade-<hub>-chat.service` (`bin/chat start`, `Restart=always`),
  removed on install otherwise; `HUB_AUTO_SYNC=0` removes sync. Install runs `systemctl --user daemon-reload`, turns
  lingering on (`loginctl enable-linger`, once), `enable --now` each unit; uninstall `disable --now` and removes the files;
  status prints `loaded|absent <unit>` from `is-active`.

## Focus sessions (`bin/work`) in tmux
- `AGENT_TERMINAL=tmux` (default on Linux; any platform on request, ade-cli A6 `ade ui`): the session name is `--name N`,
  else the folder name, with `.` and `:` turned into `_` (`tmux_name`). The hub session is `ade-<hub>` (`tmux_hub_session`).
- When `ade-<hub>` exists: `tmux new-window -d -t =ade-<hub>: -n <name> -c <dir> "bash -l '<launcher>'"` (left in the
  background). Otherwise: `tmux new-session -d -s <name> -c <dir> "bash -l '<launcher>'"`; attach with `tmux attach -t <name>`.
- A tmux session `<name>`, or a window `<name>` in `ade-<hub>`, already open: exit 3 (`--force` opens another). tmux
  missing: exit 1 (a dry run still prints the command). `AGENT_TERMINAL=terminal|iterm` on Linux: exit 2.
- `bin/sessions` lists it from the launcher registry, as for any focus session.

## Notifications (`bin/monitor`, `bin/briefing`)
- macOS: `desktop_notify <title> <text>` (osascript), unchanged (`MONITOR_QUIET=1` silences it).
- Linux: a new ALERT is written once as a note event from the monitor's folder to `main` (`bin/notify`, `.ade/context/events.md`),
  text `<the ALERT line> (monitor <script>)`; a chat channel (C5) forwards it. `bin/briefing` shows no notification there.

## CI
- `.github/workflows/ci.yml` runs `bash tests/run.sh` on `macos-latest` and on `ubuntu-latest` (job `ci-linux`), both
  through `better-ade/.github` `verify.yml@v1`.
