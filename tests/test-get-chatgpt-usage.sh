#!/usr/bin/env bash
# Tests for get-chatgpt-usage script
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/get-chatgpt-usage"
PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1" >&2; }
assert_eq() {
    if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (expected '$2', got '$1')"; fi
}
assert_match() {
    if echo "$1" | grep -qE "$2"; then pass "$3"; else fail "$3 (no match for '$2')"; fi
}
assert_no_match() {
    if echo "$1" | grep -qE "$2"; then fail "$3 (unexpected match for '$2')"; else pass "$3"; fi
}

# --- Setup isolated environment ---
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

setup_env() {
    local name="$1"
    local dir="$TMPDIR_ROOT/$name"
    mkdir -p "$dir/.codex/sessions"
    echo "$dir"
}

# A fake, unsigned JWT whose payload decodes to the given `exp` claim —
# enough for the script's jwt_exp() (it never checks the signature).
fake_jwt() {
    local exp="$1"
    local payload
    payload=$(printf '{"exp":%d}' "$exp" | base64 -w0 | tr '+/' '-_' | tr -d '=')
    echo "header.${payload}.signature"
}

write_auth() {
    local dir="$1" exp="$2" last_refresh="$3" account_id="${4:-acct-1}"
    mkdir -p "$dir"
    cat > "$dir/auth.json" << AUTHEOF
{
    "tokens": {"access_token": "$(fake_jwt "$exp")", "account_id": "$account_id"},
    "last_refresh": "$last_refresh"
}
AUTHEOF
}

# Mock curl: always returns a full rate_limit response (avoids real network
# calls; a per-test PATH override can shadow this with a different mock).
mock_curl="$TMPDIR_ROOT/curl"
cat > "$mock_curl" << 'CURLEOF'
#!/usr/bin/env bash
cat << 'JSONEOF'
{
    "plan_type": "plus",
    "rate_limit": {
        "primary_window": {"used_percent": 42, "reset_at": "2099-01-01T00:00:00Z", "limit_window_seconds": 18000},
        "secondary_window": {"used_percent": 15, "reset_at": "2099-01-07T00:00:00Z", "limit_window_seconds": 604800}
    },
    "credits": {"balance": 5, "has_credits": true}
}
JSONEOF
CURLEOF
chmod +x "$mock_curl"

run_script() {
    local home_dir="$1"
    shift
    # Widen PATH with the mock curl but keep a fake `codex` present too, so
    # the not_installed short-circuit doesn't fire in the common case.
    # The pricing cache the Script reads lives under XDG_CACHE_HOME, so that
    # is pinned inside the test environment as well: a developer's real cache
    # must not price a fixture, and a fixture must not write into it.
    HOME="$home_dir" CODEX_HOME="$home_dir/.codex" XDG_CACHE_HOME="$home_dir/.cache" \
        PATH="$TMPDIR_ROOT:$PATH" bash "$SCRIPT" "$@" 2>/dev/null
}

# Fake `codex` binary — only its presence on PATH is checked by most tests;
# the stale-refresh path (`codex login status`) is a no-op here.
mock_codex="$TMPDIR_ROOT/codex"
cat > "$mock_codex" << 'CODEXEOF'
#!/usr/bin/env bash
exit 0
CODEXEOF
chmod +x "$mock_codex"

# Build a rollout fixture: one turn_context line (a "message") followed by
# one token_count line carrying that turn's token delta.
# Usage: append_turn <file> <date> <model> <tokens>
append_turn() {
    local file="$1" date="$2" model="$3" tokens="$4"
    printf '{"type":"turn_context","timestamp":"%sT12:00:00Z","payload":{"model":"%s"}}\n' "$date" "$model" >> "$file"
    printf '{"type":"event_msg","timestamp":"%sT12:00:01Z","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":%d}}}}\n' "$date" "$tokens" >> "$file"
}

# The same, with the four-way token split the costing consumes. Codex's
# total_tokens counts input plus output, the cached share inside the input.
# Usage: append_priced_turn <file> <date> <model> <input> <cached> <output>
append_priced_turn() {
    local file="$1" date="$2" model="$3" inp="$4" cached="$5" out="$6"
    printf '{"type":"turn_context","timestamp":"%sT12:00:00Z","payload":{"model":"%s"}}\n' "$date" "$model" >> "$file"
    printf '{"type":"event_msg","timestamp":"%sT12:00:01Z","payload":{"type":"token_count","info":{"last_token_usage":{"total_tokens":%d,"input_tokens":%d,"cached_input_tokens":%d,"output_tokens":%d}}}}\n' \
        "$date" "$((inp + out))" "$inp" "$cached" "$out" >> "$file"
}

# Write the shared pricing cache the way the library's refresh would, under
# the test environment's own XDG cache directory.
# Usage: write_pricing_cache <home_dir> <models-json> [usd_eur_rate]
write_pricing_cache() {
    local home_dir="$1" models="$2" rate="${3:-0}"
    mkdir -p "$home_dir/.cache/dms-ai-usage"
    printf '{"updated": "%s", "models": %s, "usd_eur_rate": %s}' \
        "$TODAY" "$models" "$rate" > "$home_dir/.cache/dms-ai-usage/pricing.json"
}

TODAY=$(date +%Y-%m-%d)
DOW=$(date +%u)  # 1=Monday, 7=Sunday

# ============================================================
echo "=== Test 1: Output format — all keys present ==="
# ============================================================
ENV1=$(setup_env "test1")
write_auth "$ENV1/.codex" 9999999999 "$(date -Iseconds)"
OUTPUT1=$(run_script "$ENV1")

