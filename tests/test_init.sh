#!/bin/bash
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"
bin/init --list | grep -q "^staff-software-engineer *Staff Software Engineer" || fail "--list shows personas"
# --dest: a new hub for a DevOps persona, from a copy
D="$(mktemp -d)/acme-ops"; CO="$(mktemp -d)/acme-infra"; mkdir -p "$CO"
bin/init --persona devops-sre --client "Acme Corp" --owner "Sam Lee" --dest "$D" --repo acme/infra="$CO" \
  --remote deploy@box.acme.test:2222 --remote-key /keys/acme --remote-dir /srv/app --staging-url https://staging.acme.test \
  --secret grafana-token --briefing 07:30 --brain-path ~/notes --embed-model mxbai-embed-large >/dev/null || fail "init --dest failed"
[ -f "$HUB/hub.conf" ] && fail "--dest wrote into the template"
cd "$D"
for f in hub.conf CLAUDE.md ACCESS.md README.md .claude/agents/devops-sre.md ops/environments/STATE.md ops/ci-cd/CLAUDE.md \
         ops/monitoring/memory/MEMORY.md ops/security/ACCESS.md .claude/agents/ops-environments.md journal; do [ -e "$f" ] || fail "missing $f"; done
assert_contains CLAUDE.md "# acme-corp-devops-sre: the DevOps / Site Reliability Engineer" "title"
assert_contains CLAUDE.md "You are the **DevOps / Site Reliability Engineer** for Acme Corp, working for Sam Lee." "persona"
assert_contains CLAUDE.md "when Sam Lee says so" "owner in the rules"
grep -q "{{" CLAUDE.md ACCESS.md README.md .claude/agents/*.md && fail "unfilled placeholder"
. ./hub.conf; assert_eq "$HUB_REMOTE_HOST" "box.acme.test" "remote host"; assert_eq "$HUB_REMOTE_PORT" "2222" "remote port"
assert_eq "$HUB_REMOTE_USER" "deploy" "remote user"; assert_eq "$HUB_BRIEFING_HOUR:$HUB_BRIEFING_MINUTE" "7:30" "briefing time"
assert_eq "$HUB_SECRETS" "grafana-token" "secret names"
assert_eq "$HUB_BRAIN_PATHS|$HUB_EMBED_MODEL|$HUB_OLLAMA_URL" "$HOME/notes|mxbai-embed-large|http://localhost:11434" "brain settings"; assert_eq "$HUB_REPOS" "acme/infra" "repos"
assert_contains ops/environments/ACCESS.md "| acme/infra | $CO |" "first folder checks out the first repo"
assert_contains .claude/agents/ops-environments.md "You are the DevOps / Site Reliability Engineer, working only on ops/environments in the acme-corp-devops-sre hub" "folder agent persona"
out=$(env -u HUB WORK_DRY=1 bin/work ops/environments) || fail "deep work on the first folder"
echo "$out" | grep -q "cd '$CO'" || fail "work opens the repo checkout"
HUB="$D" bin/context | grep -q "^# acme-corp-devops-sre: every folder" || fail "context names the hub"
assert_contains "journal/$(date -u +%Y-%m-%d).md" "Hub initialized from ai-agent-hub-template" "journal entry"
[ "$(git config core.hooksPath)" = .githooks ] || fail "hooks path"
grep -rqi "orillia" . --exclude-dir=.git --exclude-dir=.claude --exclude-dir=tests && fail "Orillia leaked into a new hub"
# refusals: re-init, unknown persona, bad names, a secret value instead of a name
bin/init --persona devops-sre --client X --owner Y >/dev/null 2>&1; assert_eq "$?" "2" "an initialized hub is never re-initialized"
cd "$HUB"
bin/init --persona nope --client X --owner Y --dest "$(mktemp -d)/n" >/dev/null 2>&1; assert_eq "$?" "2" "unknown persona"
bin/init --persona tech-lead --client X >/dev/null 2>&1; assert_eq "$?" "2" "owner required"
bin/init --persona tech-lead --client X --owner Y --dest "$D" >/dev/null 2>&1; assert_eq "$?" "2" "existing dest refused"
bin/init --persona tech-lead --client X --owner Y --secret 'sk-ABC123=' --dest "$(mktemp -d)/s" >/dev/null 2>&1; assert_eq "$?" "2" "secret value refused"
bin/init --persona tech-lead --client X --owner Y --briefing 25:00 --dest "$(mktemp -d)/b" >/dev/null 2>&1; assert_eq "$?" "2" "bad briefing time"
bin/init --persona tech-lead --client X --owner Y --folders "projects/Bad" --dest "$(mktemp -d)/f" >/dev/null 2>&1; assert_eq "$?" "2" "bad folder"
# in place, default folders and name from the client
bin/init --persona staff-software-engineer --client "Beta Inc" --owner "Pat" >/dev/null || fail "init in place failed"
assert_contains hub.conf "HUB_NAME=beta-inc-staff-software-engineer" "derived name"
for f in projects/app projects/proposals projects/client ops/environments; do [ -f "$f/STATE.md" ] || fail "default folder $f"; done
echo ok
