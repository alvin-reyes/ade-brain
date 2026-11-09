# Plan: agents on other AI CLIs (Codex, Gemini CLI)

Status: revision 7, 2026-11-09. Revision 6 was approved by the owner after passing review. Revision 7 adds
DeepSeek, GLM and Meta Muse as providers for the Claude engine ("Providers" below). The owner approved it on
2026-11-09, subject to its adversarial review, which it passed the same day. The rest is unchanged.

History:

| Revision | Outcome |
|---|---|
| 1 | Approved by the owner, then blocked by review 1 (3 blockers, 12 majors) |
| 2 | Blocked by review 2 (1 new blocker, 6 new majors) |
| 3 | Blocked by review 3: the launcher sketch failed under a real pty, plus inbox races |
| 4 | Blocked by review 4: session end lost when the window closes, plus inbox, watchdog and gate gaps. Its prototype confirmed the Python launcher approach works. |
| 5 | Blocked for S3b only (busy-checkout check, `.git/config` denylist). Everything else passed, with the launcher and watchdog fixes proven under a real pty. Minors carried into stories below. |

After review 3, the owner chose to keep the full scope. This revision answers all five reviews (tables at the end)
and needs the owner's re-approval. Verification command unchanged: `bash tests/run.sh`.

**Method change after review 3:** the plan no longer specifies untested process-control code. Anything that touches
terminals, process groups or signals is proven by a pty test before its story builds on it. The launcher mechanism
below is the one review 3 ran successfully under a real pty (`launch_ok.sh` in the reviewer's scratch dir). Review 4 prototyped it (`r4/launch.py`, `r4/harness.py`) in both topologies; its fixes are folded in.

## Goal

A hub can run agents on more than one AI CLI, each with its own model: Claude Code (today, and still the default),
OpenAI's Codex CLI and Google's Gemini CLI.

1. **A focus session on another engine.** `bin/work --engine codex projects/app` opens the folder's focus terminal in
   Codex. The session gets the hub's rules and memory. It writes STATE, memory and journal through a per-launch inbox
   that session end applies safely.
2. **Delegation.** A specialist agent declares `engine:` and `model:`. A session hands it a task with `bin/agent`,
   which runs it headless on that CLI and model and returns the answer as framed, untrusted data. A delegated agent is
   read-only by default; `write: true` is allowed only in a listed client checkout, with its hook paths protected.

**Owner decisions (2026-11-09):**
- Engines are opt-in per hub (`HUB_ENGINES_ALLOWED`, default `claude`).
- The persona agent stays on Claude.
- Full scope is kept.
- **Claude only for now (2026-11-09).** No testing with Codex or Gemini until the owner says so. S0 answers only the
  Claude items (5, 8, 10, 14, 21, and the Claude parts of 15, 16 and 20). Stories that need Codex or Gemini answers wait.
  What can go ahead: S1, and S3a with `engine: claude` only (Claude agents on their own models, delegated headless).
- **DeepSeek, GLM and Meta Muse (2026-11-09).** Supported as providers behind Claude Code, not as separate CLIs. See
  "Providers". **Priority:** S0 item 21 and story SP come first, then S3a; S1 runs alongside.

**Not in scope:**
- sub-agents of a non-Claude session;
- non-Claude sessions in folders without a code repo (see "No-repo folders");
- Windows and Linux;
- billing;
- API keys stored in the hub.

## S0: what must be settled before any product code

S0 is a spike on the current Codex and Gemini releases. Codex is not installed here, and the local Gemini (0.1.14) is
far too old. It records answers in `.ade/context/engines.md`, including the minimum version per engine. It ends with a
go or no-go per engine per feature: session, inbox, delegation, delegation with write, and native hooks.

**Sandbox and paths:**
1. Can a session started in the client checkout get exactly one extra writable directory, its per-launch inbox,
   without a full-access or yolo flag? Can the sandbox create a hard link from the inbox to a hub file such as
   `hub.conf`?
2. Can a session run `bin/agent` (which needs the network and writes `.local/`) from inside its sandbox? Does a
   sandbox nest inside another engine's, or inside Claude's? What timeout does each engine's shell tool have, and
   which signal does it send when that timeout hits?
3. In a read-only run, what can the engine read: `~/.ssh`, `HUB_REMOTE_KEY`, other repos? Can it reach the Keychain
   through `security`?

**Read-only that holds:**
4. Which flags or overrides beat the user's config and the workspace's config (`.gemini/settings.json`, `.codex/`,
   MCP servers, `GEMINI.md`, `AGENTS.md`)? Can MCP servers and workspace context files be turned off for a run?
5. How does a headless Claude run ignore the cwd's and the user's settings and hooks? Which tool list makes it
   read-only?
6. Does Gemini have a write mode short of yolo? Can each engine's write mode deny writes to named directories?
7. **The smoke check, by hand.** A read-only run is asked to create a file, and must fail. A workspace
   `.gemini/settings.json` or `AGENTS.md` that tells the engine to run a command must be ignored. These checks become
   `bin/doctor --deep`.

**Process behaviour:**
8. Exit codes for success, model error and auth failure. Does a missing login fail fast?
9. What do Ctrl-C, SIGHUP and a closed terminal do to the engine? Do its tool subprocesses stay in its process group?
   Does its TUI need to be the terminal's foreground process group?
10. How to get only the final answer on stdout from a headless run.

**Context, hooks and versions:**
11. A system-instructions channel outside the client repo. Fallback: the first prompt. Does it survive compaction?
12. Do native SessionStart and SessionEnd hooks fire? Where can their config live? What does their payload carry?
13. Codex's trusted-directory and git check when started in a hub subfolder.
14. Does each engine's shell tool pass the environment through?
15. **Auth, for Claude, Codex and Gemini.** The exact env var names and files each needs for headless auth:
    - `CLAUDE_CONFIG_DIR`, and the `ANTHROPIC_*` names that `--claude` wrappers use;
    - Codex's `auth.json` and `OPENAI_API_KEY`;
    - Gemini's OAuth files, `GEMINI_API_KEY`, and Vertex.

    Does an owned config dir move the login away? Which proxy and CA vars are needed?
16. Versions: how each engine is installed and auto-updated (brew, npm, its own self-update), and whether it can be
    pinned. Which versions changed the writable-root or include-directory flags?
17. Can a hard link created in the inbox be written through to the hub file it points at?
18. Do native hooks run inside the engine's sandbox?
19. Which proxy variables, including lowercase ones, does each engine honour?
20. Claude Code's session registry (`<CLAUDE_CONFIG_DIR>/sessions/<pid>.json` with `cwd`, `pid`, `procStart` on recent
    versions): is it stable enough to detect a Claude session in a checkout, across every config dir this Mac uses?
