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
# hub.conf (written by bin/init): who this agent is and what it can reach. Names and locations only, never secrets.
# AGENT_* environment variables override it (tests use them).
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
