# Dispatch (config key and contract, story C3)

- `bin/dispatch [--approve <ref>] <folder>` reads `node <checkout>/_bmad/ade-runtime.mjs tickets --project-root <checkout> next`
  (the folder's one Code repo checkout, `repos_of`) and starts ready tickets with
  `bin/work --role builder --name <name> --prompt "bmad-build <ref>" <folder>`.
- `HUB_DISPATCH_MAX` (hub.conf or the environment): the most builder sessions at once. Unset = 1; above 2 = 2; not a whole
  number = exit 2. Free slots = it less the running `bin/sessions` rows with ROLE `builder` (and any running ticket session
  of another role).
- Only `ready_to_start` rows are started; only risk `low` or `medium` with no `hitl` (nor a `hitl` drift). Anything else
  (high, unset or unknown risk, hitl) prints `waiting for the owner: <ref> (<why>); ...` and is started only by `--approve <ref>`.
- A ref takes `A-Za-z0-9._/-` only (else skipped); the session name is the ref with every character outside `A-Za-z0-9._-`
  turned into `-` (`demo/01-a.md` -> `demo-01-a.md`). A running session of that name is never started again.
- Journal (bin/journal): one line per run, `dispatch: started <refs|none>; waiting for the owner: <refs|none>`
  (plus `; bin/work failed for <ref>`); `--approve` writes `dispatch: started <ref> (approved by the owner)`.
- Exit: 0 done; 1 refused (no or several checkouts, no BMAD, no node, `tickets next` failing or unreadable, bin/sessions
  failing, `--approve` of a ticket that is not ready, running or has no free slot) or a bin/work start failed (no more starts
  that run); 2 usage or unknown folder.