21. Providers (DeepSeek, GLM, Muse) behind Claude Code: the checklist in "Providers" below.

**If S0 says no:**

| No to | Then |
|---|---|
| 1 | The session gets no hub writes. Its rules say: don't update STATE or memory; end with a summary in the terminal. Session end journals only commits. |
| 17: a hard link can be written through | No inbox for that engine (its sessions get no hub writes), unless the inbox can live on a different volume from the hub. |
| 2 | `bin/agent` is called from Claude sessions only. |
| 3: it can read `~/.ssh` or `HUB_REMOTE_KEY` | Delegation on that engine is refused unless the owner accepts that by name in ADR 0002. |
| 4 or 7 | That engine gets no delegation. If workspace config can't be turned off, it gets no delegation in client checkouts. |
| 5 | No headless delegation on Claude. |
| 6 | `write: true` is refused for that engine. |
| 9: the TUI won't run as the foreground group we give it | That engine gets no focus sessions. |
| 9: its tool subprocesses leave its process group | That engine gets no delegation (the watchdog covers only the group). |
| 20: the registry isn't usable | Write mode needs the owner's setting `HUB_WRITE_UNCHECKED=1` in `hub.conf` (unset before sourcing, like the allowlist); a flag the calling model could pass would confirm nothing. Without it, write mode is refused. This is a weak guard, stated in ADR 0003: the owner's concurrent edits to the protected set are reverted and quarantined, not lost. |
| 15: auth needs env vars | Those exact names go on the engine's passthrough list. |

## Design

### Providers: DeepSeek, GLM and Meta Muse behind Claude Code (story SP)

DeepSeek and Zhipu (GLM, through z.ai) document running Claude Code against their Anthropic-compatible endpoints, and
Meta's Model API reportedly offers one for Muse (unconfirmed until S0 item 21), by setting `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` and mapping Claude Code's model slots to their
models. So the CLI stays Claude Code and the hub's hooks, `--agents` and session end work as today. Only the
provider behind it changes. Remote Control does not, by default (rule below). This needs no Codex or Gemini answers.