EXPECTED_KEYS="PLAN_TYPE PRIMARY_UTIL PRIMARY_RESET PRIMARY_WINDOW_SECONDS SECONDARY_UTIL SECONDARY_RESET SECONDARY_WINDOW_SECONDS CREDITS_BALANCE CREDITS_HAS CREDS_STATUS WEEK_TOKENS WEEK_MESSAGES WEEK_SESSIONS MONTH_TOKENS DAILY WEEK_MODELS TODAY_COST WEEK_COST MONTH_COST DAILY_COSTS USD_EUR_RATE ACCOUNTS ACCOUNT_SUBSCRIPTION ACCOUNT_PRIMARY_UTIL ACCOUNT_PRIMARY_RESET ACCOUNT_SECONDARY_UTIL ACCOUNT_SECONDARY_RESET ACCOUNT_CREDS_STATUS ACCOUNT_WEEK_TOKENS ACCOUNT_MONTH_TOKENS ACCOUNT_WEEK_MESSAGES ACCOUNT_WEEK_SESSIONS ACCOUNT_DAILY ACCOUNT_WEEK_MODELS ACCOUNT_TODAY_COST ACCOUNT_WEEK_COST ACCOUNT_MONTH_COST ACCOUNT_DAILY_COSTS"
for key in $EXPECTED_KEYS; do
    if echo "$OUTPUT1" | grep -q "^${key}="; then
        pass "key $key present"
    else
        fail "key $key missing"
    fi
done

# ChatGPT is not Claude, so its per-Account keys use the ACCOUNT_ prefix that
# CONTEXT.md's Account term implies. ACCOUNTS is the Source-level list and
# stays; no PROFILE_ key may leak out of a non-Claude Source.
assert_match "$OUTPUT1" "^ACCOUNT_PRIMARY_UTIL=" "the per-Account keys use the ACCOUNT_ prefix"
assert_match "$OUTPUT1" "^ACCOUNTS=" "the Source-level ACCOUNTS key stays"
assert_no_match "$OUTPUT1" "^PROFILE_" "a non-Claude Source emits no PROFILE_ keys"

# ============================================================
echo "=== Test 2: Fresh credentials — rate_limit fields from the API ==="
# ============================================================
PLAN1=$(echo "$OUTPUT1" | grep "^PLAN_TYPE=" | cut -d= -f2)
assert_eq "$PLAN1" "plus" "PLAN_TYPE from API"
PU1=$(echo "$OUTPUT1" | grep "^PRIMARY_UTIL=" | cut -d= -f2)
assert_eq "$PU1" "42" "PRIMARY_UTIL from API"
PW1=$(echo "$OUTPUT1" | grep "^PRIMARY_WINDOW_SECONDS=" | cut -d= -f2)
assert_eq "$PW1" "18000" "PRIMARY_WINDOW_SECONDS from API (real window length, not assumed)"
SW1=$(echo "$OUTPUT1" | grep "^SECONDARY_WINDOW_SECONDS=" | cut -d= -f2)
assert_eq "$SW1" "604800" "SECONDARY_WINDOW_SECONDS from API"
CS1=$(echo "$OUTPUT1" | grep "^CREDS_STATUS=" | cut -d= -f2)
assert_eq "$CS1" "ok" "CREDS_STATUS=ok with valid token and a rate_limit response"

# ============================================================
echo "=== Test 3: Missing auth.json — defaults, CREDS_STATUS=missing ==="
# ============================================================
ENV3=$(setup_env "test3")
OUTPUT3=$(run_script "$ENV3")

CS3=$(echo "$OUTPUT3" | grep "^CREDS_STATUS=" | cut -d= -f2)
assert_eq "$CS3" "missing" "CREDS_STATUS=missing without auth.json"
PU3=$(echo "$OUTPUT3" | grep "^PRIMARY_UTIL=" | cut -d= -f2)
assert_eq "$PU3" "0" "PRIMARY_UTIL=0 without auth.json"
PLAN3=$(echo "$OUTPUT3" | grep "^PLAN_TYPE=" | cut -d= -f2)
assert_eq "$PLAN3" "unknown" "PLAN_TYPE=unknown without auth.json"

# ============================================================
echo "=== Test 4: API response without rate_limit — CREDS_STATUS=expired ==="
# ============================================================
ENV4=$(setup_env "test4")
write_auth "$ENV4/.codex" 9999999999 "$(date -Iseconds)"

empty_curl="$TMPDIR_ROOT/test4/curl"
mkdir -p "$TMPDIR_ROOT/test4"
cat > "$empty_curl" << 'EMPTYEOF'
#!/usr/bin/env bash
echo '{}'
EMPTYEOF
chmod +x "$empty_curl"

OUTPUT4=$(HOME="$ENV4" CODEX_HOME="$ENV4/.codex" PATH="$TMPDIR_ROOT/test4:$TMPDIR_ROOT:$PATH" bash "$SCRIPT" 2>/dev/null)
CS4=$(echo "$OUTPUT4" | grep "^CREDS_STATUS=" | cut -d= -f2)
assert_eq "$CS4" "expired" "CREDS_STATUS=expired when the API call succeeds but carries no rate_limit"

# ============================================================
echo "=== Test 5: codex binary absent and no auth.json — not_installed ==="
# ============================================================
# A minimal PATH with only the standard tools the script itself needs
# (jq/curl/date/etc, all under /usr/bin here) and no real `codex` binary —
# the ambient $PATH can't be reused as-is since it may have a real `codex`
# installed somewhere the script's own PATH-widening also searches.
NOCODEX_PATH="/usr/bin:/bin"

