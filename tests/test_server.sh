#!/bin/bash
# bin/server (story V2, .ade/context/server.md): `ade server install` and `ade server status` on an Ubuntu VPS.
# bash tests/test_server.sh [check ...] runs only the named checks (all of them by default).
# Hermetic: AGENT_PLATFORM=linux and fakes first on PATH (sudo, apt-get, dpkg-query, sshd, ufw, systemctl, loginctl,
# curl, id, uname); nothing is installed, no network is reached, no real service is touched.
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"
S="$(mktemp -d)"; S="$(cd "$S" && pwd -P)"; mkdir -p "$S/bin" "$S/home" "$S/state" "$S/apt" "$S/dl"
export HOME="$S/home" AGENT_STATE="$S/state" AGENT_PLATFORM=linux AGENT_APT_CONF_DIR="$S/apt" AGENT_SYSTEMD_USER_DIR="$S/units"
export PASSWORD_STORE_DIR="$S/no-pass" S
trap 'rm -rf "$S" "$(dirname "$HUB")" "$CLAUDE_HOME" "$(dirname "$AGENT_SYNC_LOG")" "$(dirname "$AGENT_SYNC_LOCK")"' EXIT
REAL_UID="$(id -u)"
# every fake logs one line to $S/calls; state lives in files under $S
cat > "$S/bin/sudo" <<'STUB'
#!/bin/bash
echo "sudo $*" >> "$S/calls"; [ -e "$S/nosudo" ] && exit 1
while [ "${1#-}" != "$1" ]; do [ "$1" = -v ] && exit 0; shift; done; exec "$@"
STUB
cat > "$S/bin/apt-get" <<'STUB'
#!/bin/bash
echo "apt-get $*" >> "$S/calls"; [ "$1" = install ] || exit 0
for p in "$@"; do case "$p" in -*|install) ;; *) echo "$p" >> "$S/installed" ;; esac; done
STUB
printf '#!/bin/bash\nfor p; do :; done; grep -qx "$p" "$S/installed" 2>/dev/null && printf "install ok installed" || exit 1\n' > "$S/bin/dpkg-query"
# apt-cache: every package is in the archive except those in $S/unpackaged (yazi by default, as on Ubuntu 24.04)
printf '#!/bin/bash\necho "apt-cache $*" >> "$S/calls"; for p; do :; done; grep -qx "$p" "$S/unpackaged" 2>/dev/null && exit 100; echo "Package: $p"\n' > "$S/bin/apt-cache"
printf '#!/bin/bash\necho "sshd $*" >> "$S/calls"; cat "$S/sshd.conf"\n' > "$S/bin/sshd"
printf '#!/bin/bash\necho "ufw $*" >> "$S/calls"; cat "$S/ufw.status"\n' > "$S/bin/ufw"
cat > "$S/bin/systemctl" <<'STUB'
#!/bin/bash
echo "systemctl $*" >> "$S/calls"
case " $* " in *" enable --now "*) for a; do u="$a"; done; echo "$u" >> "$S/active"; exit 0 ;; *" disable --now "*) for a; do u="$a"; done; grep -vx "$u" "$S/active" > "$S/active.t"; mv "$S/active.t" "$S/active"; exit 0 ;;
  *" is-enabled unattended-upgrades "*) cat "$S/uu" 2>/dev/null || echo disabled; exit 0 ;; *" is-active "*) for a; do u="$a"; done; grep -qx "$u" "$S/active" 2>/dev/null; exit ;; esac
