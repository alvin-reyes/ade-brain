#!/bin/bash
. "$(dirname "$0")/helpers.sh"
make_hub
. "$HUB/bin/lib.sh"
assert_eq "$(encode_path /Users/me/Project/acme-app)" "-Users-me-Project-acme-app" "encode slashes"
assert_eq "$(encode_path "/a/b.c_d e")" "-a-b-c-d-e" "encode dots, underscores, spaces"
assert_eq "$(hub_root)" "$HUB" "hub_root honours HUB"
[[ "$(utc_today)" =~ ^20[0-9]{2}-[01][0-9]-[0-3][0-9]$ ]] || fail "utc_today format"
echo ok
