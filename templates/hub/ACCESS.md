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

If secrets come from the 1Password CLI (`op read`, `op run`) through the desktop-app integration: `op whoami` says the
account is not signed in even when it works, so test with `op vault list`. Each new shell or session may raise its own
approval prompt in the app; approve it there and run the command again.

## Permissions
- Agents may run: `bin/doctor`, read-only `bin/remote` commands, the repos' tests, reads from services.
- {{OWNER}}'s word for that change: deploys, writes on shared systems, sending messages, anything production.
- Never: printing secrets, real people's data in tests, committing to the hub from a client repo.
