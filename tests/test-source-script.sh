#!/usr/bin/env bash
# Tests for lib/source-script.sh, the library every Script sources (#75).
#
# What the library owns is what is the same for every Source: the Requirement
# preflight and the Blocked report (ADR 0005), the Account registry and its
# first-registration-wins rule, the argument parsing the settings page and the
# widget share, the listing answer, and the result file reader and writer.
#
# These tests cross the library's own interface: they source it and call it,
# rather than running a Script and reading its report. The four Scripts' own
# tests, and tests/test-requirement-preflight.sh, stay the proof that each
# Script wires the library in.
#
# Each case body is a string this file hands to a fresh bash, so the expansions
# in it are meant to happen there and not here: the single quotes are the point.
# shellcheck disable=SC2016
set -eu

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$REPO_DIR/lib/source-script.sh"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }
assert_eq() {
    if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (expected '$2', got '$1')"; fi
}

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# Each case runs in its own bash so the registry starts empty and a case that
# exits cannot take the suite with it. SCRIPT_DIR is what the library resolves
# the manifest against, so every case is handed one.
run_case() {
    local body="$1" dir="${2:-$REPO_DIR}"
    SCRIPT_DIR="$dir" bash -c "
        set -eu
        SCRIPT_DIR='$dir'
        . '$LIB'
        $body
    " 2>&1
}

# A plugin.json declaring the given commands, for the preflight cases.
make_manifest() {
    local dir="$1"
    shift
    local list="" name
    mkdir -p "$dir"
    for name in "$@"; do
        list="${list:+$list, }\"$name\""
    done
    cat > "$dir/plugin.json" <<EOF
{
  "id": "aiUsage",
  "requires": [$list],
  "permissions": []
}
EOF
    printf '%s' "$dir"
}

echo "=== Requirement names"

out=$(run_case 'requirement_names "$SCRIPT_DIR/plugin.json" | tr "\n" " "')
assert_eq "$out" "jq curl " "requirement_names reads the manifest's requires list"

EMPTY_DIR=$(make_manifest "$TMPDIR_ROOT/no-requires")
out=$(run_case 'requirement_names "$SCRIPT_DIR/plugin.json" | wc -l' "$EMPTY_DIR")
assert_eq "$out" "0" "an empty requires list names nothing"

echo "=== Requirement preflight"

# A PATH holding only what the library itself needs, so the named Requirements
# are genuinely absent rather than shadowed.
BARE_PATH="$TMPDIR_ROOT/bare"
mkdir -p "$BARE_PATH"
for name in bash sed tr cat dirname; do
    ln -sf "$(command -v "$name")" "$BARE_PATH/$name"
done

MANIFEST_DIR=$(make_manifest "$TMPDIR_ROOT/manifest" jq curl)

out=$(PATH="$BARE_PATH" run_case 'require_requirements; echo REACHED' "$MANIFEST_DIR")
assert_eq "$(echo "$out" | grep '^CREDS_STATUS=')" "CREDS_STATUS=blocked" \
    "a missing Requirement reports Blocked"
assert_eq "$(echo "$out" | grep '^BLOCKING_REQUIREMENT=')" "BLOCKING_REQUIREMENT=jq,curl" \
    "every missing command is named, in manifest order"
assert_eq "$(echo "$out" | grep -c '^REACHED$')" "0" \
    "nothing downstream of the preflight runs"
assert_eq "$(echo "$out" | grep '^ACCOUNTS=')" "ACCOUNTS=" \
    "the Blocked report carries an empty Account list"
assert_eq "$(echo "$out" | grep -c '^ACCOUNT_ORIGINS=')" "0" \
    "a fetch call is not answered with the listing's extra keys"

out=$(PATH="$BARE_PATH" run_case 'require_requirements --list-accounts' "$MANIFEST_DIR")
assert_eq "$(echo "$out" | grep -c '^ACCOUNT_ORIGINS=$')" "1" \
    "a listing call is answered with empty origins"
assert_eq "$(echo "$out" | grep -c '^ACCOUNT_SHADOWED=$')" "1" \
    "a listing call is answered with empty shadowed rows"

