# Access: {{NAME}}

Names and locations only. Never a key, token or password.

## Code
| Repo | Checkout | Default branch | Who merges | CI |
|---|---|---|---|---|

## Machines
| Name | Host / how to reach | What runs there | Safe read-only commands |
|---|---|---|---|

## Services
| Service | Where (location id, channel, URL) |
|---|---|

## Credentials (locations only)
| What | Where it lives (`bin/secret <name>`, a server file, a wp option) |
|---|---|

## Permissions
- Claude may run itself: read-only checks listed above.
- Staged for {{OWNER}} to run: production changes (scripts in this folder).
- Never: printing secrets, sending to real contacts in tests, committing to the hub from a client repo.

## Undo
| Live change | Rollback command |
|---|---|