ENV5=$(setup_env "test5")
OUTPUT5=$(HOME="$ENV5" CODEX_HOME="$ENV5/.codex" PATH="$NOCODEX_PATH" bash "$SCRIPT" 2>/dev/null)
CS5=$(echo "$OUTPUT5" | grep "^CREDS_STATUS=" | cut -d= -f2)
assert_eq "$CS5" "not_installed" "CREDS_STATUS=not_installed when codex isn't on PATH and no auth.json exists"

# An existing auth.json is treated as proof of installation even off PATH
ENV5B=$(setup_env "test5b")
write_auth "$ENV5B/.codex" 9999999999 "$(date -Iseconds)"
OUTPUT5B=$(HOME="$ENV5B" CODEX_HOME="$ENV5B/.codex" PATH="$NOCODEX_PATH:$TMPDIR_ROOT" bash "$SCRIPT" 2>/dev/null)
CS5B=$(echo "$OUTPUT5B" | grep "^CREDS_STATUS=" | cut -d= -f2)
if [ "$CS5B" != "not_installed" ]; then
    pass "auth.json presence overrides not_installed even with codex off PATH"
else
    fail "auth.json presence should override not_installed (got not_installed)"
fi

# ============================================================
echo "=== Test 6: Token/message aggregation from rollout session files ==="
# ============================================================
ENV6=$(setup_env "test6")

if [ "$DOW" -eq 1 ]; then
    OTHER_DAY=$(date -d "1 day" +%Y-%m-%d)
    OTHER_IDX=1
else
    OTHER_DAY=$(date -d "1 day ago" +%Y-%m-%d)
    OTHER_IDX=$((DOW - 2))
fi
TODAY_IDX=$((DOW - 1))

append_turn "$ENV6/.codex/sessions/a.jsonl" "$TODAY" "gpt-5-codex" 100
append_turn "$ENV6/.codex/sessions/a.jsonl" "$TODAY" "gpt-5-codex" 150
append_turn "$ENV6/.codex/sessions/b.jsonl" "$OTHER_DAY" "gpt-5-codex" 80

OUTPUT6=$(run_script "$ENV6")

WEEK_TOKENS6=$(echo "$OUTPUT6" | grep "^WEEK_TOKENS=" | cut -d= -f2)
assert_eq "$WEEK_TOKENS6" "330" "WEEK_TOKENS sums token_count deltas across sessions"
WEEK_MESSAGES6=$(echo "$OUTPUT6" | grep "^WEEK_MESSAGES=" | cut -d= -f2)
assert_eq "$WEEK_MESSAGES6" "3" "WEEK_MESSAGES counts turn_context events"
WEEK_SESSIONS6=$(echo "$OUTPUT6" | grep "^WEEK_SESSIONS=" | cut -d= -f2)
assert_eq "$WEEK_SESSIONS6" "2" "WEEK_SESSIONS counts distinct rollout files"
WEEK_MODELS6=$(echo "$OUTPUT6" | grep "^WEEK_MODELS=" | cut -d= -f2-)
assert_match "$WEEK_MODELS6" "gpt-5-codex=330" "WEEK_MODELS attributes tokens to the active model"

DAILY6=$(echo "$OUTPUT6" | grep "^DAILY=" | cut -d= -f2)
DAILY_TODAY6=$(echo "$DAILY6" | tr ',' '\n' | sed -n "$((TODAY_IDX + 1))p")
DAILY_OTHER6=$(echo "$DAILY6" | tr ',' '\n' | sed -n "$((OTHER_IDX + 1))p")
assert_eq "$DAILY_TODAY6" "250" "DAILY today=250"
assert_eq "$DAILY_OTHER6" "80" "DAILY other day=80"

# ============================================================
echo "=== Test 7: Empty sessions dir — all counters zero ==="
# ============================================================
ENV7=$(setup_env "test7")
OUTPUT7=$(run_script "$ENV7")

assert_eq "$(echo "$OUTPUT7" | grep "^WEEK_TOKENS=" | cut -d= -f2)" "0" "WEEK_TOKENS=0 empty"
assert_eq "$(echo "$OUTPUT7" | grep "^WEEK_MESSAGES=" | cut -d= -f2)" "0" "WEEK_MESSAGES=0 empty"
assert_eq "$(echo "$OUTPUT7" | grep "^WEEK_SESSIONS=" | cut -d= -f2)" "0" "WEEK_SESSIONS=0 empty"
assert_eq "$(echo "$OUTPUT7" | grep "^DAILY=" | cut -d= -f2)" "0,0,0,0,0,0,0" "DAILY all zeros"

# ============================================================
echo "=== Test 8: Malformed rollout lines are skipped ==="
# ============================================================
ENV8=$(setup_env "test8")
{
    echo "this is not json"
    echo ""
    echo '{"truncated": true'
} > "$ENV8/.codex/sessions/c.jsonl"
append_turn "$ENV8/.codex/sessions/c.jsonl" "$TODAY" "gpt-5-codex" 200
echo '{"type":"turn_context","timestamp":"invalid"}' >> "$ENV8/.codex/sessions/c.jsonl"

OUTPUT8=$(run_script "$ENV8")
WEEK_TOKENS8=$(echo "$OUTPUT8" | grep "^WEEK_TOKENS=" | cut -d= -f2)
assert_eq "$WEEK_TOKENS8" "200" "Malformed lines skipped, valid turn counted"