exit 0
STUB
printf '#!/bin/bash\necho "loginctl $*" >> "$S/calls"; [ "$1" = show-user ] && echo Linger=no; exit 0\n' > "$S/bin/loginctl"
# curl: never the network. A gitleaks tarball and checksums from $S/dl; the bun and claude installers become scripts
# that make a fake binary
cat > "$S/bin/curl" <<'STUB'
#!/bin/bash
echo "curl $*" >> "$S/calls"; o=""; u=""
while [ $# -gt 0 ]; do case "$1" in -o) o="$2"; shift 2 ;; -*) shift ;; *) u="$1"; shift ;; esac; done
case "$u" in
  *.tar.gz) cp "$S/dl/gitleaks.tar.gz" "$o" ;;
  *checksums.txt) cp "$S/dl/sums" "$o" ;;
  https://bun.sh/install) printf 'mkdir -p "$HOME/.bun/bin"; printf "#!/bin/bash\\necho $1\\n" > "$HOME/.bun/bin/bun"; chmod +x "$HOME/.bun/bin/bun"\n' ;;
  https://claude.ai/install.sh) printf 'mkdir -p "$HOME/.local/bin"; printf "#!/bin/bash\\necho $1\\n" > "$HOME/.local/bin/claude"; chmod +x "$HOME/.local/bin/claude"\n' ;;
  *) echo "fake curl: unexpected $u" >&2; exit 22 ;;