**Providers.** `anthropic` (default: Claude Code's own login), `deepseek`, `glm`, `meta` (Meta's Muse models; named
`meta`, not `muse`, so it isn't confused with the `muse` CLI login or muse.ai). A provider is a row in a table in
`bin/lib.sh`: base URL, the Keychain secret name for its key, and default model slots. Starting values (confirmed in
S0 item 21, since vendors rename models often):

| Provider | Base URL | Key (Keychain name, via `bin/secret`) | Default models |
|---|---|---|---|
| deepseek | `https://api.deepseek.com/anthropic` | `deepseek-api-key` | per DeepSeek's Claude Code guide (`deepseek-v4-pro` / `deepseek-v4-flash` at the time of writing) |
| glm | `https://api.z.ai/api/anthropic` | `zai-api-key` | per z.ai's Claude Code guide (`glm-5.x` at the time of writing) |
| meta | **unconfirmed**: `https://api.meta.ai` per third-party guides; the exact host and path come from Meta's own docs in S0 item 21 | `meta-model-api-key` (doctor shows "Meta Model API key") | **unconfirmed**: `muse-spark-1.3` per third-party guides |

**Muse caveats.** The sources for Muse are third-party guides, not Meta's own docs, and they say Meta's endpoint
accepts only a subset of the Anthropic API that Claude Code routinely uses. S0 item 21 must confirm the endpoint
against Meta's developer docs and find which Claude Code requests fail. If plain Claude Code can't run against it,
`meta` gets a no-go for that feature (enforced, below) or is dropped, and the owner decides. The `meta` row ships in
SP only with at least one go; otherwise it moves to a later story, so SP is never blocked by it. No request carrying
the key goes to a host not confirmed from Meta's own docs. Base URLs are fixed in the `lib.sh` table; there is no
per-hub base URL override (no `HUB_<P>_BASE_URL`), now or later. The key is a Meta Model API key, not the `muse` CLI login. Unofficial bridges that drive a muse.ai
browser session are never used.

No trailing `/v1`: Claude Code appends `/v1/messages` itself.

**Choosing one.**
- `hub.conf`: `HUB_PROVIDER` (sessions, default `anthropic`) and `HUB_PROVIDERS_ALLOWED` (default `anthropic`), read
  only from `hub.conf` and unset before sourcing, like `HUB_ENGINES_ALLOWED`. A provider not in the list is refused
  (exit 2). DeepSeek, Zhipu and Meta are separate vendors, so the client's code and the hub's notes go to them; that is
  an owner decision per hub, recorded in ADR 0002, with each vendor's API terms on training and retention of inputs.
- `bin/work --provider glm <folder>` for one session; `--model` is that provider's model name.
- Agent front matter `provider: deepseek` (with `model:`), for delegation through `bin/agent`.
- `HUB_<PROVIDER>_MODEL` and `HUB_<PROVIDER>_SMALL_MODEL` override the defaults per hub. They are checked like
  `--model` (a slot alias or an id from the row); a stale value exits 2 instead of failing at runtime.

**How a session is started.**
- **Endpoint and models:** `ANTHROPIC_BASE_URL`, `ANTHROPIC_MODEL` and the slot variables
  (`ANTHROPIC_DEFAULT_OPUS_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL`,
  `ANTHROPIC_SMALL_FAST_MODEL`) come from the provider row. `CLAUDE_CODE_SUBAGENT_MODEL` is not set, so agents' own
  `model:` and `--agent-model` keep working through the slot aliases.
- **The key never sits in the environment if it can be avoided.** Environment variables are inherited by every hook,
  Bash tool command, MCP server and client-repo script the session runs, where one `printenv` puts the key in a
  transcript. S0 item 21 decides between, in this order:
  1. Claude Code's `apiKeyHelper` in a provider settings layer, calling `bin/secret <name>`: only Claude Code runs it,
     so no child process inherits the key. S0 checks it sends the auth header these endpoints expect.
  2. Claude Code's subprocess environment scrub (its current setting name), set so hooks, Bash tool commands and MCP
     servers don't receive `ANTHROPIC_AUTH_TOKEN`.
  3. If neither works, the key goes in `ANTHROPIC_AUTH_TOKEN` and the exposure is written into ADR 0002 as an owner
     decision. The README says so.

  S0 proves the chosen option with a hook and a Bash tool command that try to read the token and must not see it.
- **Fail closed.** The launcher reads the key (or runs the helper once as a check) into a variable before starting
  Claude Code. If `bin/secret` fails or returns nothing (missing key, locked Keychain, denied prompt), it prints the
  `bin/secret --set <name>` hint and exits; Claude Code never starts against a third-party base URL without that
  provider's key, so it can't fall back to the owner's Anthropic login there. The launcher file holds the
  `bin/secret` call, never the key.
- **Remote Control:** off for every provider other than `anthropic` (`--provider` implies `--no-remote`). The README
  already says it needs a claude.ai login (`README.md:110`), and if it did work, the session would also pass through
  Anthropic's relay. S0 item 21 records whether it works; enabling it later is an owner decision.
- **Models in a provider session:** `HUB_<P>_MODEL` replaces `HUB_MODEL`, which may be a full Anthropic model id.
  `--model` must be a slot alias (`opus`, `sonnet`, `haiku`) or an id from the provider's row; anything else exits 2.
  `--effort` is refused unless S0 item 21 shows thinking budgets work on that provider.
- **Wrappers:** `--provider` other than `anthropic` needs plain `claude`. If the resolved command is anything else,
  whichever source set it (`--claude`, `HUB_CLAUDE` or `AGENT_CLAUDE`), it exits 2. Tested with each of the three.
- **One settings file:** the provider layer (`apiKeyHelper`, and the base URL and slot variables in its `env` block)
  is merged with the folder's settings into one generated temp file passed as the single `--settings`, so the folder's
  hooks are kept. A test checks the merged file holds both. S0 item 21 confirms that this layer's `env` wins over an
  `env` block in the client checkout's or the user's settings; if it doesn't, provider sessions are refused in a
  checkout whose `.claude/settings*.json` sets `ANTHROPIC_BASE_URL`.
- **Nonessential traffic:** provider sessions set `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, so Claude Code sends
  no telemetry or update checks to Anthropic while talking to another vendor. S0 lists any other Anthropic data path
  that remains, such as WebFetch domain checks or server-side tools.
- **Scope:** `HUB_PROVIDER` covers `bin/work` sessions and, in S3a, `bin/agent`. `bin/briefing` stays on Anthropic.

**One provider per Claude process.** A Claude session's `--agents` sub-agents run on the same provider as the session
(one base URL per process); their `model:` must be that provider's model or a slot alias. Mixing providers in one
piece of work goes through `bin/agent`: an Anthropic Opus session delegates to a DeepSeek coder and a GLM reviewer,
each a headless `claude -p` with its own provider environment.
- An agent with no `provider:` (every existing agent) inherits the session's provider, under the model rule above.
- An agent whose `provider:` names a different provider is left out of `--agents` and listed as delegatable instead.

**Delegation (`bin/agent`, S3a).** For `engine: claude` with a provider other than `anthropic`, the provider's
variables are added to the cleared environment, with the key read from the Keychain by `bin/agent` itself, never taken
from the caller's environment. `bin/agent` fails closed like the launcher: if the key read fails or is empty it exits
2 before starting `claude -p` (tested with a fake `bin/secret` that exits 1). The env allowlist's auth exception (ADR 0003) names them exactly. All S3a rules apply:
read-only, framed output, watchdog, version gate.

**Feature go/no-go, enforced (all providers).** S0 item 21 ends with a go or no-go per provider per feature:
focus session, `--agents` sub-agents, delegation (`bin/agent`). It is recorded in `.ade/context/engines.md` and in a
machine-readable table in `lib.sh`. `bin/work --provider` and `bin/agent` refuse a provider/feature pair without a go
(exit 2, naming the S0 finding), and tests cover the refusal. A tool restriction, if S0 finds one is needed, is a
`--allowedTools` set in the provider row, applied by `bin/work` and `bin/agent`, not a README sentence.

**Records.** The S3a version gate records (engine realpath, version, provider), so a provider's deep check is its
own record. SP adds `HUB_PROVIDER` and `HUB_PROVIDERS_ALLOWED` to the `lib.sh` unset-before-sourcing list; S2a later
extends that same code, not a second mechanism.

**Doctor.** One row per allowed provider: the key exists in the Keychain (name only, never the value). `bin/doctor
--deep` makes one tiny request per allowed provider and records that the endpoint answered with the configured
model.

**Existing `--claude` wrappers** (OpenRouter, Ollama, README) keep working; providers are the managed way to do the
same for DeepSeek, GLM and Meta, with the allowlist and the Keychain.

**S0 item 21 (Claude only, can run now with the owner's keys):** for each provider, confirm on the current Claude
Code:
- `ANTHROPIC_AUTH_TOKEN` versus `ANTHROPIC_API_KEY`, and the `apiKeyHelper` and env-scrub options above;
- that with a valid key the endpoint receives **no Anthropic credential header**, and that an existing Anthropic
  login doesn't interfere or get sent; and the same when the `apiKeyHelper` **fails after startup** (Keychain locked
  after sleep): Claude Code must error, not fall back to the OAuth login against the third-party URL. If it falls
  back, the helper option is rejected;
- whether `/model` writes a provider model id into the shared user settings (breaking the next Anthropic session),
  and that `--resume` of an Anthropic session under a provider would send its history there (README warns);
- whether Remote Control works, and whether thinking budgets (`--effort`) work;
- **behaviour, not just errors** (a partial compatibility layer may accept a field and ignore it): a canary
  instruction in the system prompt / rules is obeyed; a forced tool call happens; a deny rule in the rules is
  respected. A provider that fails any of these gets a no-go for delegation, since `templates/delegated.md`'s read-only
  instructions reach the agent only through the prompt. `bin/doctor --deep` repeats the canary per provider;
- and: the current model IDs and slot mapping; what doesn't work through the compatible endpoint (tool use,
images, extended thinking, web search, prompt caching, token counting) and how Claude Code fails when it is used;
whether hooks and `--agents` still work; and the exit code on a bad key. For Meta, first confirm the
host, path and model IDs in Meta's own developer docs, before any request carries the key, and list every Claude Code
request field the endpoint rejects or ignores.

**Tests (hermetic: `tests/run.sh` never runs the real `claude` or calls a vendor):**
- A static check over **every** provider row: no base URL ends in `/v1` or `/`, and every row has a key name.
- Every row is exercised by the dry-run tests below (one case per provider), not only `glm`.
- A provider/feature pair with a no-go is refused by `bin/work --provider` and `bin/agent`.
- `bin/agent` with a provider and a fake `bin/secret` that exits 1, or prints nothing, exits 2 before `claude -p` runs.
- `WORK_DRY=1` shows the provider's environment names and the base URL exactly as in the row, never the key; the
  launcher file contains no key.
- A fake `bin/secret` that exits 1, or prints nothing: the launcher exits with the hint and the fake engine never runs.
- `--provider glm` implies `--no-remote`; `--provider` with a wrapper exits 2; a full Anthropic model id exits 2;
  `HUB_MODEL` isn't passed; `--effort` is refused.
- A provider not in `HUB_PROVIDERS_ALLOWED`, or set only in the environment, is refused.
- `--agents` refuses a sub-agent with a different provider.
- `bin/agent` with `provider: glm` passes exactly the provider's variables, takes the key from a fake `bin/secret`,
  and ignores an `ANTHROPIC_AUTH_TOKEN` in the caller's environment.
- An agent without `provider:` stays in `--agents`; one with a different provider is left out.

The real `claude` against a local fake Anthropic-compatible server (checking the `/v1/messages` path, that only the
provider's auth header arrives, and the hook and Bash tool can't see the key) runs in S0 item 21 and in `bin/doctor
--deep`, with a temp `CLAUDE_CONFIG_DIR`, `DISABLE_AUTOUPDATER=1` and `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`.

### No-repo folders

`bin/work` starts a no-repo folder's session in `$H/$F` itself (`bin/work:42`). There, a writable workspace could edit
the folder's `.claude/settings.json` hooks and `.claude/agents/*.md`. So in this plan, non-Claude engines are refused
for folders without a code repo:
- `bin/work --engine` exits 2 with the reason.
- Delegation there is read-only, and `write: true` is already refused.

A later plan can allow it if S0 item 6 shows `.claude/` can be denied.

### The allowlist and options (S2a)

**The allowlist:**
- `lib.sh` unsets `HUB_ENGINES_ALLOWED`, `HUB_CODEX`, `HUB_GEMINI` and `HUB_AUTH_PASSTHROUGH` before sourcing `hub.conf` (`lib.sh:47`), so
  only `hub.conf` sets them. An older `hub.conf` means `claude`.
- There is no `AGENT_*` override.
- **Threat model** (README and ADR 0002): the allowlist guards against accidents, not a hostile model. `HUB=` pointing
  at another hub, and `--claude` wrappers, are the owner's choices.

**Option rules:**
- `--model` and `HUB_<ENGINE>_MODEL` use the pattern check at `bin/work:27`. `HUB_MODEL` is for Claude only.
- `--effort` with another engine exits 2.
- `--agent-model`, `--agent-effort`, `--agents` and `--no-remote` are Claude only.
- `--agent-model name=X` naming a non-Claude agent exits 2 with the reason.
- `--prompt` is sent after the rules.

**Agents:** non-Claude agents are left out of Claude's `--agents`. `bin/context` lists the folder's delegatable agents
and how to call `bin/agent`.

**Context:** `bin/context --engine E` adds the folder's `memory/MEMORY.md` index for non-Claude engines only. Claude
already gets it through `bin/setup`'s link.

### The launcher (S2b): `bin/launch.py`

The launcher is Python, not bash 3.2. `python3` is already required (`bin/brain.py`, `bin/work:66`). Python's
`fork`/`setpgid`/`tcsetpgrp`/`waitpid` behave the same on every Mac. There is no `set -m` anywhere.

**The child process:**
1. Ignores SIGTTOU.
2. `setpgid(0, 0)`. The parent also calls `setpgid(pid, pid)`, so an early signal can't miss the group.
3. `tcsetpgrp(tty, own group)`, so the engine owns the terminal and Ctrl-C goes to it.
4. Resets INT, QUIT, TSTP, TTIN, TTOU, PIPE and XFSZ to their defaults. An ignored signal survives exec, and Python
   ignores SIGPIPE; without this the engine and its tools would start with Ctrl-C ignored (review 4, finding 2).
5. `execvp` the engine.

**The parent process:**
- **Signals:** it ignores SIGINT and SIGTTOU.
- **On SIGHUP or SIGTERM:**
  1. `killpg(engine, sig)`, then SIGCONT;
  2. after 10 s, TERM;
  3. after 5 s more, KILL.
- **Waiting:** it uses `waitpid(..., WUNTRACED)`. A stopped engine gets the terminal back and SIGCONT.
- **After the engine exits, session end comes first:**
  1. records the exit status;
  2. starts session end (below), before anything touches the terminal;
  3. then, each inside its own `try` so a closed terminal (ENOTTY, EIO) can't abort anything: takes the terminal
     back, removes the launcher file (today's `rm -f "$0"`), prints any message.

  Nothing the launcher does after the engine exits can stop session end.
- **A shell that doesn't HUP its jobs** (zsh `nohup`): the launcher also checks once a second that its terminal is
  still open; if it isn't, it runs the same ladder as SIGHUP.
- **Session end:** started by a double fork:
  1. fork;
  2. the child calls `setsid`, then forks again, then `_exit`s;
  3. the grandchild execs `bin/session-end F --since <start> --launch <id>`, with stdin on `/dev/null` (S1 reads
     stdin) and stdout and stderr on its log.

  No `setsid` call is made from a process-group leader, which is review 3's EPERM bug.
- **Launch id:** `AGENT_LAUNCH_ID=<pid>-<start-epoch>` is exported to the engine, so an S4 native hook knows the id.
  The once-only marker is `mkdir .local/session-end/<id>`. Markers older than 7 days are removed.

**Proof gate.** S2b's first commit is `tests/pty_run.py`, a pty harness, plus a fake engine.
- **Topology:** every check runs in production's topology: an interactive shell (`zsh -f -i`) on the pty that types
  `bash <launcher file>`, which is what Terminal's `do script` does. Running the launcher as the pty's session leader
  hid review 4's blocker, so that topology isn't enough.
- **The fake engine:** a bash script, not Python, so it can't install its own SIGINT handler and hide inherited
  dispositions. A small compiled probe (`tests/sigdisp.c`, built in the test) records its starting signal
  dispositions. It reads a line in normal mode, where `^C` is a signal, then switches to `stty raw`, where `^C` is the
  byte `\x03`. It records SIGINT and SIGHUP, and can ignore HUP and TERM.

S2b builds `bin/work` integration only after these pass:
- **Keystrokes:** the engine reads a typed line; no SIGTTIN or SIGTTOU stop.
- **Ctrl-C:** in normal mode, `^C` reaches the engine as SIGINT and does not end the session. In raw mode it arrives as
  a byte.
- **Inherited signals:** the engine starts with INT, TTOU and PIPE at their defaults.
- **`^Z`:** stops the engine; the launcher gives the terminal back and sends SIGCONT.
- **Closed terminal:** closing the master ends the session, and **session end then runs exactly once**. Also with an
  engine that ignores HUP and TERM (killed by the ladder), and with the shell's `nohup` option set.
- **Session end:** it runs exactly once through the real double-fork path, checked by its marker and its log line. It
  also runs once after a non-zero exit.
- **Terminal handback:** the launcher's process group owns the terminal again afterwards.

These tests run inside `bash tests/run.sh`, which has no terminal of its own; `pty_run.py` creates one.

### The inbox (S2c)

- **Per launch.** Each launch has its own `.local/inbox/<folder>/<launch-id>/`, seeded at launch with copies of
  `STATE.md`, `memory/MEMORY.md` and `memory/*.md`. Their hashes go in `.local/inbox-meta/<launch-id>.json`, outside
  the writable inbox, so the engine can't rewrite the base it is compared against.
- **Applied by `bin/session-end --launch <id>`, under the sync lock (S1):**
  - Only files that differ from the manifest are applied.
  - If the hub file also changed since launch (the owner, another session, a sync pull), the inbox copy goes to
    `.local/inbox-conflicts/<launch-id>/<name>`: not in git, not in the brain, not announced by `bin/changes`. The
    journal says so, `bin/doctor` lists it, and nothing is overwritten.
  - `MEMORY.md`: a line is appended only if it is in the engine's copy and not in the **current** hub file (exact
    line match), and only if it points at a memory file that was actually applied. Edited lines are not applied; they
    go to the conflicts folder. The engine's copy never replaces it.
  - New memory files need plain Markdown names. One whose name exists goes to the conflicts folder, not lost.
  - Deletions (a file missing from the inbox) are never applied.
  - Each path component is opened with `O_NOFOLLOW|O_DIRECTORY`, the file with `O_NOFOLLOW`, and `nlink` is checked
    with `fstat` on the open file. A symlink, a hard link (`nlink > 1`), a non-Markdown file or a file over 256 KB is
    refused and reported.
  - STATE and memory text is applied as written, as a Claude session's would be; only the journal is sanitised
    (threat model, ADR 0002).
  - If session end times out on the sync lock, the inbox is kept and the apply is retried by the next session end on
    that folder, not abandoned.
- **Journal from the inbox:** `journal.md` is collapsed to one paragraph, with lines starting with `#` removed and
  newlines turned into spaces. It is capped at 2 KB, prefixed `(codex session)`, then passed to `bin/journal`.
- **After applying,** the launch's inbox directory is removed. An inbox left by a crash is never applied
  automatically. `bin/doctor` lists it, and `bin/session-end F --launch <id>` applies it by hand.
- **Tests:**
  - two concurrent launches on one folder;
  - an owner edit during a session (a side file is written, nothing is lost);
  - a stale inbox (not re-applied);
  - a forged `## 12:00 UTC · hub` header in `journal.md` (it ends up inside one paragraph);
  - a symlink and a hard link (both refused);
  - the `MEMORY.md` append.

### S1: `bin/session-end` without a hook

- **Input:** the deadline read from `bin/changes:13-21` replaces `cat` (`bin/session-end:8`).
- **Start time:** `--since <epoch>` gives an exact start; the 8-hour fallback is only for hook calls without one.
- **The sync lock:** it waits up to 30 s, honouring stale pids. If the lock stays busy, it skips the commit and
  journals that. It releases the lock before `auto_sync`.
- **`bin/sync --yes`** takes the same lock as `--auto`, so a manual sync can't race either.
- **Log:** when `--since` is given, output goes to the session-end log.
- **Tests:**
  - a pipe holding `script`'s stdin open (fails on today's code);
  - a never-closing pipe;
  - a held lock and a stale lock;
  - the follow-on sync isn't skipped;
  - `--yes` waits for the lock.

### Delegation, read-only (S3a): `bin/agent`

`bin/agent --folder F <name>` reads the task on stdin. It is Python, for the same process control reasons as the
launcher.

- **Inputs:**
  - `F` matches `^(projects|ops)/[a-z0-9-]+$` and exists. It defaults to `$AGENT_FOLDER`; with neither, the run
    exits 2.
  - `<name>` matches `^[a-z0-9-]+$`.
  - Lookup: `F/.claude/agents/<name>.md`, else the hub root's `.claude/agents/<name>.md`, but only when
    `<name> = agent_name F`.
- **Prompt:** `bin/context F --rules --engine E`, then `templates/delegated.md` (read-only, return findings, no hub
  writes, no deploys, no `bin/`), then the agent body, then the task.
- **Environment:**
  - It is cleared, then allows only exact names: `HOME`, `USER`, `SHELL`, `PATH`, `LANG`, `TMPDIR`, `AGENT_FOLDER`,
    `HTTPS_PROXY`, `NO_PROXY`, `SSL_CERT_FILE` and `NODE_EXTRA_CA_CERTS`.
  - It adds the engine's auth names from `engines.md`. For Claude that is `CLAUDE_CONFIG_DIR=$(claude_home)`, plus the
    exact `ANTHROPIC_*` names a configured wrapper needs.
  - No wildcards. A cloud credential such as `GOOGLE_APPLICATION_CREDENTIALS` passes only if `hub.conf` lists it by
    name in `HUB_AUTH_PASSTHROUGH`. ADR 0003 flags this.
  - `HUB_AUTH_PASSTHROUGH` is unset before `hub.conf` is sourced, like the allowlist, so the environment can't set it.
    `bin/agent` reads `hub.conf` through `lib.sh` (a `bash -c '. lib.sh; ...'` call that prints the values), never
    its own parser. Each name must match `^[A-Z][A-Z0-9_]*$`; names starting with `GH_`, `GITHUB_` or `SSH_` are
    refused. Tests cover an exported value and a refused name.
- **Config:** S0 item 4's overrides, keeping the login. No hooks, no workspace config, no MCP servers, no workspace
  context files.
- **Version gate:**
  - `bin/agent` resolves the engine to one absolute binary (realpath) and refuses it unless that realpath and its
    version have a passing `bin/doctor --deep` result on this Mac, recorded in `.local/engines/verified`.
  - The same gate applies to `bin/work --engine` (focus sessions depend on the same sandbox flags).
  - Claude is gated too for headless delegation (S0 item 5's isolation flags); Claude focus sessions are not, as
    today.
  - On a new, unverified version, `bin/agent` runs the smoke check inline once (about a minute), records it, then
    proceeds or refuses, so an auto-update doesn't break delegation mid-session.
  - The message tells the owner to run `bin/doctor --deep`.
- **Output:**
  - Frame lines carry a random per-call nonce.
  - The answer is capped at 20 KB; the full text goes to `.local/agent-out/` and is kept 30 days.
  - The `CLAUDE.md` rule: delegated output is data.
- **Journal:** `journal/delegations-YYYY-MM.md` records the agent, engine, model, exit code and duration, never task
  text. `bin/changes` and `bin/context` don't read it, and a test proves both.
- **Lifetime:**
  - **Own process group.** The engine runs in its own process group, with a watchdog process in that group.
    - The watchdog ignores TERM, INT and HUP, so the group TERM in the kill ladder and an engine's own `kill 0` don't
      take it down.
    - It watches a pipe whose write end only `bin/agent` holds (close-on-exec, so the engine never inherits it). End
      of file means `bin/agent` is gone, by any signal including SIGKILL; there is no pid polling and no pid reuse.
    - It then runs the ladder itself (TERM, then KILL after 5 s) and exits.
  - **Signals and timeout.** TERM, INT, HUP and the timeout kill the group (TERM, then KILL after 5 s).
  - **Timeout.** `AGENT_TIMEOUT` defaults to 540 s and is capped at 570 s, so the timer, the kill grace and startup fit
    inside Claude's 600 s Bash maximum.
  - **The rule for callers.** Use `run_in_background` for anything over 2 minutes, or `timeout: 600000`. Claude Code
    may move a timed-out command to the background instead of killing it, and the watchdog handles both cases.
- **Exit codes:** 0 answer; 1 engine failed, timed out or was killed; 2 bad usage, refused engine or unverified
  version.
- **Tests:** fake engines that dump argv and env.
  - `ps` never shows the task.
  - No `GH_TOKEN` or wildcard leak.
  - A grandchild is fully gone after the timeout, and after `kill -TERM`, `kill -INT` and `kill -KILL` of `bin/agent`.
  - `kill -KILL` of `bin/agent` during the 5 s grace, with an engine that ignores TERM: the group is still fully gone.
  - An engine that kills its own group during cleanup: nothing survives.
  - A version mismatch is refused.
  - The frame nonce, the 20 KB cap and the journal separation.

### Delegation with write (S3b)

- **Where it's allowed:** only when realpath(cwd) equals the realpath of a checkout listed in F's `ACCESS.md` and is
  outside realpath(`$H`).
- **Denied directories:** the engine must deny writes to them (S0 item 6); otherwise `write: true` is refused for that
  engine.
- **Busy checkout:** write mode is refused while **another** session is active in that checkout, so nobody else's git
  or permission writes land in the comparison.
  - **Launch markers:** the launcher writes `.local/active/<sha of checkout realpath>/<launch-id>.json` (pid, process
    start time, engine) at launch and removes it at exit; a marker whose pid and start time don't match a live process
    is stale and removed.
  - **Claude sessions** started outside `bin/work` are found through Claude Code's session registry, if S0 item 20 says
    it is usable, read in every config dir the hub knows (`claude_home`, plus `HUB_CLAUDE_CONFIG_DIR`). If not, the
    `HUB_WRITE_UNCHECKED` fallback applies.
  - **Not detected:** Codex or Gemini sessions the owner starts by hand outside `bin/work`. The README says so: an
    edit to the protected set in such a session during a write-mode run is reverted and kept in quarantine.
  - **The caller is exempt:** a session whose pid is an ancestor of `bin/agent` (walked up through `ps -o ppid=`), or
    whose launch id equals the caller's `AGENT_LAUNCH_ID`, doesn't count. The caller's own git writes are covered by
    the allowlist below, not by refusing.
- **Protected set:** snapshotted (copied, not just hashed) before the run:
  - `.git/hooks` and `.git/info`, resolved through the common git dir for worktrees, plus `.git/modules/*/hooks`;
  - `.git/config`, `config.worktree` and `.git/modules/*/config`, compared **by key, with an allowlist**: every key
    that changed is reverted, except a short list of keys that can't run code and that ordinary git use writes:
    `branch.*.remote`, `branch.*.merge`, `branch.*.rebase`, `remote.*.fetch`. `remote.*.url` and `remote.*.pushurl`
    are reverted too: a changed push URL would send the client's code to a host the engine chose.
    Git keeps adding keys that run commands (`diff.external`, `gpg.program`, `merge.*.driver`, `core.askPass`...),
    so a denylist would always lag. Reverts use `git config --file <path>` with `--unset-all` / `--replace-all` for
    multi-valued keys, so a concurrent write isn't lost, and no git command that reads hooks or fsmonitor runs before
    the revert;
  - the root `.gitattributes` (it selects merge drivers and filters);
  - the resolved `core.hooksPath`;
  - `.claude/` (except `settings.local.json`, which permission approvals write), `.codex/`, `.gemini/`, `.github/`
    and `.husky/`;
  - `.envrc`, `.vscode/`, `.pre-commit-config.yaml`, `mise.toml` and `.tool-versions`;
  - `CLAUDE.md`, `AGENTS.md` and `GEMINI.md` at the repo root.

  These are small, named paths; packs and the index are never hashed.
- **After the run:** any change in that set is reverted from the snapshot. The engine's versions go to
  `.local/quarantine/<id>/`. The run exits 1 with a loud message naming each file.
- **Lock:** a per-checkout write lock holds a pid, with stale-pid detection like `bin/sync`'s. A held lock fails fast.
- **Tests:**
  - refused in a hub folder, in `$H/repos/` and through a symlink;
  - a planted `.git/hooks/pre-commit`, a `core.hooksPath` file, a `core.fsmonitor` key and a root `AGENTS.md` are each
    reverted and quarantined;
  - an allowlisted `.git/config` change (`branch.*.remote` from `git push -u`) is left alone, and a planted
    `diff.external`, `gpg.program` and multi-valued `alias.*` are reverted;
  - the caller's own focus session in the checkout doesn't refuse write mode; a second live session does; a stale
    marker doesn't;
  - a held lock and a stale lock;
  - a worktree checkout (a `.git` file).

### S4: native hooks, only where S0 says go

- Config lives under the gitignored `.local/engines/<engine>/`, apart from the login.
- `.codex` and `.gemini` are added to the brain's skip list and to `.gitignore`.
- For a session started by the launcher, the launcher alone owns session end; native SessionEnd hooks are not
  installed for launched sessions (they could take the marker while the engine still runs, possibly inside its
  sandbox). S4 native hooks cover only SessionStart and per-prompt notices.

### Doctor

- **Plain `bin/doctor`:** for each allowed engine, installed, minimum version, logged in, and whether this version is
  verified. It also lists:
  - agents whose engine isn't allowed;
  - leftover inboxes;
  - quarantined files.

  It makes no model calls.
- **`bin/doctor --deep`:** runs the S0 item 7 smoke checks per allowed engine in a temp dir, and records a pass for that
  exact version. It is never part of `tests/run.sh`.

### Records

- **ADR 0002:** engines are opt-in; the allowlist is an accident guard; any engine that can read `~/.ssh` is accepted
  by name or refused.
- **ADR 0003:** the `bin/agent` contract: front matter, stdin input, the nonce frame, exit codes, the env allowlist,
  `HUB_AUTH_PASSTHROUGH`, and the version gate.
- **`.ade/context/engines.md`:** the S0 findings and the exact auth names per engine.

## Stories (one PR each, test-first, docs and doctor rows in the same story)

| Story | Content | Needs |
|---|---|---|
| S0 | The spike: items 1–21 (Claude-only items first, item 21 first of all), `engines.md`, go/no-go. Owner's go-ahead to install Codex and upgrade Gemini. | — |
| S1 | `bin/session-end`: deadline read, `--since`, lock (also for `sync --yes`), log | — |
| SP | Providers: table, `HUB_PROVIDER(S_ALLOWED)`, `bin/work --provider`, `--agents` provider check, Keychain key at launch, doctor rows, README, ADR 0002 section | S0 item 21 |
| S2a | Allowlist, option rules, `--agents` filter, `bin/context --engine`, no-repo refusal, ADR 0002, README | S0 |
| S2b | `bin/launch.py`, behind the pty proof gate, and `bin/work --engine`. Until S2c ships, non-Claude sessions get the no-hub-writes rules (as for S0 item 1 = no). | S1, S2a |
| S2c | Per-launch inbox, `session-end --launch` and its apply | S2b |
| S3a | Read-only `bin/agent` (with providers for `engine: claude`), version gate, `bin/doctor --deep`, ADR 0003 | S2a, SP |
| S3b | `write: true` | S3a |
| S4 | Native hooks where S0 says go (SessionStart and prompt notices only) | S2c |
| S5 | `bin/init --engine`, `bin/new <folder> --specialist <name> --engine E --model M`, guide diagram, upgrade notes | all |

S3a doesn't depend on S2b or S2c, so delegation can ship before non-Claude focus terminals. Tests in S3a are Python
and don't vary with `gtimeout` (lib.sh's `timeout` isn't used).

**What a non-Claude session loses** (README, from S2b):
- the change notices on each prompt;
- the stop check;
- the compaction journal line;
- Remote Control;
- folder agents as sub-agents;
- direct hub writes, which go through the inbox instead;
- sessions in no-repo folders.

## Review 3 findings

| Finding | Answer |
|---|---|
| X1 SIGTTIN stop, launcher hang | The child takes the terminal (`tcsetpgrp`) before exec; Python launcher; pty proof gate |
| X2 Ctrl-C never reaches the engine | The engine owns the terminal; the parent ignores INT; pty `^C` test |
| X3 `setsid` EPERM, silent | Double fork, `setsid` in a non-leader; the test checks session end ran through the real path |
| X4 tests can't catch X1–X3 | `tests/pty_run.py`; a fake engine that reads the terminal in raw mode and records signals |
| X5 no-repo folders | Non-Claude sessions refused there |
| X6 inbox races | Per-launch inbox; manifest hashes; side files on conflict; `MEMORY.md` append-only; applied under the lock; removed after |
| X7 inbox journal injection | One paragraph, `#` lines removed, 2 KB cap, engine prefix; forged-header test |
| X8 SIGKILL and nested callers | Watchdog in the engine group; `kill -KILL` test; cap 570 s; S0 item 2 shell-tool timeouts; the background note |
| X9 version drift | Version gate on a recorded `bin/doctor --deep` pass |
| X10 hash check gaps and cost | Named protected set, including `hooksPath` and the common dir; snapshot, revert and quarantine; pid lock |
| X11 Claude auth, wildcard | Claude in item 15; `CLAUDE_CONFIG_DIR`; exact names only; `HUB_AUTH_PASSTHROUGH` for cloud credentials |
| X12 stories too big | S2a/S2b/S2c and S3a/S3b |
| X13 minors | Plain doctor makes no model calls; `nlink`/`O_NOFOLLOW`; `AGENT_LAUNCH_ID`; SIGCONT; exit status; unset `HUB_CODEX`/`HUB_GEMINI`; `sync --yes` lock; delegations test; 30-day retention |
| M12 remaining S0 gaps | Items 1 (hard link), 2 (shell-tool timeouts), 9 (TUI foreground), 15 (Claude), 16 (versions) |

## Review 5 minors, carried into their stories

| Story | Carry |
|---|---|
| S2b | The 1 s terminal check uses `os.tcgetpgrp(0)` (ENOTTY) or `poll` with POLLHUP/POLLNVAL; both work after close. |
| S2b | Close checks also run in topology C (bash as the pty's session leader), which is `AGENT_TERMINAL=iterm`. |
| S2b | S2b owns `session-end --launch <id>` and its marker; S2c only adds the inbox apply. |
| S2c | A kept inbox (sync lock timeout) gets a persistent `pending` flag in `inbox-meta`; only flagged inboxes are retried, crash leftovers never are. Both are tested. |
| S2c | `MEMORY.md` lines are appended only for newly created memory files; any other changed line goes to conflicts. |
| S3a | The inline smoke check counts inside `AGENT_TIMEOUT`, runs under the watchdog, serialises writes to `verified`, and doesn't record network or auth failures as version failures. |
| S3a | The watchdog closes its inherited copy of the pipe's write end, moves its stdio to `/dev/null`, and skips the ladder when the group holds only itself. |
| S3a | The `hub.conf` read runs as `env -i bash --noprofile --norc -c '. lib.sh; ...'`, so `BASH_ENV` or exported functions can't defeat the unset. |
| S3a | For npm-installed engines, the version gate keys on the package version (S0 item 16), not only the shim's realpath. |

## Review 5 majors

| Finding | Answer |
|---|---|
| N1 busy-checkout check refuses the caller; no Claude lock | Launch-time markers keyed by checkout with stale detection; the caller exempt by ancestry or launch id; Claude registry as S0 item 20 with the owner's `HUB_WRITE_UNCHECKED` fallback; hand-started Codex/Gemini sessions named as undetected |
| N2 `.git/config` denylist misses keys that run code | Allowlist of harmless keys, revert everything else with `git config --file`; root `.gitattributes` protected; tests for planted keys |

## Review 4 findings

| Finding | Answer |
|---|---|
| 1 session end lost on window close; gate can't see it | Session end starts first after exit; terminal work in `try`; gate in production topology with "session end once after close" |
| 2 inherited ignored INT/TTOU/PIPE | Child resets seven signals before exec; compiled probe in the gate |
| 3 engine can rewrite the manifest | Manifest in `.local/inbox-meta/`, outside the writable inbox |
| 4 hard link write-through | S0 item 17; no inbox if possible; `O_NOFOLLOW` per component, `fstat` `nlink` |
| 5 side files spread; `MEMORY.md` underspecified | `.local/inbox-conflicts/`, doctor lists it; line rules against the current file; no deletions; refused files kept; retry after lock timeout |
| 6 watchdog dies with the group | Ignores TERM/INT/HUP; EOF on a close-on-exec pipe; grace-window and self-kill tests |
| 7 version gate only for delegation, keyed on a string | Gate on realpath and version, also for `bin/work --engine`; Claude headless gated; inline smoke check on a new version |
| 8 write-mode revert races the caller and the owner | Refused while a session is active in the checkout; `.git/config` by key; `settings.local.json` excluded; worktree and submodule configs added |
| 9 `HUB_AUTH_PASSTHROUGH` from the environment | Unset before sourcing; read through `lib.sh`; name pattern; GH/GITHUB/SSH refused; tests |
| m1 story dependencies | Launcher alone owns session end; S4 needs S2c and drops SessionEnd; S2b's interim rules; S2c owns `--launch` |
| m2 shells that don't HUP jobs | Launcher polls its terminal |
| m3 session end's stdin | `/dev/null` |
| m4 early signal before the group exists | Parent also calls `setpgid(pid, pid)` |
| m5 `gtimeout` test for Python | Dropped |
| m6 STATE and memory verbatim | Stated in the threat model |
| m7 protected set gaps | Root `CLAUDE.md`/`AGENTS.md`/`GEMINI.md`, `mise.toml`, `.tool-versions` added |
| New S0 questions | Items 16–19 |

## Reviews 1 and 2

Every row closed in review 3 stays as answered in revision 3. The rows review 3 marked partly or not are covered here:

| Earlier finding | Covered by review 3 row |
|---|---|
| B1 hub writes from a sandboxed session | X5, X6 |
| B2 session end from the launcher | X1–X4 |
| B3 read-only only by flags | X9 |
| M1 write agents editing hooks | X10 |
| M2 secrets reaching vendors | X11 |
| M3 injection | X7 |
| M8 timeout | X8 |
| N1 orphaned engine | X8 |
| N3 HUP mechanics | X1–X3 |
| N4 auth | X11 |
| N7 workspace config | X9 |
| N8 marker | X13 |
| N9 lock | X13 |