# ============================================================
echo "=== Test 9: Week boundary — previous week excluded from WEEK_TOKENS ==="
# ============================================================
ENV9=$(setup_env "test9")
LAST_SUNDAY=$(date -d "last Sunday" +%Y-%m-%d)
if [ "$(date +%u)" -eq 7 ]; then
    LAST_SUNDAY=$(date -d "7 days ago" +%Y-%m-%d)
fi

append_turn "$ENV9/.codex/sessions/w1.jsonl" "$TODAY" "gpt-5-codex" 100
append_turn "$ENV9/.codex/sessions/w2.jsonl" "$LAST_SUNDAY" "gpt-5-codex" 500

OUTPUT9=$(run_script "$ENV9")
WEEK_TOKENS9=$(echo "$OUTPUT9" | grep "^WEEK_TOKENS=" | cut -d= -f2)
assert_eq "$WEEK_TOKENS9" "100" "Previous week data excluded from WEEK_TOKENS"

# ============================================================
echo "=== Test 10: Month boundary — previous month excluded from MONTH_TOKENS ==="
# ============================================================
ENV10=$(setup_env "test10")
PREV_MONTH_DATE=$(date -d "$(date +%Y-%m-01) - 1 day" +%Y-%m-%d)

append_turn "$ENV10/.codex/sessions/m1.jsonl" "$TODAY" "gpt-5-codex" 100
append_turn "$ENV10/.codex/sessions/m2.jsonl" "$PREV_MONTH_DATE" "gpt-5-codex" 400

OUTPUT10=$(run_script "$ENV10")
MONTH_TOKENS10=$(echo "$OUTPUT10" | grep "^MONTH_TOKENS=" | cut -d= -f2)
assert_eq "$MONTH_TOKENS10" "100" "Previous month data excluded from MONTH_TOKENS"

# ============================================================
echo "=== Test 11: ACCOUNTS field — default account always present ==="
# ============================================================
ENV11=$(setup_env "test11")
OUTPUT11=$(run_script "$ENV11")

ACCOUNTS11=$(echo "$OUTPUT11" | grep "^ACCOUNTS=" | cut -d= -f2)
assert_match "$ACCOUNTS11" "default" "ACCOUNTS contains default"

# ============================================================
echo "=== Test 12: Manual accounts passed as name=path arguments ==="
# ============================================================
ENV12=$(setup_env "test12")
mkdir -p "$ENV12/manual/work/sessions"
write_auth "$ENV12/manual/work" 9999999999 "$(date -Iseconds)"
append_turn "$ENV12/manual/work/sessions/t.jsonl" "$TODAY" "gpt-5-codex" 100

OUTPUT12=$(run_script "$ENV12" "work=$ENV12/manual/work")
ACCOUNTS12=$(echo "$OUTPUT12" | grep "^ACCOUNTS=" | cut -d= -f2)
assert_match "$ACCOUNTS12" "work" "manual account appears in ACCOUNTS"

# Tokens from the manual account are included in the aggregate total
WEEK_TOKENS12=$(echo "$OUTPUT12" | grep "^WEEK_TOKENS=" | cut -d= -f2)
assert_eq "$WEEK_TOKENS12" "100" "manual account tokens counted in aggregate WEEK_TOKENS"

# ============================================================
echo "=== Test 13: duplicate account names/dirs registered once ==="
# ============================================================
ENV13=$(setup_env "test13")
mkdir -p "$ENV13/other"

# "default" is already registered; a manual entry reusing the name is ignored
OUTPUT13=$(run_script "$ENV13" "default=$ENV13/other")
ACCOUNTS13=$(echo "$OUTPUT13" | grep "^ACCOUNTS=" | cut -d= -f2)
DEFAULT_COUNT13=$(echo "$ACCOUNTS13" | tr ',' '\n' | grep -c '^default$')
assert_eq "$DEFAULT_COUNT13" "1" "duplicate account name registered only once"

# The same codex home dir under another name must not be counted twice
OUTPUT13B=$(run_script "$ENV13" "alias=$ENV13/.codex")
ACCOUNTS13B=$(echo "$OUTPUT13B" | grep "^ACCOUNTS=" | cut -d= -f2)
if echo "$ACCOUNTS13B" | tr ',' '\n' | grep -q '^alias$'; then
    fail "duplicate codex home dir registered under another name"
else
    pass "duplicate codex home dir registered only once"
fi

# ============================================================
echo "=== Test 14: Per-Account readings the Popout overlays ==="
# ============================================================
# Two Accounts with different credentials and different local token counts, so
# each ACCOUNT_* list has something to tell them apart by.
multi_curl_dir="$TMPDIR_ROOT/test14"
mkdir -p "$multi_curl_dir"
cat > "$multi_curl_dir/curl" << 'CURLEOF'
#!/usr/bin/env bash
acct=""
for a in "$@"; do
    case "$a" in
        ChatGPT-Account-Id:*) acct="${a#ChatGPT-Account-Id: }" ;;
    esac
done
case "$acct" in
    acct-work) plan=pro primary=7 primary_reset="2099-02-01T00:00:00Z" secondary=3 secondary_reset="2099-02-07T00:00:00Z" ;;
    *) plan=plus primary=42 primary_reset="2099-01-01T00:00:00Z" secondary=15 secondary_reset="2099-01-07T00:00:00Z" ;;
esac
cat << JSONEOF
{
    "plan_type": "$plan",
    "rate_limit": {
        "primary_window": {"used_percent": $primary, "reset_at": "$primary_reset", "limit_window_seconds": 18000},
        "secondary_window": {"used_percent": $secondary, "reset_at": "$secondary_reset", "limit_window_seconds": 604800}
    },
    "credits": {"balance": 5, "has_credits": true}
}
JSONEOF
CURLEOF
chmod +x "$multi_curl_dir/curl"