out=$(PATH="$BARE_PATH" run_case 'ACCOUNT_LIST_KEY=PROFILES
ACCOUNT_KEY_PREFIX=PROFILE_
require_requirements --list-accounts' "$MANIFEST_DIR")
assert_eq "$(echo "$out" | grep -c '^PROFILES=$')" "1" \
    "the Blocked report uses the Script's own list key"
assert_eq "$(echo "$out" | grep -c '^PROFILE_ORIGINS=$')" "1" \
    "the Blocked report uses the Script's own key prefix"

out=$(run_case 'require_requirements; echo REACHED' "$MANIFEST_DIR")
assert_eq "$(echo "$out" | tail -1)" "REACHED" \
    "every Requirement present runs on past the preflight"

echo "=== Account registration"

out=$(run_case 'add_account one aaa "~/.one"
add_account two bbb "~/.two"
echo "$(IFS=,; echo "${ACCOUNT_NAMES[*]}")|$(account_origins)|$(account_shadowed)"')
assert_eq "$out" "one,two|one:~/.one,two:~/.two|" \
    "two distinct Accounts both register, each under its Origin"

out=$(run_case 'add_account one aaa "~/.one"
add_account one bbb custom
echo "$(IFS=,; echo "${ACCOUNT_NAMES[*]}")|$(IFS=,; echo "${ACCOUNT_VALUES[*]}")|$(account_shadowed)"')
assert_eq "$out" "one|aaa|one|one:custom" \
    "the first registration of a name wins and the loser is reported"

out=$(run_case 'add_account one aaa "~/.one"
add_account two aaa custom
echo "$(IFS=,; echo "${ACCOUNT_NAMES[*]}")|$(account_shadowed)"')
assert_eq "$out" "one|one|two:custom" \
    "the first registration of a value wins, and the winner names it"

out=$(run_case 'add_account one aaa "~/.one"
add_account two aaa "~/.two"
echo "[$(account_shadowed)]"')
assert_eq "$out" "[]" \
    "two detected registrations clashing is the Script's precedence, not a shadow row"

out=$(run_case 'add_account "a,b|c:d" aaa "x,y|z:w"
echo "$(IFS=,; echo "${ACCOUNT_NAMES[*]}")|$(account_origins)"')
assert_eq "$out" "abcd|abcd:xyz:w" \
    "the list delimiters are stripped from a name and an Origin, the colon only from a name"

out=$(run_case 'add_account "" aaa custom
add_account named "" custom
echo "[${#ACCOUNT_NAMES[@]}]"')
assert_eq "$out" "[0]" \
    "an Account with no name or no value is not an Account"

out=$(run_case 'echo "[$(account_origins)][$(account_shadowed)]"')
assert_eq "$out" "[][]" \
    "an empty registry joins to nothing rather than failing under set -u"

echo "=== Argument parsing"

out=$(run_case 'parse_account_args alpha=aaa beta=bbb
echo "$LIST_ACCOUNTS|$(IFS=,; echo "${ACCOUNT_NAMES[*]}")|$(account_origins)"')
assert_eq "$out" "0|alpha,beta|alpha:custom,beta:custom" \
    "a name=value argument registers a Custom Account"

out=$(run_case 'parse_account_args --list-accounts alpha=aaa
echo "$LIST_ACCOUNTS|$(IFS=,; echo "${ACCOUNT_NAMES[*]}")"')
assert_eq "$out" "1|alpha" \
    "--list-accounts is recorded and the Custom Accounts still register"

out=$(run_case 'parse_account_args
echo "$LIST_ACCOUNTS|[${#ACCOUNT_NAMES[@]}]"')
assert_eq "$out" "0|[0]" \
    "no arguments is a fetch call with no Custom Accounts"

out=$(run_case 'parse_account_args "alpha=k=with=equals"
echo "$(IFS=,; echo "${ACCOUNT_VALUES[*]}")"')
assert_eq "$out" "k=with=equals" \
    "a value carrying an equals sign survives the split"

echo "=== Account listing"

out=$(run_case 'add_account one aaa "~/.one"
add_account two aaa custom
emit_account_listing' | tr '\n' '|')
assert_eq "$out" "ACCOUNTS=one|ACCOUNT_ORIGINS=one:~/.one|ACCOUNT_SHADOWED=one|two:custom|" \
    "the listing answers with names, Origins and shadowed rows"

out=$(run_case 'emit_account_listing' | tr '\n' '|')
assert_eq "$out" "ACCOUNTS=|ACCOUNT_ORIGINS=|ACCOUNT_SHADOWED=|CREDS_STATUS=not_installed|" \
    "an empty listing says why it is empty"

out=$(run_case 'ACCOUNT_LIST_KEY=PROFILES
ACCOUNT_KEY_PREFIX=PROFILE_
add_account one aaa "~/.one"
emit_account_listing' | tr '\n' '|')
assert_eq "$out" "PROFILES=one|PROFILE_ORIGINS=one:~/.one|PROFILE_SHADOWED=|" \
    "the listing uses the Script's own list key and prefix"

echo "=== Result files"

RESULT_FILE="$TMPDIR_ROOT/result"
printf 'PLAN_TYPE=pro\nPRIMARY_UTIL=\n' > "$RESULT_FILE"

out=$(run_case "result_value '$RESULT_FILE' PLAN_TYPE unknown")
assert_eq "$out" "pro" "result_value reads a key's value"

out=$(run_case "result_value '$RESULT_FILE' PRIMARY_UTIL 0")
assert_eq "$out" "0" "an empty value falls back to the default"

out=$(run_case "result_value '$RESULT_FILE' ABSENT fallback")
assert_eq "$out" "fallback" "an absent key falls back to the default"

out=$(run_case "result_value '$TMPDIR_ROOT/nope' ANY fallback")
assert_eq "$out" "fallback" "an absent file falls back to the default"

OUT_FILE="$TMPDIR_ROOT/written"
run_case "write_usage_result '$OUT_FILE' 'A=1' 'B=2'" >/dev/null
assert_eq "$(tr '\n' '|' < "$OUT_FILE")" "A=1|B=2|" "write_usage_result writes one line per value"
assert_eq "$(find "$TMPDIR_ROOT" -maxdepth 1 -name 'written.tmp.*' | wc -l)" "0" \
    "the temporary it published through is gone"

UNWRITABLE="$TMPDIR_ROOT/unwritable"
mkdir -p "$UNWRITABLE"
chmod 500 "$UNWRITABLE"
run_case "write_usage_result '$UNWRITABLE/result' 'A=1'" >/dev/null 2>&1 || true
assert_eq "$(find "$UNWRITABLE" -maxdepth 1 -type f | wc -l)" "0" \
    "a write that fails leaves no file behind, not a half-written one"
chmod 700 "$UNWRITABLE"

echo
echo "Passed: $PASS, Failed: $FAIL"
[ "$FAIL" -eq 0 ]
