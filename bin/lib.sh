#!/bin/bash
# Shared helpers for bin/ scripts. HUB and CLAUDE_HOME may be overridden (tests).
hub_root() { if [ -n "${HUB:-}" ]; then echo "$HUB"; else (cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd); fi; }
# the Claude config dir this hub's install uses (memory and skills are linked there): CLAUDE_HOME (tests), else
# HUB_CLAUDE_CONFIG_DIR from hub.conf, else the shell's CLAUDE_CONFIG_DIR, else ~/.claude
claude_home() { echo "${CLAUDE_HOME:-${HUB_CLAUDE_CONFIG_DIR:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}}}"; }
# the Claude install hub sessions run as: AGENT_CLAUDE, else HUB_CLAUDE from hub.conf, else claude
claude_cmd() { echo "${AGENT_CLAUDE:-${HUB_CLAUDE:-claude}}"; }
encode_path() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }
utc_today() { date -u +%Y-%m-%d; }
utc_now() { date -u +%H:%M; }
folders() { local h; h="$(hub_root)"; for d in "$h"/projects/* "$h"/ops/*; do [ -d "$d" ] && echo "${d#$h/}"; done; }
agent_name() { case "$1" in projects/*) echo "${1#projects/}";; ops/*) echo "ops-${1#ops/}";; esac; }
state_dir() { echo "${AGENT_STATE:-$HOME/.agent-hub/$(hub_name)}"; }
# repos_of <folder>: existing checkout dirs from the Checkout column of ACCESS.md's Code table (absolute, ~ allowed).
# Any table row whose 2nd cell starts with / or ~ counts, so a row appended after the table still works.
repos_of() {
  local a; a="$(hub_root)/$1/ACCESS.md"; [ -f "$a" ] || return 0
  awk -F'|' '/^\|/{c=$3; gsub(/^[ \t]+|[ \t]+$/,"",c); if(c ~ /^[\/~]/)print c}' "$a" |
    while IFS= read -r r; do r="${r/#\~/$HOME}"; [ -d "$r" ] && echo "$r"; done
}
# stale_repos <folder>: repos whose HEAD commit is newer than STATE.md's mtime, as "<repo> <hash>" lines
stale_repos() {
  local s m r ct; s="$(hub_root)/$1/STATE.md"; [ -f "$s" ] || return 0; m=$(stat -f %m "$s")
  repos_of "$1" | while IFS= read -r r; do
    ct=$(git -C "$r" log -1 --format=%ct 2>/dev/null) || continue
    [ -n "$ct" ] && [ "$ct" -gt "$m" ] && echo "$r $(git -C "$r" rev-parse HEAD)"
  done
  return 0
}
# _timeout_fallback <secs> <cmd...>: no timeout/gtimeout installed. Run in the background, sleep, then kill the
# command and its children (so a pipe it holds open closes). Returns the command's status, or 124 if it was killed.
_timeout_fallback() {
  local s="$1" p w rc; shift
  "$@" & p=$!
  ( sleep "$s"; pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null ) >/dev/null 2>&1 & w=$!
  wait "$p" 2>/dev/null; rc=$?
  if kill -0 "$w" 2>/dev/null; then pkill -P "$w" 2>/dev/null; kill "$w" 2>/dev/null; wait "$w" 2>/dev/null; return "$rc"; fi
  return 124
}
# A timeout that works on macOS: GNU coreutils' gtimeout when installed, else the fallback above.
if ! command -v timeout >/dev/null; then
  if command -v gtimeout >/dev/null; then timeout() { gtimeout "$@"; }; else timeout() { _timeout_fallback "$@"; }; fi
fi
# Providers behind Claude Code (story SP; contract in .ade/context/providers.md, findings in .ade/context/engines.md).
# One row per provider; anthropic (Claude Code's own login) has no row. Base URLs live only here: no override, ever.
# Fields: base_url, secret (Keychain name for bin/secret), label (doctor), model/opus/sonnet/haiku/small (slots),
# owner_only (1 = only in a hub with HUB_OWNED_BY_OWNER=1; owner rule 2026-11-09, ADR 0002; a row without it is owner-only too).
providers() { echo "deepseek glm"; }
provider_field() {
  case "$1:$2" in
    deepseek:base_url) echo "https://api.deepseek.com/anthropic" ;;
    deepseek:secret) echo "deepseek-api-key" ;;
    deepseek:label) echo "DeepSeek API key" ;;
    deepseek:model|deepseek:sonnet|deepseek:haiku|deepseek:small) echo "deepseek-flash" ;;
    deepseek:opus) echo "deepseek-v4-pro" ;;
    deepseek:owner_only) echo 1 ;;
    glm:base_url) echo "https://api.z.ai/api/anthropic" ;;
    glm:secret) echo "zai-api-key" ;;
    glm:label) echo "z.ai API key" ;;
    glm:owner_only) echo 1 ;;
    glm:model|glm:opus|glm:sonnet|glm:haiku|glm:small) echo "unconfirmed" ;;
    *) return 1 ;;
  esac
}
# provider_feature_go <provider> <focus|agents|delegation|effort|remote>: 0 = go (S0 item 21). One go per line.
provider_feature_go() {
  case "$1:$2" in
    deepseek:focus) return 0 ;;
    deepseek:agents) return 0 ;;
    deepseek:delegation) return 0 ;;
    deepseek:effort) return 0 ;;
    *) return 1 ;;
  esac
}
provider_no_go_reason() { echo "provider $1 has no go for $2 (S0 item 21, .ade/context/engines.md)"; }
# provider_model_ok <provider> <model>: a slot alias or an id from the row
provider_model_ok() {
  case "$2" in opus|sonnet|haiku) return 0 ;; esac
  local s; for s in model opus sonnet haiku small; do [ "$(provider_field "$1" "$s")" = "$2" ] && return 0; done; return 1
}
# provider_model_id <provider> <model>: a slot alias resolved through the row, else the model itself
provider_model_id() { case "$2" in opus|sonnet|haiku) provider_field "$1" "$2" ;; *) echo "$2" ;; esac; }
# provider_hub_refusal <provider>: prints why this hub may not use it (empty = it may). Call after hub.conf is read.
# Fails closed: only owner_only 0 opens a provider to client hubs; a missing value counts as owner-only.
provider_hub_refusal() {
  local o; o="$(provider_field "$1" owner_only)"
  [ "$o" = 0 ] || [ "${HUB_OWNED_BY_OWNER:-}" = 1 ] && return 0
  if [ "$o" = 1 ]; then
    echo "$1 is only for the owner's own hubs (HUB_OWNED_BY_OWNER=1 in hub.conf): its terms allow training on API data and store it in the People's Republic of China (ADR 0002)"
  else
    echo "$1 has no owner_only value in bin/lib.sh, so it is refused outside the owner's own hubs (HUB_OWNED_BY_OWNER=1 in hub.conf, ADR 0002)"
  fi
}
# provider_scrub_vars: names that beat apiKeyHelper or switch Claude Code to another backend (auth order:
# ANTHROPIC_AUTH_TOKEN > ANTHROPIC_API_KEY > apiKeyHelper > OAuth). A provider session never passes them on.
provider_scrub_vars() { echo "ANTHROPIC_AUTH_TOKEN ANTHROPIC_API_KEY ANTHROPIC_CUSTOM_HEADERS CLAUDE_CODE_USE_BEDROCK CLAUDE_CODE_USE_VERTEX CLAUDE_CODE_USE_FOUNDRY CLAUDE_CODE_OAUTH_TOKEN"; }
# hub.conf (written by bin/init): who this agent is and what it can reach. Names and locations only, never secrets.
# AGENT_* environment variables override it (tests use them). Provider choice and hub ownership come only from hub.conf.
unset HUB_PROVIDER HUB_PROVIDERS_ALLOWED HUB_OWNED_BY_OWNER
[ -f "$(hub_root)/hub.conf" ] && . "$(hub_root)/hub.conf"
hub_name() { echo "${HUB_NAME:-$(basename "$(hub_root)")}"; }
hub_owner() { echo "${HUB_OWNER:-the hub owner}"; }
persona_title() { echo "${HUB_PERSONA_TITLE:-technical agent}"; }
code_owner() { echo "${AGENT_CODE_OWNER:-${HUB_CODE_OWNER:-}}"; }
# The remote box (staging server, VM) reached by bin/remote; empty host = none configured.
remote_host() { echo "${AGENT_REMOTE_HOST:-${HUB_REMOTE_HOST:-}}"; }
remote_user() { echo "${AGENT_REMOTE_USER:-${HUB_REMOTE_USER:-}}"; }
remote_port() { echo "${AGENT_REMOTE_PORT:-${HUB_REMOTE_PORT:-22}}"; }
remote_key() { echo "${AGENT_REMOTE_KEY:-${HUB_REMOTE_KEY:-}}"; }
remote_dir() { echo "${AGENT_REMOTE_DIR:-${HUB_REMOTE_DIR:-}}"; }
remote_target() { local u; u="$(remote_user)"; echo "${u:+$u@}$(remote_host)"; }
staging_url() { echo "${AGENT_STAGING_URL:-${HUB_STAGING_URL:-}}"; }
keychain_service() { echo "${AGENT_KEYCHAIN_SERVICE:-${HUB_KEYCHAIN_SERVICE:-$(hub_name)}}"; }
# The sync lock: one bin/sync --yes/--auto run or session-end commit at a time. A directory holding its owner's pid.
sync_lock_path() { echo "${AGENT_SYNC_LOCK:-$(state_dir)/sync.lock}"; }
# seconds bin/sync --yes and bin/session-end wait for a busy lock (--auto never waits)
sync_lock_wait() { echo "${AGENT_LOCK_WAIT:-30}"; }
# sync_lock_take <lock> <wait-secs> [log-cmd]: take the lock, trying once a second; a busy lock is retried <wait-secs>
# times after the first try (attempts are counted, so the wait is at least <wait-secs> seconds).
# A stale lock (its owner pid is gone, or it is over 120 minutes old) is removed and `<log-cmd> removed stale lock` runs.
# Returns 0 holding the lock (pid file = $$), 1 when a live owner still holds it.
sync_lock_take() {
  local k="$1" w="${2:-0}" lg="${3:-:}" n=0; mkdir -p "$(dirname "$k")" 2>/dev/null
  while :; do
    mkdir "$k" 2>/dev/null && { echo $$ > "$k/pid"; return 0; }
    _sync_lock_reap "$k" "$lg" && continue
    [ "$n" -lt "$w" ] || return 1
    n=$((n + 1)); sleep 1
  done
}
_sync_lock_stale() {
  local op; op=$(cat "$1/pid" 2>/dev/null)
  { [ -n "$op" ] && ! kill -0 "$op" 2>/dev/null; } || [ -n "$(find "$1" -maxdepth 0 -mmin +120 2>/dev/null)" ]
}
# _sync_lock_reap <lock> <log-cmd>: removes <lock> if it is stale; 0 = removed. Only one taker at a time may judge and
# remove (the guard <lock>.gc, a mkdir), and the lock is judged again inside the guard, so two takers that both saw the
# same stale lock cannot remove the lock one of them has just taken. The judged directory is moved aside and removed
# only if it is still the one judged (same inode); otherwise it is put back and the lock counts as busy.
# A guard left by a killed run expires after a minute.
_sync_lock_reap() {
  local k="$1" g="$1.gc" s="$1.stale.$$" i r=1
  _sync_lock_stale "$k" || return 1
  [ -n "$(find "$g" -maxdepth 0 -mmin +1 2>/dev/null)" ] && rm -rf "$g"
  mkdir "$g" 2>/dev/null || return 1
  i=$(stat -f %i "$k" 2>/dev/null)
  if [ -n "$i" ] && _sync_lock_stale "$k"; then
    rm -rf "$s"
    if mv "$k" "$s" 2>/dev/null; then
      if [ "$(stat -f %i "$s" 2>/dev/null)" = "$i" ]; then rm -rf "$s"; "$lg" "removed stale lock"; r=0
      else [ -e "$k" ] || mv "$s" "$k" 2>/dev/null; rm -rf "$s"; fi
    fi
  fi
  rmdir "$g" 2>/dev/null
  return $r
}
# sync_lock_release <lock>: removes the lock only when this process owns it
sync_lock_release() { [ "$(cat "$1/pid" 2>/dev/null)" = "$$" ] && rm -rf "$1"; return 0; }
