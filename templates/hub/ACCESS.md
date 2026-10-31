# Access: {{NAME}} (shared)

Names and locations only. Never a key, token or password. Folder ACCESS.md files add their own rows.

## Code
| Repo | Checkout | Default branch | Who merges | CI |
|---|---|---|---|---|
{{REPO_ROWS}}
## Remote box
| What | Value |
|---|---|
| SSH | `bin/remote <cmd>`: {{REMOTE}} |
| Staging URL | {{STAGING}} |

## Services
| Service | Where (URL, account id) |
|---|---|

## Credentials (locations only)
| What | Where |
|---|---|
| Stored secrets | `bin/secret <name>` (Keychain service `{{NAME}}`): {{SECRETS}} |
| GitHub | `gh auth login` |

## Permissions
- Agents may run: `bin/doctor`, read-only `bin/remote` commands, the repos' tests, reads from services.
- {{OWNER}}'s word for that change: deploys, writes on shared systems, sending messages, anything production.
- Never: printing secrets, real people's data in tests, committing to the hub from a client repo.
