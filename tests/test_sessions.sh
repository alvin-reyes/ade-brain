#!/bin/bash
# bin/sessions: the durable list of focus sessions bin/work started, with the session that started each
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"
unset ADE_HOOK_BIN ADE_HOOK_PORT ADE_HOOK_TOKEN ADE_PTY_ID   # never the real ADE
ST="$(mktemp -d)"; export RSPUR_STATE="$ST" AGENT_STATE="$ST"
bin/new projects/demo >/dev/null
S="$(mktemp -d)"; printf '#!/bin/bash\nexec sleep 30\n' > "$S/claude-stub"; chmod +x "$S/claude-stub"
launch() { WORK_NO_OPEN=1 bin/work --force --claude claude-stub projects/demo 2>/dev/null | sed -n 's/^launcher: //p'; }
wait_for() { for _ in $(seq 1 50); do eval "$1" && return 0; sleep 0.1; done; return 1; }
# a session started from a Claude session (CLAUDE_PID=777) registers itself with that parent
f=$(CLAUDE_PID=777 launch); [ -x "$f" ] || fail "launcher written"
PATH="$S:$PATH" bash "$f" & lp=$!
wait_for '[ -f "$ST/sessions/demo.$lp" ]' || fail "running session is registered"
out=$(bin/sessions); echo "$out" | grep -q "^demo  *projects/demo  *[0-9][0-9]*  *777 " || fail "listed with claude pid and parent: $out"
cp=$(pgrep -P "$lp" | head -1); echo "$out" | grep -q " $cp  *777 " || fail "claude pid is the launcher's child ($cp): $out"
bin/sessions --parent 777 | grep -q "^demo " || fail "--parent 777 lists it"
bin/sessions --parent 1 | grep -q "^demo " && fail "--parent 1 does not"
CLAUDE_PID=777 bin/sessions --mine | grep -q "^demo " || fail "--mine lists the caller's children"
CLAUDE_PID=778 bin/sessions --mine | grep -q "^demo " && fail "--mine skips other sessions' children"
# the session ending removes its entry
kill "$cp"; wait "$lp" 2>/dev/null
wait_for '[ ! -e "$ST/sessions/demo.$lp" ]' || fail "entry removed when the session ends"
[ ! -e "$f" ] || fail "launcher removed itself"
# started outside a Claude session: parent is -
f=$(env -u CLAUDE_PID bash -c "$(declare -f launch); launch"); PATH="$S:$PATH" bash "$f" & lp=$!
wait_for '[ -f "$ST/sessions/demo.$lp" ]' || fail "registered without a parent"
bin/sessions | grep -q "^demo .* - " || fail "no parent shows as -"
kill "$(pgrep -P "$lp" | head -1)"; wait "$lp" 2>/dev/null
# negatives: a dead launcher (killed hard) is pruned; bad arguments; --mine outside a Claude session
mkdir -p "$ST/sessions"; printf 'name=ghost\nfolder=projects/ghost\nlauncher=999999\nparent=1\nstarted=x\n' > "$ST/sessions/ghost.999999"
bin/sessions | grep -q "^ghost" && fail "dead launcher not listed"
[ ! -e "$ST/sessions/ghost.999999" ] || fail "dead entry pruned"
# a reused pid (a live process that is not a launcher) is pruned too
sleep 30 & other=$!; printf 'name=reused\nfolder=projects/x\nlauncher=%s\nparent=1\nstarted=x\n' "$other" > "$ST/sessions/reused.$other"
bin/sessions | grep -q "^reused" && fail "reused pid not listed"; [ ! -e "$ST/sessions/reused.$other" ] || fail "reused entry pruned"; kill "$other"
bin/sessions --parent x >/dev/null 2>&1; assert_eq "$?" "2" "bad --parent"
bin/sessions --nope >/dev/null 2>&1; assert_eq "$?" "2" "unknown option"
env -u CLAUDE_PID bin/sessions --mine >/dev/null 2>&1; assert_eq "$?" "2" "--mine needs CLAUDE_PID"
echo ok
