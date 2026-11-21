# Browser automation on the server (contract, story V3)

Agents on the server use the ade-skills `browser` plugin's Playwright MCP with headless Chromium. The plugin owns the MCP
server and its ask-first rules (no form submit, purchase or message without the owner's word, asked over Telegram on the
server); the hub only says where each folder's browser state and files live. `ade browser login|forget` (ade-cli) runs
`<hub>/bin/browser login|forget`.

## `bin/browser`
- `mcp <folder>` prints one JSON object `{"args": [...]}`: the arguments the plugin adds to its Playwright MCP command for
  that folder: `--browser chromium --headless`, then `--isolated` (default: no logins) or `--user-data-dir <profile>`
  (profile mode), then `--output-dir <hub>/<folder>/reports/browser` (screenshots and downloads; made; refused, exit 1,
  when it resolves outside the folder; `projects/*/reports/browser/` and `ops/*/reports/browser/` are in `.gitignore`, so
  nothing there syncs to the hub's git). No flag that loosens the plugin's rules is ever added.
- `login <folder> <url>` (profile mode only, else exit 2 naming the hub.conf switch; `http(s)` URLs only): Chromium on the
  folder's profile on a private Xvfb display (`-nolisten tcp`), x11vnc on `-localhost` with a one-time password read
  from a 0600 file it deletes (`-passwdfile rm:<file>`, never an argument), noVNC through `websockify` on
  `127.0.0.1:${HUB_BROWSER_VIEW_PORT:-6080}`. It prints the `ssh -N -L <port>:127.0.0.1:<port> <user>@<server>` tunnel, the
  `http://localhost:<port>/vnc.html` address and the password; the owner signs in. Enter, or closing the browser, stops
  every process it started. Never a public port.
- `forget <folder>` deletes that folder's profile (a link is refused and not followed).
- `status` prints `ready  chromium <path>` or `missing ...` (exit 1).

## Profiles
- `${AGENT_BROWSER_DIR:-${XDG_CONFIG_HOME:-~/.config}/ade/browser}/<agent name>/` (`projects/acme` -> `acme`, `ops/x` ->
  `ops-x`), 0700 and the user's (refused otherwise), one per folder, never shared.
- Profile mode is opt-in per folder in `hub.conf`: `HUB_BROWSER_PROFILE_<NAME>=1` (`<NAME>` = the agent name upper-case,
  `-` and `.` as `_`). Every `HUB_BROWSER_PROFILE_*` is unset before `hub.conf` is sourced, so the environment cannot turn
  it on.
- Chromium is Playwright's (`${PLAYWRIGHT_BROWSERS_PATH:-~/.cache/ms-playwright}/chromium-*/chrome-linux*/chrome`,
  `browser_chromium` in `bin/lib.sh`); a system Chromium does not count.

## Install and status (`bin/server`, `.ade/context/server.md`)
- `bin/server install` adds `xvfb x11vnc novnc websockify` to its packages and, when Chromium is missing, runs
  `npx -y playwright@1.64.1 install --with-deps chromium` (Playwright installs the system libraries with sudo).
- `bin/server status` adds a `browser` row: `ready (headless Chromium, <path>)` or `missing (bin/server install)`.
