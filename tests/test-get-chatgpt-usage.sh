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
    HOME="$home_dir" CODEX_HOME="$home_dir/.codex" PATH="$TMPDIR_ROOT:$PATH" bash "$SCRIPT" "$@" 2>/dev/null
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

TODAY=$(date +%Y-%m-%d)
DOW=$(date +%u)  # 1=Monday, 7=Sunday

# ============================================================
echo "=== Test 1: Output format — all keys present ==="
# ============================================================
ENV1=$(setup_env "test1")
write_auth "$ENV1/.codex" 9999999999 "$(date -Iseconds)"
OUTPUT1=$(run_script "$ENV1")

EXPECTED_KEYS="PLAN_TYPE PRIMARY_UTIL PRIMARY_RESET PRIMARY_WINDOW_SECONDS SECONDARY_UTIL SECONDARY_RESET SECONDARY_WINDOW_SECONDS CREDITS_BALANCE CREDITS_HAS CREDS_STATUS WEEK_TOKENS WEEK_MESSAGES WEEK_SESSIONS MONTH_TOKENS DAILY WEEK_MODELS ACCOUNTS PROFILE_SUBSCRIPTION PROFILE_FIVE_HOUR_UTIL PROFILE_FIVE_HOUR_RESET PROFILE_SEVEN_DAY_UTIL PROFILE_SEVEN_DAY_RESET PROFILE_CREDS_STATUS PROFILE_WEEK_TOKENS PROFILE_MONTH_TOKENS PROFILE_WEEK_MESSAGES PROFILE_WEEK_SESSIONS PROFILE_DAILY PROFILE_WEEK_MODELS"
for key in $EXPECTED_KEYS; do
    if echo "$OUTPUT1" | grep -q "^${key}="; then
        pass "key $key present"
    else
        fail "key $key missing"
    fi
done

# The widget's account adapter reads PROFILE_*, so the old ACCOUNT_* namespace is
# dead output and must be gone. ACCOUNTS is the Source-level list and stays.
assert_no_match "$OUTPUT1" "^ACCOUNT_" "no per-Account ACCOUNT_* keys remain"
assert_match "$OUTPUT1" "^ACCOUNTS=" "the Source-level ACCOUNTS key stays"

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
echo "=== Test 14: Per-Account readings the widget overlays ==="
# ============================================================
# Two Accounts with different credentials and different local token counts, so
# each PROFILE_* list has something to tell them apart by.
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
assert_eq "$(echo "$OUTPUT14" | grep "^PROFILE_SUBSCRIPTION=" | cut -d= -f2)" "default:plus,work:pro" "PROFILE_SUBSCRIPTION carries each Account's plan"
assert_eq "$(echo "$OUTPUT14" | grep "^PROFILE_CREDS_STATUS=" | cut -d= -f2)" "default:ok,work:ok" "PROFILE_CREDS_STATUS carries each Account's own status"
# The primary Window is only Claude's five-hour slot by name; #29 replaces these
# Claude-shaped keys with ones each descriptor declares.
assert_eq "$(echo "$OUTPUT14" | grep "^PROFILE_FIVE_HOUR_UTIL=" | cut -d= -f2)" "default:42,work:7" "PROFILE_FIVE_HOUR_UTIL carries each Account's primary Window"
assert_eq "$(echo "$OUTPUT14" | grep "^PROFILE_FIVE_HOUR_RESET=" | cut -d= -f2)" "default:2099-01-01T00:00:00Z,work:2099-02-01T00:00:00Z" "PROFILE_FIVE_HOUR_RESET carries each Account's primary reset"
assert_eq "$(echo "$OUTPUT14" | grep "^PROFILE_SEVEN_DAY_UTIL=" | cut -d= -f2)" "default:15,work:3" "PROFILE_SEVEN_DAY_UTIL carries each Account's secondary Window"
assert_eq "$(echo "$OUTPUT14" | grep "^PROFILE_SEVEN_DAY_RESET=" | cut -d= -f2)" "default:2099-01-07T00:00:00Z,work:2099-02-07T00:00:00Z" "PROFILE_SEVEN_DAY_RESET carries each Account's secondary reset"
assert_eq "$(echo "$OUTPUT14" | grep "^PROFILE_WEEK_TOKENS=" | cut -d= -f2)" "default:100,work:300" "PROFILE_WEEK_TOKENS carries each Account's own weekly tokens"
assert_eq "$(echo "$OUTPUT14" | grep "^PROFILE_MONTH_TOKENS=" | cut -d= -f2)" "default:100,work:300" "PROFILE_MONTH_TOKENS carries each Account's own monthly tokens"
assert_eq "$(echo "$OUTPUT14" | grep "^PROFILE_WEEK_MESSAGES=" | cut -d= -f2)" "default:1,work:1" "PROFILE_WEEK_MESSAGES carries each Account's own message count"
assert_eq "$(echo "$OUTPUT14" | grep "^PROFILE_WEEK_SESSIONS=" | cut -d= -f2)" "default:1,work:1" "PROFILE_WEEK_SESSIONS carries each Account's own session count"
assert_eq "$(echo "$OUTPUT14" | grep "^PROFILE_WEEK_MODELS=" | cut -d= -f2-)" "default:gpt-5-codex=100|work:gpt-5-codex=300" "PROFILE_WEEK_MODELS carries each Account's own model breakdown"

PROFILE_DAILY14=$(echo "$OUTPUT14" | grep "^PROFILE_DAILY=" | cut -d= -f2-)
DEFAULT_DAILY14=$(echo "$PROFILE_DAILY14" | tr '|' '\n' | grep '^default:' | cut -d: -f2-)
WORK_DAILY14=$(echo "$PROFILE_DAILY14" | tr '|' '\n' | grep '^work:' | cut -d: -f2-)
assert_eq "$(echo "$DEFAULT_DAILY14" | tr ',' '\n' | sed -n "$((TODAY_IDX + 1))p")" "100" "PROFILE_DAILY carries the default Account's own daily series"
assert_eq "$(echo "$WORK_DAILY14" | tr ',' '\n' | sed -n "$((TODAY_IDX + 1))p")" "300" "PROFILE_DAILY carries the work Account's own daily series"

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
assert_eq "$(echo "$OUTPUT15" | grep "^PROFILE_CREDS_STATUS=" | cut -d= -f2)" "default:ok,work:missing" "the Account whose credentials were rejected is reported as missing beside the healthy one"
assert_eq "$(echo "$OUTPUT15" | grep "^PROFILE_FIVE_HOUR_UTIL=" | cut -d= -f2)" "default:42,work:0" "the rejected Account's own primary Window is reported, not masked by the healthy Account's"
assert_eq "$(echo "$OUTPUT15" | grep "^PROFILE_SEVEN_DAY_UTIL=" | cut -d= -f2)" "default:15,work:0" "the rejected Account's own secondary Window is reported, not masked by the healthy Account's"

# ============================================================
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
