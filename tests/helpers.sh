#!/bin/bash
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "$3: got [$1] want [$2]"; }
assert_contains() { grep -qF -- "$2" "$1" || fail "$3: [$2] not in $1"; }
make_hub() {
  # results never depend on the tester's shell: no Anthropic credential or backend switch reaches a test
  local v; for v in $(compgen -e); do case "$v" in ANTHROPIC_*|CLAUDE_CODE_USE_*|CLAUDE_CODE_OAUTH_TOKEN) unset "$v" ;; esac; done
  # nor a tester's ADE terminal or terminal choice: bin/work would open a real ADE sub-terminal (story W1)
  unset ADE_HOOK_BIN ADE_HOOK_PORT ADE_HOOK_TOKEN ADE_PTY_ID AGENT_TERMINAL
  HUB="$(mktemp -d)/hub"; mkdir -p "$HUB"
  (cd "$REPO" && tar cf - --exclude ./repos --exclude ./.git --exclude ./hub.conf --exclude ./.local --exclude ./.superpowers .) | (cd "$HUB" && tar xf -)
  rm -f "$HUB"/journal/[0-9]*.md   # test hubs start with an empty journal; the real journal/ is never touched
  git -C "$HUB" init -q && git -C "$HUB" config user.name t && git -C "$HUB" config user.email t@t
  CLAUDE_HOME="$(mktemp -d)"; export HUB CLAUDE_HOME
  export AGENT_OLLAMA_URL=http://127.0.0.1:9   # tests never reach a real Ollama (test_brain runs a fake one)
  # tests never push a real hub or touch the real sync log/lock; test_report turns auto sync on with a stub
  export AGENT_AUTO_SYNC=0 AGENT_SYNC_LOG="$(mktemp -d)/sync.log" AGENT_SYNC_LOCK="$(mktemp -d)/sync.lock"
}