ENV14=$(setup_env "test14")
write_auth "$ENV14/.codex" 9999999999 "$(date -Iseconds)"
mkdir -p "$ENV14/work/sessions"
write_auth "$ENV14/work" 9999999999 "$(date -Iseconds)" acct-work
append_turn "$ENV14/.codex/sessions/a.jsonl" "$TODAY" "gpt-5-codex" 100
append_turn "$ENV14/work/sessions/b.jsonl" "$TODAY" "gpt-5-codex" 300

OUTPUT14=$(HOME="$ENV14" CODEX_HOME="$ENV14/.codex" PATH="$multi_curl_dir:$TMPDIR_ROOT:$PATH" bash "$SCRIPT" "work=$ENV14/work" 2>/dev/null)

assert_eq "$(echo "$OUTPUT14" | grep "^ACCOUNTS=" | cut -d= -f2)" "default,work" "ACCOUNTS lists both Accounts"
assert_eq "$(echo "$OUTPUT14" | grep "^ACCOUNT_SUBSCRIPTION=" | cut -d= -f2)" "default:plus,work:pro" "ACCOUNT_SUBSCRIPTION carries each Account's plan"
assert_eq "$(echo "$OUTPUT14" | grep "^ACCOUNT_CREDS_STATUS=" | cut -d= -f2)" "default:ok,work:ok" "ACCOUNT_CREDS_STATUS carries each Account's own status"
# The per-Account keys are named for ChatGPT's own Windows: primary and
# secondary, whose lengths the API reports.
assert_eq "$(echo "$OUTPUT14" | grep "^ACCOUNT_PRIMARY_UTIL=" | cut -d= -f2)" "default:42,work:7" "ACCOUNT_PRIMARY_UTIL carries each Account's primary Window"
assert_eq "$(echo "$OUTPUT14" | grep "^ACCOUNT_PRIMARY_RESET=" | cut -d= -f2)" "default:2099-01-01T00:00:00Z,work:2099-02-01T00:00:00Z" "ACCOUNT_PRIMARY_RESET carries each Account's primary reset"
assert_eq "$(echo "$OUTPUT14" | grep "^ACCOUNT_SECONDARY_UTIL=" | cut -d= -f2)" "default:15,work:3" "ACCOUNT_SECONDARY_UTIL carries each Account's secondary Window"
assert_eq "$(echo "$OUTPUT14" | grep "^ACCOUNT_SECONDARY_RESET=" | cut -d= -f2)" "default:2099-01-07T00:00:00Z,work:2099-02-07T00:00:00Z" "ACCOUNT_SECONDARY_RESET carries each Account's secondary reset"
assert_no_match "$OUTPUT14" "^PROFILE_" "no PROFILE_ key leaks out of a non-Claude Source"
assert_eq "$(echo "$OUTPUT14" | grep "^ACCOUNT_WEEK_TOKENS=" | cut -d= -f2)" "default:100,work:300" "ACCOUNT_WEEK_TOKENS carries each Account's own weekly tokens"
assert_eq "$(echo "$OUTPUT14" | grep "^ACCOUNT_MONTH_TOKENS=" | cut -d= -f2)" "default:100,work:300" "ACCOUNT_MONTH_TOKENS carries each Account's own monthly tokens"
assert_eq "$(echo "$OUTPUT14" | grep "^ACCOUNT_WEEK_MESSAGES=" | cut -d= -f2)" "default:1,work:1" "ACCOUNT_WEEK_MESSAGES carries each Account's own message count"
assert_eq "$(echo "$OUTPUT14" | grep "^ACCOUNT_WEEK_SESSIONS=" | cut -d= -f2)" "default:1,work:1" "ACCOUNT_WEEK_SESSIONS carries each Account's own session count"
assert_eq "$(echo "$OUTPUT14" | grep "^ACCOUNT_WEEK_MODELS=" | cut -d= -f2-)" "default:gpt-5-codex=100|work:gpt-5-codex=300" "ACCOUNT_WEEK_MODELS carries each Account's own model breakdown"

ACCOUNT_DAILY14=$(echo "$OUTPUT14" | grep "^ACCOUNT_DAILY=" | cut -d= -f2-)
DEFAULT_DAILY14=$(echo "$ACCOUNT_DAILY14" | tr '|' '\n' | grep '^default:' | cut -d: -f2-)
WORK_DAILY14=$(echo "$ACCOUNT_DAILY14" | tr '|' '\n' | grep '^work:' | cut -d: -f2-)
assert_eq "$(echo "$DEFAULT_DAILY14" | tr ',' '\n' | sed -n "$((TODAY_IDX + 1))p")" "100" "ACCOUNT_DAILY carries the default Account's own daily series"
assert_eq "$(echo "$WORK_DAILY14" | tr ',' '\n' | sed -n "$((TODAY_IDX + 1))p")" "300" "ACCOUNT_DAILY carries the work Account's own daily series"

# ============================================================
echo "=== Test 15: An Account with rejected credentials stays visible ==="
# ============================================================
# The work Account has no auth.json, so its credentials are missing. Its own
# reading must still appear beside the healthy default's rather than vanish.
ENV15=$(setup_env "test15")
write_auth "$ENV15/.codex" 9999999999 "$(date -Iseconds)"
mkdir -p "$ENV15/work/sessions"

OUTPUT15=$(run_script "$ENV15" "work=$ENV15/work")

