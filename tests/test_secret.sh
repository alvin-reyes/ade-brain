#!/bin/bash
. "$(dirname "$0")/helpers.sh"
make_hub; cd "$HUB"
S="$(mktemp -d)"; export STORE="$S/store"; : > "$STORE"   # stub `security`: a name=value file
cat > "$S/security" <<'STUB'
#!/bin/bash
op="$1"; shift; acct=""; val=""; w=0
while [ $# -gt 0 ]; do case "$1" in -a) acct="$2"; shift 2;; -w) if [ $# -ge 2 ]; then val="$2"; shift 2; else w=1; shift; fi;; *) shift;; esac; done
case "$op" in
  add-generic-password) grep -v "^$acct=" "$STORE" > "$STORE.t"; mv "$STORE.t" "$STORE"; echo "$acct=$val" >> "$STORE";;
  find-generic-password) l=$(grep "^$acct=" "$STORE") || exit 44; [ "$w" = 1 ] && echo "${l#*=}"; exit 0;;
  delete-generic-password) grep -q "^$acct=" "$STORE" || exit 44; grep -v "^$acct=" "$STORE" > "$STORE.t"; mv "$STORE.t" "$STORE";;
esac
STUB
chmod +x "$S/security"; export PATH="$S:$PATH"
printf 'pat-123\n' | bin/secret --set api-token 2>err || fail "set failed"
grep -q "pat-123" err && fail "set echoed the value"
assert_eq "$(bin/secret api-token)" "pat-123" "get returns the value"
bin/secret --has api-token || fail "--has after set"
bin/secret --forget api-token 2>/dev/null; bin/secret --has api-token && fail "--has after forget"
bin/secret nope 2>err; assert_eq "$?" "1" "missing secret exits 1"; assert_contains err "not stored" "says how to store it"
printf '\n' | bin/secret --set empty 2>/dev/null; assert_eq "$?" "1" "empty value refused"
bin/secret >/dev/null 2>&1; assert_eq "$?" "2" "no args exits 2"
echo ok
