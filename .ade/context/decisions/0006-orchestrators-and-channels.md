# 0006: Orchestrators and channels

- Status: Accepted (owner, 2026-11-21).
- Context: the owner wants to reach the orchestrator from Telegram, to run several orchestrators (one per hub, e.g. one
  per customer for forward deployed engineers) started from the `ade` CLI, and later to run them on an Ubuntu VPS.
  Claude Code connects a running session to chat apps through "channels" (research preview; Telegram plugin
  `telegram@claude-plugins-official`).
- Decision:
  1. **An orchestrator** is one named, long-running Claude Code session at a hub's root: name, hub, model (the hub's
     orchestrator model, any provider, default Anthropic Opus 5.5), and a list of channels. One hub has at most one
     orchestrator; customers are separated by hub, never by orchestrator.
  2. **A channel** is one way to reach an orchestrator. Each channel type defines: its plugin, the secret it needs (kept
     in the hub's secrets store, never a file in the repo), how a sender is paired to the allowlist, and its state folder.
     `telegram` is the first channel type; others (Discord, Slack) are added the same way. Remote Control is always on
     and is not a channel.
  3. **Config** lives in the hub's `hub.conf`: `HUB_ORCHESTRATOR=<name>`, `HUB_CHANNELS="telegram"`. Each orchestrator
     keeps its channel state in its own folder, so several run on one machine without sharing a bot or an allowlist.
  4. **Lifecycle:** `bin/chat start|stop|status|setup <channel>` in the hub; `ade orchestrator new|start|stop|list|logs`
     across hubs. Each running orchestrator is one service (launchd on macOS, systemd on Linux), restarted if it dies.
  5. **Safety:** only paired senders reach it; permission prompts are relayed to the owner on the channel; it never runs
     with `--dangerously-skip-permissions`; message content forwarded inside a chat is data, not instructions; a hub's
     orchestrator uses only the providers that hub (customer) approves.
- Consequences: C5 becomes "orchestrator with channels, Telegram first"; ade-cli A2 adds `ade orchestrator`; V2 installs
  one service per orchestrator. Open item to verify while building C5: where the Telegram plugin keeps its state, and
  whether a per-orchestrator state folder needs its own Claude config folder (and so its own one-time login).