assert_eq "$(echo "$OUTPUT15" | grep "^ACCOUNTS=" | cut -d= -f2)" "default,work" "a rejected Account stays listed in ACCOUNTS"
assert_eq "$(echo "$OUTPUT15" | grep "^ACCOUNT_CREDS_STATUS=" | cut -d= -f2)" "default:ok,work:missing" "the Account whose credentials were rejected is reported as missing beside the healthy one"
assert_eq "$(echo "$OUTPUT15" | grep "^ACCOUNT_PRIMARY_UTIL=" | cut -d= -f2)" "default:42,work:0" "the rejected Account's own primary Window is reported, not masked by the healthy Account's"
assert_eq "$(echo "$OUTPUT15" | grep "^ACCOUNT_SECONDARY_UTIL=" | cut -d= -f2)" "default:15,work:0" "the rejected Account's own secondary Window is reported, not masked by the healthy Account's"

# ============================================================
echo "=== Test 16: Listing mode reports every Account and where it came from ==="
# ============================================================
# The settings page asks the same Script the Popout asks, so the Accounts it
# lists can never disagree with the selector. --list-accounts returns the list
# and its origins without fetching anything, so opening the settings page
# costs no request.
ENV16=$(setup_env "test16")
write_auth "$ENV16/.codex" 9999999999 "$(date -Iseconds)"

# run_script sets CODEX_HOME, so that variable is what placed the directory.
LIST16=$(run_script "$ENV16" --list-accounts)
assert_eq "$(echo "$LIST16" | grep "^ACCOUNTS=" | cut -d= -f2)" "default" "listing mode lists the detected Account"
assert_eq "$(echo "$LIST16" | grep "^ACCOUNT_ORIGINS=" | cut -d= -f2)" "default:CODEX_HOME" "listing mode names CODEX_HOME as the origin when it decided the directory"
assert_eq "$(echo "$LIST16" | wc -l)" "3" "listing mode returns the Account, origin and refused lists and nothing else"

LIST16B=$(HOME="$ENV16" CODEX_HOME='' PATH="$TMPDIR_ROOT:$PATH" bash "$SCRIPT" --list-accounts 2>/dev/null)
assert_eq "$(echo "$LIST16B" | grep "^ACCOUNT_ORIGINS=" | cut -d= -f2)" "default:~/.codex" "listing mode names the conventional path when no CODEX_HOME is set"

# A Custom Account is reported as coming from the Custom Account list. It cannot
# take the name "default", which the Codex home already holds, so both are
# reported and the origin says which one the selector shows.
LIST16C=$(run_script "$ENV16" --list-accounts "work=$ENV16/work")
assert_eq "$(echo "$LIST16C" | grep "^ACCOUNTS=" | cut -d= -f2)" "default,work" "listing mode lists Custom Accounts beside detected ones"
assert_eq "$(echo "$LIST16C" | grep "^ACCOUNT_ORIGINS=" | cut -d= -f2)" "default:CODEX_HOME,work:custom" "listing mode reports Custom and detected origins side by side"
assert_eq "$(echo "$LIST16C" | grep "^ACCOUNT_SHADOWED=" | cut -d= -f2)" "" "no registration is refused when the names differ"

# Here detection runs first, so a Custom Account that takes the Codex home's name
# is the one refused. It is still reported, with the origin it came from, so the
# settings page can mark the row the selector does not offer.
LIST16E=$(run_script "$ENV16" --list-accounts "default=$ENV16/elsewhere")
assert_eq "$(echo "$LIST16E" | grep "^ACCOUNTS=" | cut -d= -f2)" "default" "the detected Account keeps the name"
assert_eq "$(echo "$LIST16E" | grep "^ACCOUNT_SHADOWED=" | cut -d= -f2)" "default|default:custom" "the refused Custom registration is reported with its origin"

# Without codex, the not-installed answer is what the listing mode returns, so it
# carries the origins key too: a Source the Script cannot read Accounts for must
# not look like one it read and found empty.
ENV16D=$(setup_env "test16d")
LIST16D=$(HOME="$ENV16D" CODEX_HOME="$ENV16D/.codex" PATH="$NOCODEX_PATH" bash "$SCRIPT" --list-accounts 2>/dev/null)
assert_eq "$(echo "$LIST16D" | grep "^ACCOUNTS=" | cut -d= -f2)" "" "an uninstalled Source lists no Account"
assert_eq "$(echo "$LIST16D" | grep -c "^ACCOUNTS=")" "1" "an uninstalled Source still answers with the Account key"
assert_eq "$(echo "$LIST16D" | grep "^ACCOUNT_ORIGINS=" | cut -d= -f2)" "" "an uninstalled Source answers with an empty origins key"
assert_eq "$(echo "$LIST16D" | grep -c "^ACCOUNT_ORIGINS=")" "1" "an uninstalled Source still answers with the origins key"
assert_eq "$(echo "$LIST16D" | grep "^CREDS_STATUS=" | cut -d= -f2)" "not_installed" "an uninstalled Source says so in its listing answer"

# ============================================================
echo "=== Test 17: Cost — the four-way split, from the pricing cache ==="
# ============================================================
# Rates chosen so each bucket of the split lands on its own cent: a turn
# today with input 20000 (half cached) and output 10000 prices as
#   (20000−10000)·1e-05 + 10000·1e-06 + 10000·1e-04 = 0.10 + 0.01 + 1.00
# Charging the cached share at the input rate reads 1.20; charging it as free
# reads 1.10. Only the right split reads 1.11.
ENV17=$(setup_env "test17")
write_auth "$ENV17/.codex" 9999999999 "$(date -Iseconds)"
write_pricing_cache "$ENV17" \
    '{"gpt-5.1": {"input": 1e-05, "output": 1e-04, "cache_read": 1e-06, "cache_write": 0}}' 0.9

