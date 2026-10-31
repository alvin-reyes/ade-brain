#!/bin/bash
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "$3: got [$1] want [$2]"; }
assert_contains() { grep -qF -- "$2" "$1" || fail "$3: [$2] not in $1"; }
make_hub() {
  HUB="$(mktemp -d)/hub"; mkdir -p "$HUB"
  (cd "$REPO" && tar cf - --exclude ./repos --exclude ./.git --exclude ./hub.conf --exclude ./.superpowers .) | (cd "$HUB" && tar xf -)
  rm -f "$HUB"/journal/[0-9]*.md   # test hubs start with an empty journal; the real journal/ is never touched
  git -C "$HUB" init -q && git -C "$HUB" config user.name t && git -C "$HUB" config user.email t@t
  CLAUDE_HOME="$(mktemp -d)"; export HUB CLAUDE_HOME
  export AGENT_OLLAMA_URL=http://127.0.0.1:9   # tests never reach a real Ollama (test_brain runs a fake one)
}
