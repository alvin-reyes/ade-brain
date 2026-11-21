#!/bin/bash
# Browser automation on the server (story V3, .ade/context/browser.md): bin/browser and its part of bin/server.
# bash tests/test_browser.sh [check ...] runs only the named checks (all of them by default).
# Hermetic: fake Chromium (a Playwright-style install under $HOME/.cache/ms-playwright), Xvfb, x11vnc, websockify and
# npx first on PATH; no browser, display or port is ever opened.
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"
S="$(mktemp -d)"; S="$(cd "$S" && pwd -P)"; mkdir -p "$S/bin" "$S/home" "$S/state"
export HOME="$S/home" AGENT_STATE="$S/state" S; unset PLAYWRIGHT_BROWSERS_PATH
trap 'for p in $(cat "$S"/*.pid 2>/dev/null); do kill "$p" 2>/dev/null; done; rm -rf "$S" "$(dirname "$HUB")" "$CLAUDE_HOME" "$(dirname "$AGENT_SYNC_LOG")" "$(dirname "$AGENT_SYNC_LOCK")"' EXIT
bin/new projects/acme >/dev/null; bin/new projects/beta >/dev/null
# each fake records its argv and pid, then stays up until killed (Chromium until killed or $S/close-browser appears)
for t in Xvfb x11vnc websockify; do
  printf '#!/bin/bash\nprintf "%%s\\n" "$@" > "$S/%s.argv"; echo $$ > "$S/%s.pid"\n%s\nexec sleep 30\n' "$t" "$t" \
    "$([ "$t" = x11vnc ] && echo 'for a; do case "$a" in rm:*) f="${a#rm:}"; cat "$f" > "$S/x11vnc.pw"; rm -f "$f";; esac; done')" > "$S/bin/$t"; done
CH="$HOME/.cache/ms-playwright/chromium-1234/chrome-linux/chrome"
make_chromium() { mkdir -p "$(dirname "$CH")"; printf '#!/bin/bash\nprintf "%%s\\n" "$@" > "$S/chrome.argv"; env > "$S/chrome.env"; echo $$ > "$S/chrome.pid"\nfor i in $(seq 1 120); do [ -e "$S/close-browser" ] && exit 0; sleep 0.25; done\n' > "$CH"; chmod +x "$CH"; }
chmod +x "$S"/bin/*; export PATH="$S/bin:$PATH"
conf() { printf '%s\n' "$@" > hub.conf; }
mcp_args() { bin/browser mcp "$1" | python3 -c 'import json, sys; print("\n".join(json.load(sys.stdin)["args"]))'; }
arg_after() { awk -v k="$1" 'p{print; exit} $0==k{p=1}' "$2"; }
alive() { local f; for f in "$@"; do [ -f "$S/$f.pid" ] && kill -0 "$(cat "$S/$f.pid")" 2>/dev/null && return 0; done; return 1; }

server_installs_chromium() {   # AC1
  grep -q 'xvfb x11vnc novnc websockify' bin/server || fail "the server's package list has the view's packages"
  grep -q 'playwright@.* install --with-deps chromium' bin/server || fail "bin/server installs Chromium and its system dependencies"
  rm -rf "$HOME/.cache"; bin/browser status > "$S/out" 2>&1; assert_eq "$?" 1 "no Chromium yet"; assert_contains "$S/out" "missing" "status says missing"
  make_chromium; bin/browser status > "$S/out"; assert_eq "$?" 0 "Chromium found"; grep -q "^ready  chromium $CH" "$S/out" || fail "status: $(cat "$S/out")"
  AGENT_PLATFORM=linux bin/server status 2>/dev/null | grep -q 'browser  *ready' || fail "ade server status shows the browser: $(AGENT_PLATFORM=linux bin/server status 2>&1)"
}
isolated_by_default() {   # AC2, AC6
  make_chromium; conf '# none'; mcp_args projects/acme > "$S/args"
  grep -qx -- --isolated "$S/args" || fail "isolated by default: $(cat "$S/args")"; grep -qx -- --user-data-dir "$S/args" && fail "no profile by default"
  grep -qx -- --headless "$S/args" && [ "$(arg_after --browser "$S/args")" = chromium ] || fail "headless Chromium"
  assert_eq "$(arg_after --output-dir "$S/args")" "$HUB/projects/acme/reports/browser" "screenshots and downloads in the folder"
  [ -d projects/acme/reports/browser ] || fail "output folder made"
  echo data > projects/acme/reports/browser/download.csv; git check-ignore -q projects/acme/reports/browser/download.csv || fail "browser files never sync to the hub's git"
  rm -f projects/acme/reports/browser/download.csv
  conf 'HUB_BROWSER_PROFILE_ACME=1'; mcp_args projects/acme > "$S/args"
  assert_eq "$(arg_after --user-data-dir "$S/args")" "$HOME/.config/ade/browser/acme" "profile mode per folder"; grep -qx -- --isolated "$S/args" && fail "profile mode is not isolated"
  assert_eq "$(fmode "$HOME/.config/ade/browser/acme")" 700 "profile 0700"
  mcp_args projects/beta | grep -qx -- --isolated || fail "another folder stays isolated"
  HUB_BROWSER_PROFILE_BETA=1 bin/browser mcp projects/beta | grep -q user-data-dir && fail "profile mode comes only from hub.conf"
  rm -rf projects/acme/reports/browser; ln -s "$S" projects/acme/reports/browser
  bin/browser mcp projects/acme >/dev/null 2> "$S/err"; assert_eq "$?" 1 "an output folder outside the folder is refused"; assert_contains "$S/err" "outside" "says why"
  rm -f projects/acme/reports/browser
  bin/browser mcp projects/nope >/dev/null 2>&1; assert_eq "$?" 2 "unknown folder"
}
login_tunnelled_view() {   # AC3
  make_chromium; conf 'HUB_BROWSER_PROFILE_ACME=1'; rm -f "$S"/*.argv "$S"/*.pid "$S/close-browser" "$S/x11vnc.pw"
  { sleep 3; echo; } | bin/browser login projects/acme https://tool.example/login > "$S/out" 2> "$S/err"; assert_eq "$?" 0 "login: $(cat "$S/err")"
  assert_eq "$(sed -n 1p "$S/Xvfb.argv")" ":99" "a private display"; grep -qx -- -nolisten "$S/Xvfb.argv" && [ "$(arg_after -nolisten "$S/Xvfb.argv")" = tcp ] || fail "Xvfb takes no TCP"
  grep -qx -- -localhost "$S/x11vnc.argv" || fail "x11vnc on localhost only"
  grep -q -- '^rm:' "$S/x11vnc.argv" || fail "one-time password file, read and removed"; [ -s "$S/x11vnc.pw" ] || fail "a password was set"
  grep -qF -- "$(cat "$S/x11vnc.pw")" "$S/x11vnc.argv" && fail "the password is in an argument"
  assert_eq "$(sed -n 3p "$S/websockify.argv")" "127.0.0.1:6080" "noVNC on 127.0.0.1 only"
  grep -q -- "--user-data-dir=$HOME/.config/ade/browser/acme" "$S/chrome.argv" && grep -qx "https://tool.example/login" "$S/chrome.argv" || fail "Chromium on the folder's profile: $(cat "$S/chrome.argv")"
  grep -q 'ssh -N -L 6080:127.0.0.1:6080 ' "$S/out" && grep -q 'http://localhost:6080/vnc.html' "$S/out" || fail "the tunnel to use: $(cat "$S/out")"
  sleep 0.5; alive Xvfb x11vnc websockify chrome && fail "the view is still up after Enter"
  rm -f "$S"/*.pid; ( sleep 3; touch "$S/close-browser" ) & sleep 30 | bin/browser login projects/acme https://tool.example/login >/dev/null 2>&1 &
  local lp=$! i; for i in $(seq 1 60); do kill -0 "$lp" 2>/dev/null || break; sleep 0.25; done
  kill -0 "$lp" 2>/dev/null && { kill "$lp"; fail "closing the browser ends the view"; }; sleep 0.5; alive Xvfb x11vnc websockify && fail "the view is still up after the browser closed"
  rm -f "$S/close-browser"
  conf '# none'; bin/browser login projects/acme https://tool.example/ >/dev/null 2> "$S/err" </dev/null; assert_eq "$?" 2 "profile mode off"; assert_contains "$S/err" "HUB_BROWSER_PROFILE_ACME=1" "says how"
  conf 'HUB_BROWSER_PROFILE_ACME=1'; bin/browser login projects/acme 'javascript:alert(1)' >/dev/null 2>&1 </dev/null; assert_eq "$?" 2 "only http(s)"
}
profiles_per_folder() {   # AC4
  make_chromium; conf 'HUB_BROWSER_PROFILE_ACME=1' 'HUB_BROWSER_PROFILE_BETA=1'
  a="$(mcp_args projects/acme | awk 'p{print; exit} $0=="--user-data-dir"{p=1}')"; b="$(mcp_args projects/beta | awk 'p{print; exit} $0=="--user-data-dir"{p=1}')"
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" != "$b" ] || fail "each folder its own profile: [$a] [$b]"
  echo cookie > "$a/Cookies"; echo cookie > "$b/Cookies"
  bin/browser forget projects/acme > "$S/out" 2>&1 || fail "forget: $(cat "$S/out")"
  [ ! -e "$a" ] || fail "acme's profile deleted"; [ -f "$b/Cookies" ] || fail "beta's profile kept"
  bin/browser forget projects/acme | grep -q "no profile" || fail "forgetting twice is fine"
  rm -rf "$b"; ln -s "$S" "$b"; bin/browser forget projects/beta >/dev/null 2>&1; assert_eq "$?" 1 "a linked profile is not followed"; [ -d "$S/bin" ] || fail "the link's target survived"; rm -f "$b"
}
ask_first_unchanged() {   # AC5
  local a; mcp_args projects/acme > "$S/args"
  for a in --allow-unrestricted-file-access --no-sandbox --caps --allowed-origins --blocked-origins --ignore-https-errors; do grep -qx -- "$a" "$S/args" && fail "the hub changes the plugin's rules ($a)"; done
  grep -Eqi 'browser.? plugin.*ask-first' templates/hub/CLAUDE.md && grep -qi 'telegram' templates/hub/CLAUDE.md || fail "the hub rules keep the browser plugin's ask-first rules, asked over Telegram on the server"
}

ALL="server_installs_chromium isolated_by_default login_tunnelled_view profiles_per_folder ask_first_unchanged"
for t in ${@:-$ALL}; do "$t"; done
echo ok