append_priced_turn "$ENV17/.codex/sessions/a.jsonl" "$TODAY" "gpt-5.1" 20000 10000 10000
append_priced_turn "$ENV17/.codex/sessions/a.jsonl" "$OTHER_DAY" "gpt-5.1" 1000 0 0

OUTPUT17=$(run_script "$ENV17")

assert_eq "$(echo "$OUTPUT17" | grep '^TODAY_COST=' | cut -d= -f2)" "1.11" \
    "TODAY_COST prices cached input at the cache-read rate, not the input rate"
assert_eq "$(echo "$OUTPUT17" | grep '^WEEK_COST=' | cut -d= -f2)" "1.12" \
    "WEEK_COST sums the week's turns across days"
assert_eq "$(echo "$OUTPUT17" | grep '^MONTH_COST=' | cut -d= -f2)" "1.12" \
    "MONTH_COST sums the month's turns"
DAILY_COSTS17=$(echo "$OUTPUT17" | grep '^DAILY_COSTS=' | cut -d= -f2)
assert_eq "$(echo "$DAILY_COSTS17" | tr ',' '\n' | sed -n "$((TODAY_IDX + 1))p")" "1.11" \
    "DAILY_COSTS carries today's cost in today's slot"
assert_eq "$(echo "$DAILY_COSTS17" | tr ',' '\n' | sed -n "$((OTHER_IDX + 1))p")" "0.01" \
    "DAILY_COSTS carries the other day's cost in its own slot"
assert_eq "$(echo "$OUTPUT17" | grep '^USD_EUR_RATE=' | cut -d= -f2)" "0.9" \
    "USD_EUR_RATE rides the same cache"
WEEK_TOKENS17=$(echo "$OUTPUT17" | grep '^WEEK_TOKENS=' | cut -d= -f2)
assert_eq "$WEEK_TOKENS17" "31000" \
    "costing leaves the token counts alone (total stays input + output)"

assert_eq "$(echo "$OUTPUT17" | grep '^ACCOUNT_TODAY_COST=' | cut -d= -f2)" "default:1.11" \
    "ACCOUNT_TODAY_COST carries the per-Account figure"
assert_eq "$(echo "$OUTPUT17" | grep '^ACCOUNT_WEEK_COST=' | cut -d= -f2)" "default:1.12" \
    "ACCOUNT_WEEK_COST carries the per-Account figure"
assert_eq "$(echo "$OUTPUT17" | grep '^ACCOUNT_MONTH_COST=' | cut -d= -f2)" "default:1.12" \
    "ACCOUNT_MONTH_COST carries the per-Account figure"
# The per-Account daily-cost series is asserted slot by slot: today is not
# the week's first day in general, so a prefix match would only pass on Monday.
ACCOUNT_DAILY_COSTS17=$(echo "$OUTPUT17" | grep '^ACCOUNT_DAILY_COSTS=' | cut -d= -f2)
assert_eq "$(echo "${ACCOUNT_DAILY_COSTS17#default:}" | tr ',' '\n' | sed -n "$((TODAY_IDX + 1))p")" "1.11" \
    "ACCOUNT_DAILY_COSTS carries the per-Account series"
assert_eq "$(echo "${ACCOUNT_DAILY_COSTS17#default:}" | tr ',' '\n' | sed -n "$((OTHER_IDX + 1))p")" "0.01" \
    "ACCOUNT_DAILY_COSTS carries the other day's cost too"

# ============================================================
echo "=== Test 18: An unpriced model costs zero but still counts ==="
# ============================================================
ENV18=$(setup_env "test18")
write_auth "$ENV18/.codex" 9999999999 "$(date -Iseconds)"
write_pricing_cache "$ENV18" \
    '{"gpt-5.1": {"input": 1e-05, "output": 1e-04, "cache_read": 1e-06, "cache_write": 0}}'

# codex-auto-review is the model LiteLLM does not name yet; its turns add
# tokens and no cost, and the figure heals when the table names it.
append_priced_turn "$ENV18/.codex/sessions/a.jsonl" "$TODAY" "codex-auto-review" 1000 0 500
OUTPUT18=$(run_script "$ENV18")

assert_eq "$(echo "$OUTPUT18" | grep '^TODAY_COST=' | cut -d= -f2)" "0.00" \
    "TODAY_COST=0.00 when the model is not in the table"
assert_eq "$(echo "$OUTPUT18" | grep '^WEEK_TOKENS=' | cut -d= -f2)" "1500" \
    "WEEK_TOKENS still counts the unpriced turn"
assert_match "$OUTPUT18" '^WEEK_MODELS=.*codex-auto-review=1500' \
    "WEEK_MODELS still names the unpriced model"

# ============================================================
echo "=== Test 19: A dated model snapshot prices at its base name ==="
# ============================================================
ENV19=$(setup_env "test19")
write_auth "$ENV19/.codex" 9999999999 "$(date -Iseconds)"
write_pricing_cache "$ENV19" \
    '{"gpt-4.1": {"input": 2e-05, "output": 2e-04, "cache_read": 2e-06, "cache_write": 0}}'

# A runtime name can carry the snapshot date the table's entry omits.
append_priced_turn "$ENV19/.codex/sessions/a.jsonl" "$TODAY" "gpt-4.1-2025-04-14" 1000 0 1000
OUTPUT19=$(run_script "$ENV19")

# 1000·2e-05 + 1000·2e-04 = 0.22
assert_eq "$(echo "$OUTPUT19" | grep '^TODAY_COST=' | cut -d= -f2)" "0.22" \
    "TODAY_COST strips the date suffix and prices at the base entry"

# ============================================================
echo "=== Test 20: The cache is fetched when it is absent ==="
# ============================================================
ENV20=$(setup_env "test20")
write_auth "$ENV20/.codex" 9999999999 "$(date -Iseconds)"

# A curl answering by URL: the price table from a fixture, the EUR rate from
# Frankfurter's shape, and the usage endpoint's answer for anything else.
mkdir -p "$TMPDIR_ROOT/test20"
cat > "$TMPDIR_ROOT/test20/litellm.json" << 'LITELLMEOF'
{
    "gpt-5.2": {"input_cost_per_token": 2e-05, "output_cost_per_token": 2e-04, "litellm_provider": "openai"},
    "codex-auto-review": null
}
LITELLMEOF
cat > "$TMPDIR_ROOT/test20/curl" << 'URLEOF'
#!/usr/bin/env bash
case "${*: -1}" in
    *model_prices_and_context_window.json)
        cat "${LITELLM_FIXTURE:?}" ;;
    *frankfurter*)
        echo '{"rates":{"EUR":0.9}}' ;;
    *)
        printf '%s' '{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":42,"reset_at":"2099-01-01T00:00:00Z","limit_window_seconds":18000},"secondary_window":{"used_percent":15,"reset_at":"2099-01-07T00:00:00Z","limit_window_seconds":604800}},"credits":{"balance":5,"has_credits":true}}' ;;
