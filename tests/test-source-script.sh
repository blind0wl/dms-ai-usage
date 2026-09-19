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
assert_match() {
    if printf '%s' "$1" | grep -qE "$2"; then pass "$3"; else fail "$3 (no match for '$2')"; fi
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

echo "=== The shared pricing cache"

# Cost figures price tokens at the providers' published API rates (ADR 0006),
# so the library carries one cache the fetch-path Scripts share. These cases
# cross its own interface the same way as the ones above: load_pricing and
# refresh_pricing are called directly, with a curl stub answering by URL and
# the cache in an isolated XDG_CACHE_HOME.
#
# The fixture carries the shapes the filter decides on: an OpenAI model, a
# dated OpenAI snapshot, an OpenAI entry the key filter drops, an unpriced
# one, Z.ai's own entries, and the same GLM model under another provider's
# rates.
PRICE_ENV="$TMPDIR_ROOT/pricing"
PRICE_CACHE="$PRICE_ENV/cache"
mkdir -p "$PRICE_ENV/bin"
export PRICE_ENV PRICE_CACHE

cat > "$PRICE_ENV/bin/curl" << 'STUBEOF'
#!/usr/bin/env bash
# Answer by URL: the price table from its fixture, the EUR rate from its own
# fixture, and an empty object for anything else. A fixture named but absent
# makes the call fail, the way a network outage does.
case "${*: -1}" in
    *model_prices_and_context_window.json)
        cat "${PRICE_FIXTURE:?}" 2>/dev/null || exit 1 ;;
    *frankfurter*)
        cat "${PRICE_EUR_FILE:-/dev/null}" 2>/dev/null || echo '{"rates":{}}' ;;
    *)
        echo '{}' ;;
esac
STUBEOF
chmod +x "$PRICE_ENV/bin/curl"

PRICE_FIXTURE="$PRICE_ENV/litellm.json"
export PRICE_FIXTURE
cat > "$PRICE_FIXTURE" << 'FIXTUREEOF'
{
    "gpt-5.1": {"input_cost_per_token": 1.25e-6, "output_cost_per_token": 1e-05, "cache_read_input_token_cost": 1.25e-7, "litellm_provider": "openai"},
    "gpt-4.1": {"input_cost_per_token": 2e-6, "output_cost_per_token": 8e-6, "litellm_provider": "openai"},
    "gpt-4.1-2025-04-14": {"input_cost_per_token": 2e-6, "output_cost_per_token": 8e-6, "litellm_provider": "openai"},
    "o3": {"input_cost_per_token": 2e-6, "output_cost_per_token": 8e-6, "cache_read_input_token_cost": 5e-7, "litellm_provider": "openai"},
    "text-embedding-3-small": {"input_cost_per_token": 2e-8, "litellm_provider": "openai"},
    "whisper-1": {"input_cost_per_token": 0, "litellm_provider": "openai"},
    "zai/glm-4.6": {"input_cost_per_token": 6e-7, "output_cost_per_token": 2.2e-6, "cache_read_input_token_cost": 1.1e-7, "litellm_provider": "zai"},
    "zai/glm-5.3": {"input_cost_per_token": 1.4e-6, "output_cost_per_token": 4.4e-6, "litellm_provider": "zai"},
    "openrouter/z-ai/glm-4.6": {"input_cost_per_token": 9e-7, "output_cost_per_token": 2.7e-6, "litellm_provider": "openrouter"}
}
FIXTUREEOF

PRICE_EUR_FILE="$PRICE_ENV/eur.json"
export PRICE_EUR_FILE
echo '{"rates":{"EUR":0.93}}' > "$PRICE_EUR_FILE"

# One rate out of the flattened awk string, numerically: jq's own spelling of
# a float varies across versions, so the value is what is asserted, not the
# text. Field 1 is the model, so input is field 2.
price_field() {
    printf '%s' "$1" | tr ',' '\n' | grep -F "$2:" | head -1 \
        | awk -F: -v f="${3:-2}" '{ printf "%.10g", ($f + 0) }'
}
expect_rate() {
    awk -v v="$(awk -v n="$1" 'BEGIN { printf "%.10g", n }')" -v got="$2" \
        'BEGIN { print (got == v) ? "y" : "n" }'
}

