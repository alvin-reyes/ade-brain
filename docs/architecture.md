# ai-agent-hub-template: architecture

A template for a Claude Code "agent hub": one private repo of Bash and Markdown that holds the context, state and
history of one technical persona's work for one client. `bin/init` turns it into a hub: it writes `hub.conf` (who the
agent is and what it can reach), renders `CLAUDE.md`, `ACCESS.md`, `README.md` and the persona agent from
`templates/hub/` and `personas/<slug>.md`, and creates one folder per work area (`projects/<name>`, `ops/<name>`) with
CLAUDE.md, ACCESS.md, STATE.md, `memory/` and a named agent. Client code lives in its own repos, never in the hub.

Lineage: generalized from two working hubs (a multi-client ops hub and a single-client staff-engineer hub).

## Verification command

```
bash tests/run.sh
```

Green means every `tests/test_*.sh` prints `ok` and the command exits 0. Changing it needs the owner's approval.
