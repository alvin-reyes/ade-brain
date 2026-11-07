# 0001: Auto sync on by default

- Status: Accepted
- Context: hub files (STATE.md, journal, memory) changed in several terminals were only pushed when someone ran
  `bin/sync --yes`, so a second Mac or a fresh clone saw stale context.
- Decision: `bin/sync --auto` runs every 30 minutes (launchd) and at each focus session end, on by default.
  `HUB_AUTO_SYNC=0` in hub.conf turns both off. It refuses to run without gitleaks or the `.githooks` pre-commit,
  scans every commit it would push, never force-pushes, and leaves `.mcp.json` out of its paths.
- Consequences: hubs stay current without a manual step. A Mac without gitleaks or `bin/setup` fails every run
  quietly (only `sync.log` shows it). Unattended pushes rely on the secret checks, so those stay mandatory.
