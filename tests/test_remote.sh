#!/bin/bash
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"
bin/remote true >/dev/null 2>&1; assert_eq "$?" "2" "no remote configured exits 2"
S="$(mktemp -d)"; printf '#!/bin/bash\nprintf "%%s\\n" "$@" > "%s/ssh.args"\n' "$S" > "$S/ssh"; chmod +x "$S/ssh"
export PATH="$S:$PATH" AGENT_REMOTE_HOST=box.example AGENT_REMOTE_USER=deploy AGENT_REMOTE_PORT=2222 AGENT_REMOTE_KEY=/k AGENT_REMOTE_DIR=/srv/app
bin/remote wp option get "blog name" || fail "remote failed"
for want in BatchMode=yes 2222 /k "deploy@box.example" 'cd /srv/app && wp option get blog\ name'; do assert_contains "$S/ssh.args" "$want" "ssh args"; done
AGENT_REMOTE_DIR= AGENT_REMOTE_KEY= AGENT_REMOTE_USER= bin/remote ls; grep -q -- "-i" "$S/ssh.args" && fail "no key, no -i"
assert_contains "$S/ssh.args" "box.example" "host without user"; grep -q "cd " "$S/ssh.args" && fail "no dir, no cd"
bin/remote >/dev/null 2>&1; assert_eq "$?" "2" "no command exits 2"
echo ok