out=$(run_case '
    export PATH="$PRICE_ENV/bin:$PATH"
    export XDG_CACHE_HOME="$PRICE_CACHE"
    load_pricing
    printf "awk=%s\n" "$PRICING_AWK"
    printf "rate=%s\n" "$USD_EUR_RATE"
    printf "file=%s\n" "$(test -f "$XDG_CACHE_HOME/dms-ai-usage/pricing.json" && echo yes || echo no)"
')
PRICING_LINE=$(printf '%s' "$out" | sed -n 's/^awk=//p')
assert_eq "$(printf '%s' "$out" | sed -n 's/^file=//p')" "yes" \
    "load_pricing with no cache fetches and writes the shared cache"
assert_eq "$(printf '%s' "$out" | sed -n 's/^rate=//p')" "0.93" \
    "USD_EUR_RATE comes from Frankfurter"
assert_eq "$(price_field "$PRICING_LINE" gpt-5.1 2)" "$(awk 'BEGIN{printf "%.10g", 1.25e-6}')" \
    "the awk string carries the OpenAI input rate"
assert_eq "$(expect_rate 1.25e-7 "$(price_field "$PRICING_LINE" gpt-5.1 4)")" "y" \
    "the awk string carries the cache-read rate"
assert_eq "$(expect_rate 0 "$(price_field "$PRICING_LINE" gpt-5.1 5)")" "y" \
    "a cache-write rate the table omits prices as free"
assert_eq "$(expect_rate 2e-6 "$(price_field "$PRICING_LINE" gpt-4.1 4)")" "y" \
    "a cache-read rate the table omits prices at the input rate"
if printf '%s' "$PRICING_LINE" | grep -q 'zai/glm-4.6:'; then
    pass "the awk string carries Z.ai's own rates"
else
    fail "the awk string carries Z.ai's own rates (no zai/glm-4.6 entry)"
fi
assert_eq "$(printf '%s' "$PRICING_LINE" | grep -c 'openrouter/')" "0" \
    "a model under another provider's rates is left out"
assert_eq "$(printf '%s' "$PRICING_LINE" | grep -c 'text-embedding\|whisper')" "0" \
    "unrelated or unpriced OpenAI entries are left out"
assert_eq "$(find "$PRICE_CACHE" -name '.pricing.*' | wc -l)" "0" \
    "the refresh publishes through a temporary that is then gone"

# The bodies below run in a fresh bash under set -u, so every variable they
# name has to be exported, not just set.
TODAY=$(date +%Y-%m-%d)
export TODAY
out=$(run_case '
    export PATH="$PRICE_ENV/bin:$PATH"
    export XDG_CACHE_HOME="$PRICE_CACHE"
    mkdir -p "$XDG_CACHE_HOME/dms-ai-usage"
    printf "%s" "{\"updated\": \"$TODAY\", \"models\": {\"zai/glm-5.3\": {\"input\": 1.4e-6, \"output\": 4.4e-6, \"cache_read\": 1.4e-6, \"cache_write\": 0}}, \"usd_eur_rate\": 0.91}" \
        > "$XDG_CACHE_HOME/dms-ai-usage/pricing.json"
    PRICE_FIXTURE="$PRICE_ENV/absent.json" load_pricing
    printf "awk=%s\n" "$PRICING_AWK"
    printf "rate=%s\n" "$USD_EUR_RATE"
')
assert_eq "$(printf '%s' "$out" | sed -n 's/^rate=//p')" "0.91" \
    "a cache from today answers without the network"
assert_match "$(printf '%s' "$out" | sed -n 's/^awk=//p')" 'zai/glm-5.3:' \
    "today's cache is read, not refetched"

out=$(run_case '
    export PATH="$PRICE_ENV/bin:$PATH"
    export XDG_CACHE_HOME="$PRICE_CACHE"
    mkdir -p "$XDG_CACHE_HOME/dms-ai-usage"
    printf "%s" "{\"updated\": \"2000-01-01\", \"models\": {\"zai/glm-5.3\": {\"input\": 1.4e-6, \"output\": 4.4e-6, \"cache_read\": 1.4e-6, \"cache_write\": 0}}}" \
        > "$XDG_CACHE_HOME/dms-ai-usage/pricing.json"
    load_pricing
    printf "awk=%s\n" "$PRICING_AWK"
    printf "rate=%s\n" "$USD_EUR_RATE"
    printf "updated=%s\n" "$(jq -r .updated "$XDG_CACHE_HOME/dms-ai-usage/pricing.json")"
')
assert_eq "$(printf '%s' "$out" | sed -n 's/^updated=//p')" "$TODAY" \
    "a stale cache is refreshed"
assert_eq "$(printf '%s' "$out" | sed -n 's/^rate=//p')" "0.93" \
    "the refreshed cache carries the current EUR rate"

out=$(run_case '
    export PATH="$PRICE_ENV/bin:$PATH"
    export XDG_CACHE_HOME="$PRICE_CACHE"
    mkdir -p "$XDG_CACHE_HOME/dms-ai-usage"
    printf "%s" "{\"updated\": \"2000-01-01\", \"models\": {\"zai/glm-5.3\": {\"input\": 1.4e-6, \"output\": 4.4e-6, \"cache_read\": 1.4e-6, \"cache_write\": 0}}}" \
        > "$XDG_CACHE_HOME/dms-ai-usage/pricing.json"
    PRICE_FIXTURE="$PRICE_ENV/absent.json" load_pricing
    printf "awk=%s\n" "$PRICING_AWK"
    printf "updated=%s\n" "$(jq -r .updated "$XDG_CACHE_HOME/dms-ai-usage/pricing.json")"
')
assert_eq "$(printf '%s' "$out" | sed -n 's/^updated=//p')" "2000-01-01" \
    "a refresh that fails keeps yesterday's cache"
assert_match "$(printf '%s' "$out" | sed -n 's/^awk=//p')" 'zai/glm-5.3:' \
    "a failed refresh still prices from what it has"

# An empty table prices nothing and writes no cache. The cache the cases
# above left is removed first, so this one starts from nothing.
rm -rf "$PRICE_CACHE"
cat > "$PRICE_ENV/empty.json" << 'EOF'
{}
EOF
out=$(run_case '
    export PATH="$PRICE_ENV/bin:$PATH"
    export XDG_CACHE_HOME="$PRICE_CACHE"
    PRICE_FIXTURE="$PRICE_ENV/empty.json" load_pricing
    printf "awk=[%s]\n" "$PRICING_AWK"
    printf "rate=%s\n" "$USD_EUR_RATE"
    printf "file=%s\n" "$(test -f "$XDG_CACHE_HOME/dms-ai-usage/pricing.json" && echo yes || echo no)"
')
assert_eq "$(printf '%s' "$out" | sed -n 's/^awk=//p')" "[]" \
    "a table with nothing priced leaves the awk string empty"
assert_eq "$(printf '%s' "$out" | sed -n 's/^rate=//p')" "0" \
    "no EUR rate answered leaves USD_EUR_RATE at 0"
assert_eq "$(printf '%s' "$out" | sed -n 's/^file=//p')" "no" \
    "a table with nothing priced writes no cache"

out=$(run_case '
    export PATH="$PRICE_ENV/bin:$PATH"
    export XDG_CACHE_HOME="$PRICE_CACHE"
    PRICE_EUR_FILE="$PRICE_ENV/no-eur.json" load_pricing
    printf "rate=%s\n" "$USD_EUR_RATE"
')
assert_eq "$(printf '%s' "$out" | sed -n 's/^rate=//p')" "0" \
    "a Frankfurter answer without a rate leaves USD_EUR_RATE at 0"

echo
echo "Passed: $PASS, Failed: $FAIL"
[ "$FAIL" -eq 0 ]