esac
URLEOF
chmod +x "$TMPDIR_ROOT/test20/curl"

append_priced_turn "$ENV20/.codex/sessions/a.jsonl" "$TODAY" "gpt-5.2" 1000 0 1000
OUTPUT20=$(HOME="$ENV20" CODEX_HOME="$ENV20/.codex" XDG_CACHE_HOME="$ENV20/.cache" \
    LITELLM_FIXTURE="$TMPDIR_ROOT/test20/litellm.json" \
    PATH="$TMPDIR_ROOT/test20:$TMPDIR_ROOT:$PATH" bash "$SCRIPT" 2>/dev/null)

assert_eq "$(echo "$OUTPUT20" | grep '^TODAY_COST=' | cut -d= -f2)" "0.22" \
    "TODAY_COST prices from a table fetched over the network"
assert_eq "$(echo "$OUTPUT20" | grep '^USD_EUR_RATE=' | cut -d= -f2)" "0.9" \
    "USD_EUR_RATE comes from the fetched Frankfurter answer"
if [ -f "$ENV20/.cache/dms-ai-usage/pricing.json" ]; then
    pass "the fetched prices land in the shared cache"
else
    fail "the fetched prices land in the shared cache (no cache file)"
fi
assert_eq "$(echo "$OUTPUT20" | grep '^CREDS_STATUS=' | cut -d= -f2)" "ok" \
    "pricing leaves the credential verdict alone"

# ============================================================
echo "=== Test 21: Pricing that cannot be read costs nothing ==="
# ============================================================
ENV21=$(setup_env "test21")
write_auth "$ENV21/.codex" 9999999999 "$(date -Iseconds)"
append_turn "$ENV21/.codex/sessions/a.jsonl" "$TODAY" "gpt-5-codex" 700

# A curl that never answers with a table: the refresh fails, the tokens
# still count and every cost figure reads zero.
OUTPUT21=$(HOME="$ENV21" CODEX_HOME="$ENV21/.codex" XDG_CACHE_HOME="$ENV21/.cache" \
    PATH="$TMPDIR_ROOT:$PATH" bash "$SCRIPT" 2>/dev/null)
assert_eq "$(echo "$OUTPUT21" | grep '^TODAY_COST=' | cut -d= -f2)" "0.00" \
    "TODAY_COST=0.00 when no price can be read"
assert_eq "$(echo "$OUTPUT21" | grep '^WEEK_COST=' | cut -d= -f2)" "0.00" \
    "WEEK_COST=0.00 when no price can be read"
assert_eq "$(echo "$OUTPUT21" | grep '^DAILY_COSTS=' | cut -d= -f2)" "0.00,0.00,0.00,0.00,0.00,0.00,0.00" \
    "DAILY_COSTS is a zero series when no price can be read"
assert_eq "$(echo "$OUTPUT21" | grep '^WEEK_TOKENS=' | cut -d= -f2)" "700" \
    "WEEK_TOKENS still counts when no price can be read"

# ============================================================
echo "=== Test 22: Not installed — cost keys present at zero ==="
# ============================================================
# Test 5's output carries the not-installed heredoc; the cost keys must be
# part of it, so a Source that is not present reports zeros rather than
# teaching the reader to miss the keys.
assert_eq "$(echo "$OUTPUT5" | grep '^TODAY_COST=' | cut -d= -f2)" "0.00" \
    "the not-installed answer carries TODAY_COST=0.00"
assert_eq "$(echo "$OUTPUT5" | grep '^DAILY_COSTS=' | cut -d= -f2)" "0.00,0.00,0.00,0.00,0.00,0.00,0.00" \
    "the not-installed answer carries a zero DAILY_COSTS"
assert_eq "$(echo "$OUTPUT5" | grep -c '^ACCOUNT_TODAY_COST=')" "1" \
    "the not-installed answer carries the per-Account cost keys"

# ============================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
