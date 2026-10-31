# {{NAME}}

{{OWNER}}'s AI **{{TITLE}}** for **{{CLIENT}}**, made from
[ai-agent-hub-template](https://github.com/alvin-reyes/ai-agent-hub-template). It holds the **context, state and
history** of the work and runs Claude Code agents that know them. Client code stays in its own repos.

## Use it

1. `bin/setup` once per Mac (links Claude's memory and the BMAD skills, sets the git hooks); `ollama pull nomic-embed-text`
   and `bin/brain index` for searchable memory.
2. `bin/doctor` until what you need is OK. Store secrets with `bin/secret --set <name>`.
3. Start `claude` at the repo root. The SessionStart hook prints every folder's state and the recent journal.
4. Optional: `bin/schedule install` for the weekday morning briefing.

## Folders

{{FOLDER_LIST}}

## Commands

| Command | Does |
|---|---|
| `bin/context [folder]` | every folder's state, or one folder's state and journal |
| `bin/work [opts] <folder> [repo]` | deep work in a new Terminal in the folder's repo checkout |
| `bin/journal <folder> "<text>"` | one dated journal entry |
| `bin/new projects/<name>` / `ops/<name>` | a new folder plus its agent |
| `bin/brain search "<words>"` | search every section of the hub (keywords + meaning); `bin/brain index` refreshes |
| `bin/remote <cmd>` | a command on the remote box over SSH |
| `bin/secret <name>` | a secret from the Keychain (`--set`, `--has`, `--forget`, `--list`) |
| `bin/doctor` | what this Mac can reach; never prints a secret |
| `bin/briefing`, `bin/schedule install` | the morning briefing, and its weekday launchd job |
| `bin/work --model M --agent-model [name=]M` | override this hub's models for one session (defaults in `hub.conf`) |
| `bin/sync`, then `bin/sync --yes` | review, then commit and push hub files only |

Rules: [CLAUDE.md](CLAUDE.md). Verification: `bash tests/run.sh`.