esac
STUB
printf '#!/bin/bash\n[ "${1:-}" = -u ] && [ -e "$S/root" ] && { echo 0; exit 0; }\nexec /usr/bin/id "$@"\n' > "$S/bin/id"
printf '#!/bin/bash\n[ "${1:-}" = -m ] && { echo x86_64; exit 0; }\nexec /usr/bin/uname "$@"\n' > "$S/bin/uname"
chmod +x "$S"/bin/*
# a PATH that holds no real gitleaks, bun or claude: the fakes, then only the system tools the scripts use
mkdir -p "$S/sys"; for c in bash sh env cat grep sed awk tr cut head tail sort uniq wc mkdir rm mv cp ln chmod ls date dirname basename \
  mktemp printf python3 git tar gzip find df stat touch sleep ps pgrep tee xargs readlink id uname shasum sha256sum; do
  p="$(PATH=/usr/bin:/bin:/usr/sbin:/sbin command -v "$c" 2>/dev/null)"; [ -n "$p" ] && [ ! -e "$S/sys/$c" ] && ln -s "$p" "$S/sys/$c"; done
rm -f "$S/sys/id" "$S/sys/uname"; export PATH="$S/bin:$S/sys"
# the fake gitleaks release and its checksum
mkdir -p "$S/g"; printf '#!/bin/bash\necho 8.30.1\n' > "$S/g/gitleaks"; chmod +x "$S/g/gitleaks"
tar -czf "$S/dl/gitleaks.tar.gz" -C "$S/g" gitleaks
printf '%s  gitleaks_8.30.1_linux_x64.tar.gz\n' "$(python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$S/dl/gitleaks.tar.gz")" > "$S/dl/sums"

safe() { printf 'port 22\npasswordauthentication no\npermitrootlogin no\n' > "$S/sshd.conf"
  printf 'Status: active\n\nTo                         Action      From\n--                         ------      ----\nOpenSSH                    ALLOW       Anywhere\nOpenSSH (v6)               ALLOW       Anywhere (v6)\n' > "$S/ufw.status"
  echo enabled > "$S/uu"; printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\n' > "$S/apt/20auto-upgrades"; }
reset() { echo yazi > "$S/unpackaged"; rm -rf "$S/calls" "$S/installed" "$S/root" "$S/nosudo" "$S/units" "$HOME/.local" "$HOME/.bun" "$HOME/Project" "$S/active"; : > "$S/calls"; safe; }
install() { bin/server install "$@" > "$S/out" 2> "$S/err"; rc=$?; }
changes() { grep -E '^(apt-get install|sudo apt-get install|curl|systemctl --user enable|loginctl enable)' "$S/calls"; }

installs_missing_from_fixed_list() {   # AC1
  reset; echo git > "$S/installed"; install; assert_eq "$rc" 0 "install: $(cat "$S/err" "$S/out")"
  grep -q '^apt-get install -y -q --no-install-recommends python3 tmux gh curl ca-certificates nodejs npm ufw unattended-upgrades bat glow poppler-utils chafa$' "$S/calls" || fail "only the missing packages, ade's tools too: $(grep apt-get "$S/calls")"
  grep -q 'yazi: not packaged for this system; skipped' "$S/out" || fail "an extra that is not packaged is skipped with a note: $(cat "$S/out")"
  [ -x "$HOME/.local/bin/gitleaks" ] || fail "gitleaks installed"; grep -q 'releases/download/v8.30.1/gitleaks_8.30.1_linux_x64.tar.gz' "$S/calls" || fail "gitleaks pinned"
  grep -q 'curl -fsSL https://bun.sh/install' "$S/calls" && [ "$("$HOME/.bun/bin/bun")" = bun-v1.3.9 ] || fail "bun pinned: $("$HOME/.bun/bin/bun" 2>&1)"
  [ "$("$HOME/.local/bin/claude")" = 2.1.330 ] || fail "claude pinned"
  [ -d "$HOME/Project" ] || fail "code folder"
  [ -f "$S/units/ade-hub-monitor.timer" ] || fail "bin/schedule install ran"
  : > "$S/calls"; install; assert_eq "$rc" 0 "rerun: $(cat "$S/err")"
  assert_eq "$(changes)" "" "a rerun installs nothing"
  grep -q "all present" "$S/out" && grep -q "gitleaks: present" "$S/out" && grep -q "claude: present" "$S/out" || fail "rerun says so: $(cat "$S/out")"
  reset; cp "$S/dl/sums" "$S/dl/sums.keep"; printf '%064d  gitleaks_8.30.1_linux_x64.tar.gz\n' 0 > "$S/dl/sums"
  install; assert_eq "$rc" 1 "a gitleaks tarball that does not match its checksum"; [ ! -e "$HOME/.local/bin/gitleaks" ] || fail "an unverified gitleaks was installed"
  cp "$S/dl/sums.keep" "$S/dl/sums"
}
refuses_root_needs_sudo() {   # AC2
  reset; touch "$S/root"; install; assert_eq "$rc" 2 "root"; assert_contains "$S/err" "never as root" "says why"
  assert_eq "$(grep -c . "$S/calls")" 0 "nothing ran as root"
  reset; touch "$S/nosudo"; install; assert_eq "$rc" 2 "no sudo"; assert_contains "$S/err" "sudo" "says why"
  assert_eq "$(changes)" "" "nothing installed without sudo"
  reset; AGENT_PLATFORM=macos bin/server install >/dev/null 2>&1; assert_eq "$?" 2 "not Linux"
}
safety_rows() {   # AC3
  reset; install; local r; for r in ssh-password ssh-root firewall upgrades; do grep -q "^OK  *$r " "$S/out" || fail "row $r: $(cat "$S/out")"; done
  reset; printf 'passwordauthentication yes\npermitrootlogin prohibit-password\n' > "$S/sshd.conf"; install
  assert_eq "$rc" 1 "unsafe ssh fails the install"; grep -q '^FAIL  *ssh-password ' "$S/out" && grep -q '^FAIL  *ssh-root ' "$S/out" || fail "rows: $(cat "$S/out")"
  assert_eq "$(changes)" "" "nothing changes on an unsafe host"; grep -q -- "--accept-risk" "$S/err" || fail "names the way out"
  install --accept-risk ssh-password; assert_eq "$rc" 1 "one accepted, one still failing"
  install --accept-risk ssh-password --accept-risk ssh-root; assert_eq "$rc" 0 "both accepted: $(cat "$S/err")"
  grep -q '^ACCEPTED  *ssh-password ' "$S/out" || fail "accepted rows shown as such"
  reset; printf 'Status: inactive\n' > "$S/ufw.status"; install; assert_eq "$rc" 1 "ufw off"; grep -q '^FAIL  *firewall ' "$S/out" || fail "firewall row"
  reset; printf 'Status: active\n\nTo Action From\n-- ------ ----\n22/tcp ALLOW Anywhere\n80/tcp ALLOW Anywhere\n' > "$S/ufw.status"; install
  assert_eq "$rc" 1 "a public web port"; grep -q '^FAIL  *firewall .*80/tcp' "$S/out" || fail "names the extra rule: $(cat "$S/out")"
  reset; echo disabled > "$S/uu"; install; assert_eq "$rc" 1 "upgrades off"; grep -q '^FAIL  *upgrades ' "$S/out" || fail "upgrades row"
  install --accept-risk nonsense; assert_eq "$rc" 2 "an unknown row"
}
manual_step_printed() {   # AC4
  reset; install; assert_eq "$rc" 0 "install"
  grep -q "claude .*Pro or Max login" "$S/out" || fail "claude login step: $(cat "$S/out")"
  grep -q "bin/keys set telegram" "$S/out" || fail "telegram key step"
  grep -qi "public port" "$S/out" || fail "says nothing listens"
}
status_report() {   # AC5
  reset; install >/dev/null; printf 'pl-SECRET-%s\n' "$RANDOM" | bin/secret --set telegram-bot-token 2>/dev/null || fail "store a secret"
  mkdir -p "$AGENT_STATE/logs"; echo synced > "$AGENT_STATE/logs/sync.log"; echo ran > "$AGENT_STATE/logs/monitor.log"
  echo ade-hub-monitor.timer > "$S/active"; : > "$S/calls"   # only monitor running
  bin/server status > "$S/out" 2>&1; assert_eq "$?" 0 "status: $(cat "$S/out")"
  grep -q 'loaded  ade-hub-monitor.timer' "$S/out" && grep -q 'absent  ade-hub-sync.timer' "$S/out" || fail "services: $(cat "$S/out")"
  grep -q 'last sync  *20[0-9-]* [0-9:]* UTC' "$S/out" && grep -q 'last monitor  *20' "$S/out" || fail "last runs: $(cat "$S/out")"
  grep -q 'disk  *[0-9.]* GB free' "$S/out" || fail "disk: $(cat "$S/out")"
  grep -q 'pl-SECRET' "$S/out" && fail "status printed a secret"
  rm -f "$AGENT_STATE/logs/sync.log"; bin/server status | grep -q 'last sync  *never' || fail "never synced"
}
dry_run_changes_nothing() {   # AC6
  reset; bin/server install --dry-run > "$S/out" 2> "$S/err"; assert_eq "$?" 0 "dry run: $(cat "$S/err")"
  assert_eq "$(changes)" "" "a dry run installs nothing"; [ ! -e "$S/units" ] && [ ! -d "$HOME/Project" ] && [ ! -e "$HOME/.local/bin/gitleaks" ] || fail "a dry run changed the machine"
  grep -q '^+ sudo apt-get install -y -q --no-install-recommends git python3 tmux gh .* bat glow poppler-utils chafa$' "$S/out" || fail "prints the apt command, ade's tools too: $(cat "$S/out")"
  grep -q '^+ curl -fsSL -o .*gitleaks_8.30.1_linux_x64.tar.gz' "$S/out" && grep -q "^+ bash -c curl.*bun.sh/install" "$S/out" && grep -q "^+ bash -c curl.*claude.ai/install.sh" "$S/out" || fail "prints the tool installs: $(cat "$S/out")"
  grep -q "^+ mkdir -p $HOME/Project" "$S/out" && grep -q "^+ $HUB/bin/schedule install" "$S/out" || fail "prints the hub steps: $(cat "$S/out")"
  printf 'passwordauthentication yes\npermitrootlogin no\n' > "$S/sshd.conf"; bin/server install --dry-run > "$S/out" 2>&1; assert_eq "$?" 1 "dry run on an unsafe host exits as the install would"
  grep -q '^+ sudo apt-get install' "$S/out" || fail "still prints the plan"; assert_eq "$(changes)" "" "still changes nothing"
}

ALL="installs_missing_from_fixed_list refuses_root_needs_sudo safety_rows manual_step_printed status_report dry_run_changes_nothing"
for t in ${@:-$ALL}; do "$t"; done
echo ok
