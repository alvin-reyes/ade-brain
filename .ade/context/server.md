# The server install (contract, story V2)

`ade server install` and `ade server status` (ade-cli) run `<hub>/bin/server install|status` in the hub's checkout on the
VPS. ade-cli clones the hub first; `bin/server` refuses a hub that is not a git checkout. Linux only (`platform`, exit 2
elsewhere); never as root (exit 2); needs `sudo` (`sudo -v`, exit 2 without).

## `bin/server install [--dry-run] [--accept-risk <row>]...`
1. **Safety rows**, read-only, printed as `<OK|FAIL|ACCEPTED> <row> <detail>`; any FAIL that is not accepted exits 1
   before anything changes:
   - `ssh-password`: `sudo sshd -T` has `passwordauthentication no`
   - `ssh-root`: `sudo sshd -T` has `permitrootlogin no` (`prohibit-password` fails)
   - `firewall`: `sudo ufw status` is active and every ALLOW rule is `22`, `22/tcp` or `OpenSSH` (v4 or v6)
   - `upgrades`: `systemctl is-enabled unattended-upgrades` is `enabled` and
     `${AGENT_APT_CONF_DIR:-/etc/apt/apt.conf.d}/20auto-upgrades` sets `APT::Periodic::Unattended-Upgrade "1"`
   `--accept-risk` takes those row names only (exit 2 otherwise). The rows are checked, never changed.
2. **Packages**: `server_packages` (apt, the distribution's versions): `git python3 tmux curl ca-certificates nodejs npm
   ufw unattended-upgrades xvfb x11vnc novnc websockify` (the last four for the browser sign-in view, V3); only the missing ones (`dpkg-query`) with `sudo apt-get install -y -q --no-install-recommends`.
3. **Tools**, only when missing (any version present is left alone), pinned by `server_pin`: gitleaks `8.30.1` (release
   tarball checked against the release's checksums file, into `~/.local/bin`), bun `1.3.9` (`bun.sh/install`), Claude
   Code `2.1.330` (`claude.ai/install.sh`), and Playwright's Chromium with its system libraries (`playwright` `1.64.1`,
   story V3, `.ade/context/browser.md`).
4. **Hub**: the code folder `${AGENT_CODE_DIR:-~/Project}` (bin/work clones each checkout there on first use) and
   `bin/schedule install` when any job is absent (`bin/schedule status`).
5. Prints the one manual step: `claude` (the Pro or Max login, over SSH), then `bin/keys set telegram`.

A rerun on a set-up host changes nothing. Nothing listens on a public port: Telegram, Remote Control and git connect out.
`--dry-run` prints each changing command as `+ <command>` and changes nothing; it exits as the install would (1 on an
unsafe host, after printing the whole plan).

## `bin/server status`
`== services` (the `bin/schedule status` lines), then `last sync` and `last monitor` (the time of
`$(state_dir)/logs/sync.log` and `monitor.log`, or `never`), `disk` (free and used for `$HOME`) and `browser` (V3). It
reads no secret.
